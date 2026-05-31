import os
import time
import json
import traceback
from dotenv import load_dotenv
from core_engine.maker_service import MakerService, sanitize_filename

def main():
    print("=======================================")
    print("      AI Queue Watcher Started         ")
    print("=======================================")

    maker = MakerService()
    current_queue_file = None

    while True:
        try:
            load_dotenv(override=True)
            hot_zone = os.getenv("AI_HOTZONE")
            
            if not hot_zone:
                print("[ERROR] AI_HOTZONE not set in .env")
                time.sleep(10)
                continue
                
            queue_file = os.path.join(hot_zone, "ai_queue.json")
            
            if queue_file != current_queue_file:
                print(f"[INFO] Watching queue file: {queue_file}")
                current_queue_file = queue_file
                
            # Write Heartbeat
            status_file = os.path.join(hot_zone, "watcher_status.json")
            _atomic_write(status_file, {"status": "online", "timestamp": time.time()})

            if not os.path.exists(queue_file):
                time.sleep(10)
                continue

            with open(queue_file, "r", encoding="utf-8") as f:
                content = f.read().strip()
            
            if not content:
                time.sleep(10)
                continue

            queue_data = json.loads(content)
            
            # Find the first pending task
            pending_idx = -1
            for i, item in enumerate(queue_data):
                if item.get("status") == "pending":
                    pending_idx = i
                    break

            if pending_idx == -1:
                # Nothing to process
                time.sleep(10)
                continue

            # We have a task! Mark it as processing
            task = queue_data[pending_idx]
            task["status"] = "processing"
            task["statusText"] = "Initializing..."
            task["logs"] = ["Task picked up by Queue Watcher"]
            
            # Clean up the task title/id using LyricAgent so we get a beautiful folder name
            task_title = task.get("title", "")
            if task_title:
                try:
                    from core_engine.agents.lyric_agent import LyricAgent
                    agent = LyricAgent()
                    clean_title = agent.clean_song_query(task_title)
                    task["cleanTitle"] = clean_title
                    task["cleanId"] = sanitize_filename(clean_title)
                except Exception as e:
                    print(f"[QUEUE] Error cleaning title: {e}")
            
            _atomic_write(queue_file, queue_data)

            start_time = time.time()
            print(f"\n[QUEUE] Starting task: {task.get('title')} - {task.get('artist')}")
            
            def update_progress(msg):
                try:
                    with open(queue_file, "r", encoding="utf-8") as f:
                        q = json.loads(f.read().strip())
                    for i, item in enumerate(q):
                        if item.get("id") == task.get("id"):
                            q[i]["statusText"] = msg
                            if "logs" not in q[i]:
                                q[i]["logs"] = []
                                
                            elapsed = time.time() - start_time
                            mins, secs = divmod(elapsed, 60)
                            time_str = f"[{int(mins):02d}:{int(secs):02d}] "
                            formatted_msg = time_str + msg
                            
                            q[i]["logs"].append(formatted_msg)
                            break
                    _atomic_write(queue_file, q)
                except Exception as e:
                    print(f"[QUEUE] Error updating progress: {e}")
            
            # Generate a safe folder name (song_id) for the processing directory
            clean_id = task.get("cleanId", "")
            task_id = str(task.get("id", ""))
            
            if clean_id:
                song_id = sanitize_filename(clean_id)
            elif task_id:
                song_id = sanitize_filename(task_id)
            else:
                safe_title = sanitize_filename(task.get("title", "Unknown_Title"))
                safe_artist = sanitize_filename(task.get("artist", "Unknown_Artist"))
                song_id = f"{safe_title} - {safe_artist}"

            # Run Maker Service
            try:
                # We can use process_specific_song to leverage the provided URL directly
                url = task.get("url")
                lyrics_text = task.get("lyricsText")
                lyrics_type = task.get("lyricsType", "txt")
                
                # If it's a local file, handle differently
                local_path = None
                if task.get("sourceType", "").lower() == "localdirectory":
                    local_path = url
                    url = None

                # Handle fetchOriginalAudio
                if task.get("fetchOriginalAudio", False):
                    print(f"[WAIT] Fetch original audio requested. Ignoring local file and searching web...")
                    url = None
                    local_path = None
                    search_query = task.get("cleanTitle") or task.get("title")
                    results = maker.get_search_results(search_query)
                    best = next((r for r in results if r.get('recommended')), None)
                    if best:
                        url = best['url']
                        print(f"[OK] Found web audio: {url}")
                    else:
                        print(f"[ERROR] Failed to find web audio for {search_query}")
                
                success = maker.process_specific_song(
                    song_id=song_id,
                    url=url,
                    local_audio_path=local_path,
                    lyrics_text=lyrics_text,
                    lyrics_type=lyrics_type,
                    progress_callback=update_progress
                )
                
                task["status"] = "done" if success else "failed"
                task["statusText"] = "Completed" if success else "Failed"
                print(f"[QUEUE] Task finished with status: {task['status']}")
            except Exception as e:
                print(f"[QUEUE] Task failed with exception: {e}")
                traceback.print_exc()
                task["status"] = "failed"
                task["statusText"] = "Error"
            
            # Re-read the queue file just in case it was modified externally while processing
            with open(queue_file, "r", encoding="utf-8") as f:
                fresh_queue = json.loads(f.read().strip())
                
            # Update the specific task in the freshly loaded queue to prevent overwriting new additions
            for i, item in enumerate(fresh_queue):
                if item.get("id") == task.get("id"):
                    fresh_queue[i]["status"] = task["status"]
                    fresh_queue[i]["statusText"] = task["statusText"]
                    break
                    
            _atomic_write(queue_file, fresh_queue)

        except Exception as e:
            print(f"[WATCHER ERROR] {e}")
            time.sleep(10)
            continue

        # Short sleep before checking for the next task
        time.sleep(2)
        
        # Write heartbeat during sleep cycles as well
        if current_queue_file and os.path.exists(os.path.dirname(current_queue_file)):
            status_file = os.path.join(os.path.dirname(current_queue_file), "watcher_status.json")
            _atomic_write(status_file, {"status": "online", "timestamp": time.time()})

def _atomic_write(filepath, data):
    temp_path = f"{filepath}.tmp"
    with open(temp_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4)
    # Windows atomic replace
    os.replace(temp_path, filepath)

if __name__ == "__main__":
    main()
