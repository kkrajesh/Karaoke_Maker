import os
import sys
import json
import time
import asyncio
import sqlite3
import subprocess
import traceback
from contextlib import asynccontextmanager
from typing import List, Optional, Dict, Any

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from dotenv import load_dotenv

# Add parent dir to sys.path to resolve module imports properly
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Load env from parent directory before importing services
env_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), '.env')
load_dotenv(dotenv_path=env_path)

from core_engine.maker_service import MakerService
from core_engine.metadata_service import MetadataService
from core_engine.agents.lyric_agent import LyricAgent
from core_engine.config import get_mm_db_path

maker = MakerService()
lyric_agent = LyricAgent()

# Database setup
AI_VAULT = os.getenv("AI_VAULT", ".")
DB_PATH = os.path.join(AI_VAULT, "vox_ai_metadata.db")

def init_db():
    print(f"[init_db] DB_PATH is {DB_PATH}")
    try:
        if not os.path.exists(AI_VAULT):
            os.makedirs(AI_VAULT, exist_ok=True)
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute('PRAGMA journal_mode=DELETE;')
        c.execute('''
            CREATE TABLE IF NOT EXISTS queue_items (
                id TEXT PRIMARY KEY,
                title TEXT,
                artist TEXT,
                url TEXT,
                source_type TEXT,
                status TEXT,
                progress REAL,
                status_text TEXT,
                lyrics_text TEXT,
                lyrics_type TEXT,
                clean_id TEXT,
                clean_title TEXT,
                fetch_original_audio INTEGER,
                force_reprocess INTEGER DEFAULT 0,
                reprocess_component TEXT DEFAULT 'all',
                original_title TEXT,
                logs TEXT
            )
        ''')
        
        c.execute('''
            CREATE TABLE IF NOT EXISTS ai_artifacts (
                mm_id TEXT PRIMARY KEY,
                title TEXT,
                has_vocals INTEGER,
                has_instrumental INTEGER,
                has_pitch_data INTEGER,
                has_vocal_map INTEGER,
                has_lyrics INTEGER,
                last_processed TEXT
            )
        ''')
        
        # Add force_reprocess column if it doesn't exist
        try:
            c.execute("ALTER TABLE queue_items ADD COLUMN force_reprocess INTEGER DEFAULT 0")
        except sqlite3.OperationalError:
            pass # Column already exists
            
        try:
            c.execute("ALTER TABLE queue_items ADD COLUMN reprocess_component TEXT DEFAULT 'all'")
        except sqlite3.OperationalError:
            pass
            
        try:
            c.execute("ALTER TABLE queue_items ADD COLUMN original_title TEXT")
        except sqlite3.OperationalError:
            pass
        
        # Reset any stuck tasks from a previous run
        c.execute("UPDATE queue_items SET status='failed', status_text='Worker crashed or server restarted' WHERE status='processing' OR status='pending'")
        
        conn.commit()
        conn.close()
        print("[init_db] Successfully created tables.")
    except Exception as e:
        print(f"[init_db] ERROR initializing DB: {e}")
        traceback.print_exc()

# Initialize DB synchronously on module load to guarantee table exists
init_db()

# Connection Manager for WebSockets
class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

    async def broadcast(self, message: dict):
        dead_connections = []
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except Exception:
                dead_connections.append(connection)
        for dead in dead_connections:
            self.disconnect(dead)

manager = ConnectionManager()

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    init_db()
    print("[Orchestrator] Started. Database initialized.")
    watcher_task = asyncio.create_task(cloud_queue_watcher())
    yield
    # Shutdown
    watcher_task.cancel()
    print("[Orchestrator] Shutting down.")

app = FastAPI(lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---- Helper DB functions ----
def row_to_dict(row, cursor):
    d = {}
    for i, col in enumerate(cursor.description):
        val = row[i]
        if col[0] == 'fetch_original_audio':
            val = bool(val)
        if col[0] == 'logs':
            try:
                val = json.loads(val) if val else []
            except:
                val = []
        d[col[0]] = val
    # Map snake_case back to camelCase for Flutter
    return {
        "id": d.get("id"),
        "title": d.get("title"),
        "artist": d.get("artist"),
        "url": d.get("url"),
        "sourceType": d.get("source_type"),
        "status": d.get("status"),
        "progress": d.get("progress"),
        "statusText": d.get("status_text"),
        "lyricsText": d.get("lyrics_text"),
        "lyricsType": d.get("lyrics_type"),
        "cleanId": d.get("clean_id"),
        "cleanTitle": d.get("clean_title"),
        "fetchOriginalAudio": bool(d.get("fetch_original_audio")),
        "forceReprocess": bool(d.get("force_reprocess")),
        "reprocessComponent": d.get("reprocess_component", "all"),
        "originalTitle": d.get("original_title"),
        "logs": d.get("logs")
    }

# ---- Models ----
class QueueItemCreate(BaseModel):
    id: str
    title: str
    artist: str
    url: str
    sourceType: str
    lyricsText: Optional[str] = None
    lyricsType: Optional[str] = None
    fetchOriginalAudio: Optional[bool] = False
    forceReprocess: Optional[bool] = False
    reprocessComponent: Optional[str] = "all"

class QueueStatusUpdate(BaseModel):
    status: str

# ---- Endpoints ----
@app.get("/health")
def health_check():
    return {"status": "online"}

@app.get("/search")
def search(q: str):
    try:
        results = maker.get_search_results(q)
        return {"results": results}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/local-search")
def local_search(q: str):
    try:
        mm_db_path = get_mm_db_path()
        if not os.path.exists(mm_db_path):
            return []
            
        conn = sqlite3.connect(mm_db_path)
        # Register dummy collations just in case
        conn.create_collation("IUNICODE", lambda a, b: 0)
        conn.create_collation("NUMERIC", lambda a, b: 0)
        
        c = conn.cursor()
        
        words = [w for w in q.strip().split() if w]
        if not words:
            return []
            
        where_clauses = []
        params = []
        for word in words:
            where_clauses.append('(s.SongTitle LIKE ? OR s.Artist LIKE ? OR a.Album LIKE ?)')
            pattern = f'%{word}%'
            params.extend([pattern, pattern, pattern])
            
        where_sql = " AND ".join(where_clauses)
        
        sql = f'''
            SELECT s.ID, s.Artist, s.SongTitle, s.SongPath, s.Extension, m.DriveLetter,
                   s.SongLength, s.Bitrate, a.Album
            FROM Songs s
            LEFT JOIN Medias m ON s.IDMedia = m.IDMedia
            LEFT JOIN Albums a ON s.IDAlbum = a.ID
            WHERE {where_sql}
              AND (s.Extension IS NULL OR s.Extension = '' OR LOWER(s.Extension) IN ('mp4', 'mkv', 'avi', 'mp3', 'wav', 'm4a', 'flac'))
            LIMIT 50
        '''
        
        c.execute(sql, params)
        rows = c.fetchall()
        
        results = []
        for row in rows:
            song_id = str(row[0]) if row[0] is not None else ''
            artist = row[1] if row[1] else 'Unknown Artist'
            title = row[2] if row[2] else 'Unknown Title'
            song_path = row[3] if row[3] else ''
            drive_letter_num = row[5]
            song_length = row[6]
            bitrate = row[7]
            album = row[8]
            
            full_path = song_path
            if drive_letter_num is not None and song_path.startswith(':\\'):
                drive_char = chr(drive_letter_num + 65)
                full_path = f"{drive_char}{song_path}"
                
            metadata = {}
            if album: metadata['album'] = album
            if bitrate:
                if bitrate > 1000: metadata['bitrate'] = round(bitrate / 1000)
                elif bitrate > 0: metadata['bitrate'] = bitrate
                
            has_ai_content = False
            # Check if exists in AI_VAULT
            target_dir = os.path.join(AI_VAULT, song_id)
            if os.path.exists(target_dir):
                has_ai_content = True
                
            results.append({
                "id": song_id,
                "title": title,
                "artist": artist,
                "url": full_path,
                "previewUrl": full_path,
                "durationMs": song_length,
                "metadata": metadata,
                "mmId": song_id,
                "hasAiContent": has_ai_content
            })
            
        conn.close()
        return results
    except Exception as e:
        print(f"Error in local-search: {e}")
        return []

@app.get("/lyrics")
def fetch_lyrics(q: str):
    try:
        lyrics = lyric_agent.fetch_lyrics(q)
        return {"lyrics": lyrics}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/standardize-title")
def standardize_title(q: str):
    meta = MetadataService.search_metadata(q)
    if meta:
        return meta.to_dict()
    return {}

# ---- Queue Endpoints ----
@app.get("/queue")
def get_queue():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('SELECT * FROM queue_items ORDER BY rowid DESC')
    rows = c.fetchall()
    items = [row_to_dict(row, c) for row in rows]
    conn.close()
    return items

@app.get("/queue/{task_id}")
def get_queue_item(task_id: str):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('SELECT * FROM queue_items WHERE id = ?', (task_id,))
    row = c.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Task not found")
    item = row_to_dict(row, c)
    conn.close()
    return item

async def enqueue_task_internal(item: QueueItemCreate):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    
    # Check if exists and is pending/processing/done
    c.execute('SELECT status FROM queue_items WHERE id = ?', (item.id,))
    row = c.fetchone()
    if row:
        status = row[0]
        if status in ['pending', 'processing', 'audio_ready']:
            return None
        else:
            c.execute('DELETE FROM queue_items WHERE id = ?', (item.id,))
            
    # Perform intelligent standardization
    original_title = item.title
    meta = MetadataService.search_metadata(original_title)
    if meta:
        item.title = " | ".join(filter(None, [meta.title, meta.album, meta.year, meta.artist]))
        if meta.artist:
            item.artist = meta.artist

    c.execute('''
        INSERT INTO queue_items (id, title, artist, url, source_type, status, status_text, lyrics_text, lyrics_type, fetch_original_audio, force_reprocess, reprocess_component, original_title, logs)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', (item.id, item.title, item.artist, item.url, item.sourceType, 'pending', 'Queued', item.lyricsText, item.lyricsType, int(item.fetchOriginalAudio), int(item.forceReprocess), item.reprocessComponent, original_title, '[]'))
    conn.commit()
    conn.close()
    
    await manager.broadcast({"action": "add", "item": {
        "id": item.id, "title": item.title, "artist": item.artist, "url": item.url, 
        "sourceType": item.sourceType, "status": "pending", "statusText": "Queued",
        "fetchOriginalAudio": item.fetchOriginalAudio, "originalTitle": original_title, "logs": []
    }})
    return item.id

@app.post("/queue")
async def add_to_queue(item: QueueItemCreate, background_tasks: BackgroundTasks):
    task_id = await enqueue_task_internal(item)
    if task_id:
        background_tasks.add_task(spawn_worker, task_id)
        return {"message": "Added to queue", "id": task_id}
    return {"message": "Item already in queue", "id": item.id}

CLOUD_QUEUE_PATH = os.path.join(AI_VAULT, "ai_task_queue.jsonl")

async def cloud_queue_watcher():
    print(f"[CloudQueue] Watching {CLOUD_QUEUE_PATH} for offline tasks...")
    last_processed_line = 0
    # We intentionally start from line 0. Any tasks already processed are safely skipped by the DB check below.
    while True:
        try:
            if os.path.exists(CLOUD_QUEUE_PATH):
                with open(CLOUD_QUEUE_PATH, 'r', encoding='utf-8') as f:
                    lines = f.readlines()
                    if len(lines) > last_processed_line:
                        for idx in range(last_processed_line, len(lines)):
                            line = lines[idx].strip()
                            if not line: continue
                            try:
                                data = json.loads(line)
                                item = QueueItemCreate(**data)
                                
                                # Verify if already in DB to prevent duplicate processing on restart edge cases
                                conn = sqlite3.connect(DB_PATH)
                                c = conn.cursor()
                                c.execute('SELECT id FROM queue_items WHERE id = ?', (item.id,))
                                row = c.fetchone()
                                conn.close()
                                
                                if not row:
                                    print(f"[CloudQueue] Found new task from cloud: {item.title}")
                                    task_id = await enqueue_task_internal(item)
                                    if task_id:
                                        asyncio.create_task(spawn_worker(task_id))
                            except Exception as e:
                                print(f"[CloudQueue] Failed to process line {idx}: {e}")
                        last_processed_line = len(lines)
        except Exception as e:
            print(f"[CloudQueue] Error watching file: {e}")
            
        await asyncio.sleep(5)
        
    # Broadcast new item

@app.delete("/queue/completed")
async def clear_completed():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("DELETE FROM queue_items WHERE status IN ('done', 'failed', 'cancelled')")
    conn.commit()
    conn.close()
    await manager.broadcast({"action": "clear_completed"})
    return {"message": "Completed items cleared"}

@app.delete("/queue/{task_id}")
async def remove_item(task_id: str):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("DELETE FROM queue_items WHERE id = ?", (task_id,))
    conn.commit()
    conn.close()
    await manager.broadcast({"action": "remove", "id": task_id})
    return {"message": "Item removed"}

@app.patch("/queue/{task_id}/status")
async def update_item_status(task_id: str, payload: QueueStatusUpdate, background_tasks: BackgroundTasks):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('UPDATE queue_items SET status = ? WHERE id = ?', (payload.status, task_id))
    conn.commit()
    conn.close()
    
    await manager.broadcast({"action": "update", "id": task_id, "status": payload.status})
    
    if payload.status == "pending":
        background_tasks.add_task(spawn_worker, task_id)
        
    return {"message": "Status updated"}

# ---- Internal Worker Endpoints ----
@app.post("/internal/queue/{task_id}/log")
async def update_log(task_id: str, request: Request):
    data = await request.json()
    msg = data.get("message", "")
    
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('SELECT logs, status FROM queue_items WHERE id = ?', (task_id,))
    row = c.fetchone()
    if not row:
        conn.close()
        return {"error": "Task not found"}
        
    logs = json.loads(row[0]) if row[0] else []
    
    logs.append(msg)
    status = "processing" if row[1] == "pending" else row[1]
    
    c.execute('UPDATE queue_items SET logs = ?, status_text = ?, status = ? WHERE id = ?', 
              (json.dumps(logs), msg, status, task_id))
    conn.commit()
    conn.close()
    
    await manager.broadcast({"action": "update", "id": task_id, "statusText": msg, "log": msg, "status": status})
    return {"message": "Log updated"}

import shutil
import re

def sanitize_title(title: str) -> str:
    return re.sub(r'[\\/:*?"<>|]', '', title)

def partial_finalize_artifact(task_id: str):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('SELECT title, clean_title, clean_id FROM queue_items WHERE id = ?', (task_id,))
    row = c.fetchone()
    if not row:
        conn.close()
        return
        
    title, clean_title, clean_id = row
    
    # Use clean_title if available, otherwise fallback to raw title
    final_title = clean_title if clean_title else title
    clean_title_str = sanitize_title(final_title)
    
    # Locate HotZone source
    AI_HOTZONE = os.getenv("AI_HOTZONE", "C:/Data/Rajesh/Karaoke_HotZone")
    source_dir = os.path.join(AI_HOTZONE, task_id)
    if not os.path.exists(source_dir) and clean_id:
        source_dir = os.path.join(AI_HOTZONE, clean_id)
    if not os.path.exists(source_dir) and clean_title:
        source_dir = os.path.join(AI_HOTZONE, clean_title)
        
    if not os.path.exists(source_dir):
        print(f"[PartialFinalize] Could not find HotZone files for {task_id}")
        conn.close()
        return
        
    # Determine Vault Path
    vault_dir = None
    folder_name = None
    prefix = None
    
    for d in os.listdir(AI_VAULT):
        if os.path.isdir(os.path.join(AI_VAULT, d)) and (d == task_id or d.startswith(f"{task_id}_")):
            folder_name = d
            prefix = d
            vault_dir = os.path.join(AI_VAULT, d)
            break
            
    if not vault_dir:
        if task_id == clean_title_str or task_id == final_title:
            folder_name = task_id
            prefix = task_id
        else:
            folder_name = f"{task_id}_{clean_title_str}"
            prefix = f"{task_id}_{clean_title_str}"
        vault_dir = os.path.join(AI_VAULT, folder_name)
        
    os.makedirs(vault_dir, exist_ok=True)
    
    has_inst = has_voc = 0
    
    # Move files
    try:
        for filename in os.listdir(source_dir):
            if filename in ["original.wav", "instrumental.wav", "vocals.wav"]:
                src = os.path.join(source_dir, filename)
                if os.path.isfile(src):
                    new_filename = filename if filename.startswith(f"{task_id}_") else f"{task_id}_{filename}"
                    if not filename.startswith(prefix):
                        new_filename = f"{prefix}_{filename}"
                    else:
                        new_filename = filename
                    
                    shutil.copy2(src, os.path.join(vault_dir, new_filename))
                    
                    if "instrumental.wav" in filename: has_inst = 1
                    if "vocals.wav" in filename: has_voc = 1
                
        # Insert artifact tracking (only update what we know, don't overwrite lyrics/pitch if they exist)
        # We use an upsert that coalesces existing values for non-audio fields
        c.execute('''
            INSERT INTO ai_artifacts (mm_id, title, has_vocals, has_instrumental, has_pitch_data, has_vocal_map, has_lyrics, last_processed)
            VALUES (?, ?, ?, ?, 0, 0, 0, CURRENT_TIMESTAMP)
            ON CONFLICT(mm_id) DO UPDATE SET
                has_vocals=excluded.has_vocals,
                has_instrumental=excluded.has_instrumental,
                last_processed=CURRENT_TIMESTAMP
        ''', (task_id, final_title, has_voc, has_inst))
        conn.commit()
        
        # Generate vox_meta.json for Flutter
        from datetime import datetime
        meta_json_path = os.path.join(vault_dir, 'vox_meta.json')
        meta_data = {
            'mm_id': task_id,
            'title': final_title,
            'has_vocals': has_voc,
            'has_instrumental': has_inst,
            'has_pitch_data': 0,
            'has_vocal_map': 0,
            'has_lyrics': 0,
            'last_processed': datetime.now().isoformat()
        }
        
        # If it exists, preserve pitch/lyrics fields
        if os.path.exists(meta_json_path):
            try:
                with open(meta_json_path, 'r', encoding='utf-8') as f:
                    existing = json.load(f)
                meta_data['has_pitch_data'] = existing.get('has_pitch_data', 0)
                meta_data['has_vocal_map'] = existing.get('has_vocal_map', 0)
                meta_data['has_lyrics'] = existing.get('has_lyrics', 0)
            except Exception:
                pass
                
        with open(meta_json_path, 'w', encoding='utf-8') as f:
            json.dump(meta_data, f, indent=2)
        
        # Do NOT cleanup HotZone
        print(f"[PartialFinalize] Task {task_id} audio stems copied to AI_Vault.")
    except Exception as e:
        print(f"[PartialFinalize] Error during migration: {e}")
        
    conn.close()

def finalize_artifact(task_id: str):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('SELECT title, clean_title, clean_id FROM queue_items WHERE id = ?', (task_id,))
    row = c.fetchone()
    if not row:
        conn.close()
        return
        
    title, clean_title, clean_id = row
    
    # Use clean_title if available, otherwise fallback to raw title
    final_title = clean_title if clean_title else title
    clean_title_str = sanitize_title(final_title)
    
    # Locate HotZone source
    AI_HOTZONE = os.getenv("AI_HOTZONE", "C:/Data/Rajesh/Karaoke_HotZone")
    source_dir = os.path.join(AI_HOTZONE, task_id)
    if not os.path.exists(source_dir) and clean_id:
        source_dir = os.path.join(AI_HOTZONE, clean_id)
    if not os.path.exists(source_dir) and clean_title:
        source_dir = os.path.join(AI_HOTZONE, clean_title)
        
    if not os.path.exists(source_dir):
        print(f"[Finalize] Could not find HotZone files for {task_id}")
        conn.close()
        return
        
    # Determine Vault Path
    vault_dir = None
    folder_name = None
    prefix = None
    
    for d in os.listdir(AI_VAULT):
        if os.path.isdir(os.path.join(AI_VAULT, d)) and (d == task_id or d.startswith(f"{task_id}_")):
            folder_name = d
            prefix = d
            vault_dir = os.path.join(AI_VAULT, d)
            break
            
    if not vault_dir:
        if task_id == clean_title_str or task_id == final_title:
            folder_name = task_id
            prefix = task_id
        else:
            folder_name = f"{task_id}_{clean_title_str}"
            prefix = f"{task_id}_{clean_title_str}"
        vault_dir = os.path.join(AI_VAULT, folder_name)
        
    os.makedirs(vault_dir, exist_ok=True)
    
    has_inst = has_voc = has_pitch = has_map = has_lyr = 0
    
    # Preserve existing artifact flags from vox_meta.json
    meta_json_path = os.path.join(vault_dir, 'vox_meta.json')
    if os.path.exists(meta_json_path):
        try:
            with open(meta_json_path, 'r', encoding='utf-8') as f:
                existing = json.load(f)
            has_inst = int(existing.get('has_instrumental', 0))
            has_voc = int(existing.get('has_vocals', 0))
            has_pitch = int(existing.get('has_pitch_data', 0))
            has_map = int(existing.get('has_vocal_map', 0))
            has_lyr = int(existing.get('has_lyrics', 0))
        except Exception:
            pass
    
    # Move files
    try:
        for filename in os.listdir(source_dir):
            src = os.path.join(source_dir, filename)
            if os.path.isfile(src):
                new_filename = filename if filename.startswith(f"{task_id}_") else f"{task_id}_{filename}"
                # If using the strict prefix:
                if not filename.startswith(prefix):
                    new_filename = f"{prefix}_{filename}"
                else:
                    new_filename = filename
                
                shutil.copy2(src, os.path.join(vault_dir, new_filename))
                
                if "instrumental.wav" in filename: has_inst = 1
                if "vocals.wav" in filename: has_voc = 1
                if "pitch_profile.json" in filename: has_pitch = 1
                if "vocal_map.json" in filename: has_map = 1
                if "lyrics_native" in filename or "lyrics_english" in filename: has_lyr = 1
                
        # Insert artifact tracking
        c.execute('''
            INSERT OR REPLACE INTO ai_artifacts 
            (mm_id, title, has_vocals, has_instrumental, has_pitch_data, has_vocal_map, has_lyrics, last_processed)
            VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ''', (task_id, final_title, has_voc, has_inst, has_pitch, has_map, has_lyr))
        conn.commit()
        
        # Cleanup HotZone
        shutil.rmtree(source_dir, ignore_errors=True)
        print(f"[Finalize] Task {task_id} migrated to AI_Vault successfully.")
    except Exception as e:
        print(f"[Finalize] Error during migration: {e}")
        
    conn.close()

@app.post("/internal/queue/{task_id}/status")
async def update_status(task_id: str, request: Request, background_tasks: BackgroundTasks):
    data = await request.json()
    status = data.get("status")
    status_text = data.get("status_text")
    
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('UPDATE queue_items SET status = ?, status_text = ? WHERE id = ?', 
              (status, status_text, task_id))
    conn.commit()
    conn.close()
    
    if status == "done":
        background_tasks.add_task(finalize_artifact, task_id)
    elif status == "audio_ready":
        background_tasks.add_task(partial_finalize_artifact, task_id)
        
    await manager.broadcast({"action": "update", "id": task_id, "status": status, "statusText": status_text})
    return {"message": "Status updated"}

@app.patch("/internal/queue/{task_id}")
async def patch_queue(task_id: str, request: Request):
    data = await request.json()
    clean_title = data.get("clean_title")
    clean_id = data.get("clean_id")
    
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('UPDATE queue_items SET clean_title = ?, clean_id = ? WHERE id = ?', 
              (clean_title, clean_id, task_id))
    conn.commit()
    conn.close()
    return {"message": "Patched"}

class LinkRequest(BaseModel):
    old_id: str
    new_mm_id: str
    clean_title: str

@app.post("/internal/link_mm")
async def link_mm(req: LinkRequest):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    
    # Check if the old ID exists in ai_artifacts
    c.execute('SELECT * FROM ai_artifacts WHERE mm_id = ?', (req.old_id,))
    row = c.fetchone()
    
    if not row:
        # Check if we already updated the DB in a previous failed run
        c.execute('SELECT * FROM ai_artifacts WHERE mm_id = ?', (req.new_mm_id,))
        already_updated = c.fetchone()
        if not already_updated:
            conn.close()
            raise HTTPException(status_code=404, detail="Artifact not found")
    else:
        # Update ai_artifacts to the new MM ID
        c.execute('UPDATE ai_artifacts SET mm_id = ? WHERE mm_id = ?', (req.new_mm_id, req.old_id))
        
        # Update queue_items just in case
        c.execute('UPDATE queue_items SET id = ? WHERE id = ?', (req.new_mm_id, req.old_id))
        conn.commit()
    
    conn.close()
    
    # Rename folder in Vault
    vault = os.getenv("AI_VAULT", r"E:\Data\Rajesh\MyMusic\Music_AI_Vault")
    
    # Find existing old folder
    old_folder = None
    for d in os.listdir(vault):
        if d.startswith(req.old_id):
            old_folder = os.path.join(vault, d)
            break
            
    if old_folder and os.path.isdir(old_folder):
        def sanitize_title(t): return re.sub(r'[\\/:*?"<>|]', '', t)
        clean_title_str = sanitize_title(req.clean_title)
        
        # New folder path
        new_folder_name = req.new_mm_id if req.new_mm_id == clean_title_str else f"{req.new_mm_id}_{clean_title_str}"
        new_folder = os.path.join(vault, new_folder_name)
        
        # Rename and move files to new folder
        prefix = new_folder_name
        os.makedirs(new_folder, exist_ok=True)
        for f in os.listdir(old_folder):
            if f.endswith('.wav') or f.endswith('.json') or f.endswith('.txt') or f.endswith('.log'):
                parts = f.rsplit('_', 1)
                
                # Extract suffix reliably
                if f.endswith('pitch_profile.json'): suffix = 'pitch_profile.json'
                elif f.endswith('vocal_map.json'): suffix = 'vocal_map.json'
                elif f.endswith('lyrics_english.txt'): suffix = 'lyrics_english.txt'
                elif f.endswith('lyrics_native.txt'): suffix = 'lyrics_native.txt'
                elif f.endswith('lyrics_meaning.txt'): suffix = 'lyrics_meaning.txt'
                else: suffix = parts[-1]
                
                new_f = f'{prefix}_{suffix}'
                # Try to move file to new folder
                import shutil
                try:
                    shutil.move(os.path.join(old_folder, f), os.path.join(new_folder, new_f))
                except PermissionError:
                    # If locked, try to wait briefly
                    time.sleep(1.0)
                    try:
                        shutil.move(os.path.join(old_folder, f), os.path.join(new_folder, new_f))
                    except Exception as e:
                        print(f"Failed to move {f}: {e}")
        
        # Try to remove old folder, it might be locked by MM file monitor
        try:
            import time
            time.sleep(0.5)
            shutil.rmtree(old_folder, ignore_errors=True)
        except Exception as e:
            print(f"Could not remove old folder {old_folder}: {e}")
        
    return {"message": "Linked successfully"}

@app.post("/internal/add_to_mm")
async def add_to_mm(req: LinkRequest):
    # For Add to MM, we try to use win32com
    vault = os.getenv("AI_VAULT", r"E:\Data\Rajesh\MyMusic\Music_AI_Vault")
    def sanitize_title(t): return re.sub(r'[\\/:*?"<>|]', '', t)
    
    # Path to original.wav (or vocals) to add to MM
    old_folder = None
    for d in os.listdir(vault):
        if d.startswith(req.old_id):
            old_folder = os.path.join(vault, d)
            break
            
    if not old_folder:
        raise HTTPException(status_code=404, detail="Artifact folder not found in Vault")
        
    # We add the original.wav to MM
    target_file = None
    for f in os.listdir(old_folder):
        if 'original.wav' in f or 'vocals.wav' in f:
            target_file = os.path.join(old_folder, f)
            if 'original' in f: break
            
    if not target_file:
        raise HTTPException(status_code=404, detail="No audio file found to add to MM")
        
    try:
        import win32com.client
        sdb = win32com.client.Dispatch("SongsDB.SDBApplication")
        song = sdb.NewSongData
        song.Path = target_file
        song.Title = req.clean_title
        song.UpdateDB()
        song.UpdateAll()
        new_mm_id = str(song.SongID)
        
        # Now call link_mm internally
        req.new_mm_id = new_mm_id
        await link_mm(req)
        return {"message": "Added to MediaMonkey", "new_mm_id": new_mm_id}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"MediaMonkey COM API error. Please ensure MM is running and COM is registered. Details: {e}")

# ---- WebSocket Endpoint ----
@app.websocket("/ws/updates")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            # Keep alive
            data = await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)

# ---- Process Manager ----
async def spawn_worker(task_id: str):
    print(f"[Orchestrator] Spawning worker for task {task_id}")
    worker_script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "task_worker.py")
    
    # Mark as processing
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('UPDATE queue_items SET status = ?, status_text = ? WHERE id = ?', ('processing', 'Starting worker...', task_id))
    conn.commit()
    conn.close()
    await manager.broadcast({"action": "update", "id": task_id, "status": "processing", "statusText": "Starting worker..."})
    
    try:
        loop = asyncio.get_running_loop()
        def run_sync():
            return subprocess.run(
                [sys.executable, worker_script, "--task-id", task_id],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
            
        result = await loop.run_in_executor(None, run_sync)
        
        if result.returncode != 0:
            print(f"[Orchestrator] Worker failed for {task_id}. Stderr: {result.stderr.decode()}")
            # If the worker completely crashed without sending a final status
            conn = sqlite3.connect(DB_PATH)
            c = conn.cursor()
            c.execute('UPDATE queue_items SET status = ?, status_text = ? WHERE id = ?', ('failed', 'Worker Crash', task_id))
            conn.commit()
            conn.close()
            await manager.broadcast({"action": "update", "id": task_id, "status": "failed", "statusText": "Worker Crash"})
            
    except Exception as e:
        print(f"[Orchestrator] Failed to spawn worker: {e}")
        traceback.print_exc()

if __name__ == '__main__':
    import uvicorn
    print("Starting Karaoke Orchestrator on port 5000...")
    uvicorn.run("karaoke_orchestrator:app", host='0.0.0.0', port=5000, reload=True)
