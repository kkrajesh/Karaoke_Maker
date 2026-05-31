import os
import sys
import json
import time
import requests
import traceback
import argparse
from dotenv import load_dotenv

# Ensure core_engine module can be imported
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from core_engine.maker_service import MakerService, sanitize_filename

def main():
    parser = argparse.ArgumentParser(description="Task Worker for Karaoke Orchestrator")
    parser.add_argument("--task-id", required=True, help="The ID of the task to process")
    parser.add_argument("--orchestrator-url", default="http://127.0.0.1:5000", help="URL of the Orchestrator")
    args = parser.parse_args()
    
    task_id = args.task_id
    base_url = args.orchestrator_url
    
    # Notify Orchestrator that task started
    def update_progress(msg):
        try:
            requests.post(f"{base_url}/internal/queue/{task_id}/log", json={"message": msg}, timeout=2)
        except Exception as e:
            print(f"[WORKER ERROR] Failed to send progress update: {e}")

    try:
        # Fetch full task details from Orchestrator
        resp = requests.get(f"{base_url}/queue/{task_id}", timeout=5)
        if resp.status_code != 200:
            print(f"[WORKER ERROR] Task not found on orchestrator: {task_id}")
            return
            
        task = resp.json()
        maker = MakerService()
        
        # Clean up title for folder generation
        task_title = task.get("title", "")
        clean_title = task_title
        clean_id = task.get("clean_id", "")
        
        if task_title and not clean_title:
            try:
                from core_engine.agents.lyric_agent import LyricAgent
                agent = LyricAgent()
                clean_title = agent.clean_song_query(task_title)
                clean_id = sanitize_filename(clean_title)
                # Update orchestrator with clean info
                requests.patch(f"{base_url}/internal/queue/{task_id}", json={"clean_title": clean_title, "clean_id": clean_id}, timeout=2)
            except Exception as e:
                print(f"[WORKER] Error cleaning title: {e}")
        
        update_progress("Initializing...")
        
        # Generate safe folder name
        if clean_id:
            song_id = sanitize_filename(clean_id)
        elif task_id:
            song_id = sanitize_filename(task_id)
        else:
            safe_title = sanitize_filename(task.get("title", "Unknown_Title"))
            safe_artist = sanitize_filename(task.get("artist", "Unknown_Artist"))
            song_id = f"{safe_title} - {safe_artist}"

        # Setup parameters
        url = task.get("url")
        lyrics_text = task.get("lyrics_text")
        lyrics_type = task.get("lyrics_type", "txt")
        local_path = None
        
        if task.get("source_type", "").lower() == "localdirectory":
            local_path = url
            url = None
            
        if task.get("fetch_original_audio", False):
            update_progress("Fetch original audio requested. Ignoring local file and searching web...")
            url = None
            local_path = None
            search_query = clean_title or task_title
            results = maker.get_search_results(search_query)
            best = next((r for r in results if r.get('recommended')), None)
            if best:
                url = best['url']
                update_progress(f"Found web audio: {url}")
            else:
                update_progress(f"Failed to find web audio for {search_query}")
                
        # Execute processing
        success = maker.process_specific_song(
            song_id=song_id,
            url=url,
            local_audio_path=local_path,
            lyrics_text=lyrics_text,
            lyrics_type=lyrics_type,
            progress_callback=update_progress
        )
        
        final_status = "done" if success else "failed"
        final_msg = "Completed" if success else "Failed"
        
        requests.post(f"{base_url}/internal/queue/{task_id}/status", json={"status": final_status, "status_text": final_msg}, timeout=2)

    except Exception as e:
        print(f"[WORKER] Task failed with exception: {e}")
        traceback.print_exc()
        try:
            requests.post(f"{base_url}/internal/queue/{task_id}/status", json={"status": "failed", "status_text": "Error"}, timeout=2)
        except:
            pass

if __name__ == "__main__":
    main()
