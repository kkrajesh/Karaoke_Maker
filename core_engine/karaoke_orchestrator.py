import os
import sys
import json
import time
import asyncio
import sqlite3
import subprocess
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
from core_engine.agents.lyric_agent import LyricAgent

maker = MakerService()
lyric_agent = LyricAgent()

# Database setup
AI_VAULT = os.getenv("AI_VAULT", ".")
DB_PATH = os.path.join(AI_VAULT, "vox_ai_metadata.db")

def init_db():
    if not os.path.exists(AI_VAULT):
        os.makedirs(AI_VAULT, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
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
            logs TEXT
        )
    ''')
    conn.commit()
    conn.close()

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
    yield
    # Shutdown
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
        "fetchOriginalAudio": d.get("fetch_original_audio"),
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

@app.get("/lyrics")
def fetch_lyrics(q: str):
    try:
        lyrics = lyric_agent.fetch_lyrics(q)
        return {"lyrics": lyrics}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

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

@app.post("/queue")
async def add_to_queue(item: QueueItemCreate, background_tasks: BackgroundTasks):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    
    # Check if exists and is pending/processing/done
    c.execute('SELECT status FROM queue_items WHERE id = ?', (item.id,))
    row = c.fetchone()
    if row:
        status = row[0]
        if status in ['pending', 'processing', 'done']:
            conn.close()
            return {"message": "Item already in queue", "id": item.id}
        else:
            c.execute('DELETE FROM queue_items WHERE id = ?', (item.id,))
            
    c.execute('''
        INSERT INTO queue_items (id, title, artist, url, source_type, status, status_text, lyrics_text, lyrics_type, fetch_original_audio, logs)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', (item.id, item.title, item.artist, item.url, item.sourceType, 'pending', 'Queued', item.lyricsText, item.lyricsType, int(item.fetchOriginalAudio), '[]'))
    conn.commit()
    conn.close()
    
    # Broadcast new item
    await manager.broadcast({"action": "add", "item": {
        "id": item.id, "title": item.title, "artist": item.artist, "url": item.url, 
        "sourceType": item.sourceType, "status": "pending", "statusText": "Queued",
        "fetchOriginalAudio": item.fetchOriginalAudio, "logs": []
    }})
    
    # Schedule the worker process
    background_tasks.add_task(spawn_worker, item.id)
    return {"message": "Added to queue", "id": item.id}

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
    
    # Format with elapsed time from when processing started
    # We'll just prepend timestamp directly here or let worker do it.
    # Worker is doing it, or we can do it here if we store start_time. 
    # Actually, let's just use the message as is, worker can format it.
    
    logs.append(msg)
    status = "processing" if row[1] == "pending" else row[1]
    
    c.execute('UPDATE queue_items SET logs = ?, status_text = ?, status = ? WHERE id = ?', 
              (json.dumps(logs), msg, status, task_id))
    conn.commit()
    conn.close()
    
    await manager.broadcast({"action": "update", "id": task_id, "statusText": msg, "log": msg, "status": status})
    return {"message": "Log updated"}

@app.post("/internal/queue/{task_id}/status")
async def update_status(task_id: str, request: Request):
    data = await request.json()
    status = data.get("status")
    status_text = data.get("status_text")
    
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('UPDATE queue_items SET status = ?, status_text = ? WHERE id = ?', 
              (status, status_text, task_id))
    conn.commit()
    conn.close()
    
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
        # Run worker as a separate subprocess
        process = await asyncio.create_subprocess_exec(
            sys.executable, worker_script, "--task-id", task_id,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await process.communicate()
        
        if process.returncode != 0:
            print(f"[Orchestrator] Worker failed for {task_id}. Stderr: {stderr.decode()}")
            # If the worker completely crashed without sending a final status
            conn = sqlite3.connect(DB_PATH)
            c = conn.cursor()
            c.execute('UPDATE queue_items SET status = ?, status_text = ? WHERE id = ?', ('failed', 'Worker Crash', task_id))
            conn.commit()
            conn.close()
            await manager.broadcast({"action": "update", "id": task_id, "status": "failed", "statusText": "Worker Crash"})
            
    except Exception as e:
        print(f"[Orchestrator] Failed to spawn worker: {e}")

if __name__ == '__main__':
    import uvicorn
    print("Starting Karaoke Orchestrator on port 5000...")
    uvicorn.run("karaoke_orchestrator:app", host='127.0.0.1', port=5000, reload=True)
