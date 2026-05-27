import os
import sys
import threading
from flask import Flask, request, jsonify
from flask_cors import CORS
from dotenv import load_dotenv

# Add parent dir to sys.path to resolve module imports properly
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Load env from parent directory before importing services
env_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), '.env')
load_dotenv(dotenv_path=env_path)

from core_engine.maker_service import MakerService
from core_engine.agents.lyric_agent import LyricAgent

app = Flask(__name__)
CORS(app)

maker = MakerService()
lyric_agent = LyricAgent()

# In-memory store for background tasks
tasks = {}

@app.route('/search', methods=['GET'])
def search():
    query = request.args.get('q')
    if not query:
        return jsonify({"error": "Query parameter 'q' is required"}), 400
        
    try:
        results = maker.get_search_results(query)
        return jsonify({"results": results})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/lyrics', methods=['GET'])
def fetch_lyrics():
    query = request.args.get('q')
    if not query:
        return jsonify({"error": "Query parameter 'q' is required"}), 400
        
    try:
        # We don't save it yet, just fetch
        lyrics = lyric_agent.fetch_lyrics(query)
        return jsonify({"lyrics": lyrics})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/process', methods=['POST'])
def process_song():
    data = request.json
    song_id = data.get('song_id')
    url = data.get('url')
    local_audio_path = data.get('local_audio_path')
    lyrics_text = data.get('lyrics_text')
    lyrics_type = data.get('lyrics_type', 'txt')
    
    if not song_id:
        return jsonify({"error": "song_id is required"}), 400
        
    if not url and not local_audio_path:
        return jsonify({"error": "Either url or local_audio_path is required"}), 400

    task_id = song_id
    tasks[task_id] = {"status": "processing"}

    def run_task():
        try:
            success = maker.process_specific_song(
                song_id=song_id,
                url=url,
                local_audio_path=local_audio_path,
                lyrics_text=lyrics_text,
                lyrics_type=lyrics_type
            )
            tasks[task_id] = {"status": "completed" if success else "failed"}
            if success:
                print(f"[OK] Processing completely finished for {song_id}")
        except Exception as e:
            print(f"Task error: {e}")
            tasks[task_id] = {"status": "failed", "error": str(e)}

    thread = threading.Thread(target=run_task)
    thread.start()
    
    return jsonify({"message": "Processing started", "task_id": task_id})

@app.route('/reprocess', methods=['POST'])
def reprocess_component():
    data = request.json
    song_id = data.get('song_id')
    title = data.get('title')
    component = data.get('component') # 'vocals', 'instrumental', 'pitch', 'map', 'lyrics'
    lyrics_text = data.get('lyrics_text')
    lyrics_type = data.get('lyrics_type', 'txt')

    if not song_id or not component:
        return jsonify({"error": "song_id and component are required"}), 400

    target_dir = None
    hotzone = os.getenv("AI_HOTZONE", ".")
    vault = os.getenv("AI_VAULT", ".")
    
    # Check HotZone then Vault
    import glob
    for base_dir in [hotzone, vault]:
        # Exact match
        exact_path = os.path.join(base_dir, str(song_id))
        if os.path.exists(exact_path):
            target_dir = exact_path
            break
            
        # Prefix match (Phase 8)
        matches = glob.glob(os.path.join(base_dir, f"{song_id}_*"))
        if matches and os.path.isdir(matches[0]):
            target_dir = matches[0]
            break
            
        # Legacy match
        if title:
            from core_engine.maker_service import sanitize_filename
            legacy_dir = os.path.join(base_dir, sanitize_filename(title).replace(" ", "_"))
            if os.path.exists(legacy_dir):
                target_dir = legacy_dir
                break

    if not target_dir or not os.path.exists(target_dir):
        return jsonify({"error": f"Song directory not found for ID {song_id} or Title {title} in HotZone or Vault"}), 404

    # Delete files based on component
    import glob
    files_to_delete = []
    if component in ['vocals', 'instrumental']:
        files_to_delete.extend(glob.glob(os.path.join(target_dir, "*vocals.wav")))
        files_to_delete.extend(glob.glob(os.path.join(target_dir, "*instrumental.wav")))
    elif component == 'pitch':
        files_to_delete.extend(glob.glob(os.path.join(target_dir, "*pitch_profile.json")))
    elif component == 'map':
        files_to_delete.extend(glob.glob(os.path.join(target_dir, "*vocal_map.json")))
    elif component == 'lyrics':
        files_to_delete.extend(glob.glob(os.path.join(target_dir, "*lyrics_english.*")))
        files_to_delete.extend(glob.glob(os.path.join(target_dir, "*lyrics_meaning.*")))

    for f in files_to_delete:
        path = os.path.join(target_dir, os.path.basename(f))
        if os.path.exists(path):
            try:
                os.remove(path)
            except Exception as e:
                print(f"Failed to delete {path}: {e}")

    task_id = f"{song_id}_reprocess_{component}"
    tasks[task_id] = {"status": "processing"}

    def run_task():
        try:
            skip_audio = component == 'lyrics'
            success = maker.process_specific_song(
                song_id=song_id,
                url=None, # It will use existing local original.wav
                local_audio_path=os.path.join(target_dir, "original.wav"),
                lyrics_text=lyrics_text,
                lyrics_type=lyrics_type,
                target_dir_override=target_dir,
                skip_audio=skip_audio
            )
            tasks[task_id] = {"status": "completed" if success else "failed"}
            if success:
                print(f"[OK] Processing completely finished for {song_id}")
        except Exception as e:
            print(f"Task error: {e}")
            tasks[task_id] = {"status": "failed", "error": str(e)}

    thread = threading.Thread(target=run_task)
    thread.start()
    
    return jsonify({"message": f"Reprocessing {component} started", "task_id": task_id})

@app.route('/generate-practice-mp3', methods=['POST'])
def generate_practice_mp3():
    data = request.json
    song_id = data.get('song_id')
    
    if not song_id:
        return jsonify({"error": "song_id is required"}), 400

    target_dir = None
    hotzone = os.getenv("AI_HOTZONE", ".")
    vault = os.getenv("AI_VAULT", ".")
    
    import glob
    for base_dir in [hotzone, vault]:
        exact_path = os.path.join(base_dir, str(song_id))
        if os.path.exists(exact_path):
            target_dir = exact_path
            break
        matches = glob.glob(os.path.join(base_dir, f"{song_id}_*"))
        if matches and os.path.isdir(matches[0]):
            target_dir = matches[0]
            break

    if not target_dir or not os.path.exists(target_dir):
        return jsonify({"error": f"Song directory not found for ID {song_id}"}), 404

    task_id = f"{song_id}_gen_mp3"
    tasks[task_id] = {"status": "processing"}

    def run_task():
        try:
            from core_engine.mp3_generator import PracticeMp3Generator
            generator = PracticeMp3Generator(target_dir, ffmpeg_path=os.getenv("FFMPEG_PATH", "ffmpeg"))
            success, msg = generator.generate_all()
            tasks[task_id] = {"status": "completed" if success else "failed", "message": msg}
            if success:
                print(f"[OK] MP3 Generation finished for {song_id}: {msg}")
            else:
                print(f"[ERROR] MP3 Generation failed for {song_id}: {msg}")
        except Exception as e:
            print(f"Task error: {e}")
            tasks[task_id] = {"status": "failed", "error": str(e)}

    thread = threading.Thread(target=run_task)
    thread.start()
    
    return jsonify({"message": "MP3 generation started", "task_id": task_id})


@app.route('/status/<task_id>', methods=['GET'])
def get_status(task_id):
    task = tasks.get(task_id)
    if not task:
        return jsonify({"error": "Task not found"}), 404
    return jsonify(task)

if __name__ == '__main__':
    print("Starting Karaoke Maker API Server on port 5000...")
    app.run(host='127.0.0.1', port=5000, debug=False)
