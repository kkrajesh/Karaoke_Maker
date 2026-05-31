# Karaoke Maker (Practice App & Python Engine)

Karaoke Maker is an automated pipeline designed to search, download, and process high-fidelity audio tracks to generate clean instrumental and vocal stems. It includes a Python Backend for audio separation/LLM analysis, and a Flutter Practice App frontend.

## 🚀 Release Notes (v1.3.0)
- Completed Phase 5: Live Pitch Visualizer Engine with advanced Practice Mode and A-B looping.
- Completed Phase 6: Universal Search Engine decoupled for cross-platform reusability.
- Completed Phase 8: Data Integration & Decoupling with robust local SQLite mapping.
- Completed Phase 9: Advanced Performance Sequences with timeline-synchronized Sequence Editor.

## 🚀 Current State
- **Stable**: Automated Python pipeline (Demucs extraction, Pitch tracking, LLM lyric scraping/transliteration).
- **Stable**: Flutter Practice App featuring real-time pitch feedback, interactive segment timelines, and a dual-pane responsive lyrics engine.
- **In Transition**: We are currently extracting the core media player (Pitch Canvas, Lyrics Engine, Segment Editor) out of this app and into a universal `vox_player_core` package.

## 🛠 Tech Stack
- **Backend**: Python 3.10+, Flask, Demucs, Librosa, Crepe, yt-dlp, Local LLM Integration.
- **Frontend**: Flutter, Dart, provider, pitch_detector_dart, audioplayers.

## 🐛 Known Gaps/Bugs
- **Architecture**: The Practice App's media player is highly coupled to local state. It is being decoupled into `vox_player_core`.
- **Search**: The file explorer currently requires strict manual pathing. A new Everything.exe IPC unified search engine is planned.

## 📦 Install Instructions
1. Clone the repository.
2. Ensure `ffmpeg` is installed on your Windows PATH.
3. Install Python dependencies: `pip install -r core_engine/requirements.txt`
4. Run Flutter pub get: `cd practice_app && flutter pub get`

## 🕹 Unified Startup Sequence
To run the full ecosystem (Backend Services + Flutter Apps):

**1. Start the Python API Server (Flask Backend)**
```bash
cd core_engine
python api_server.py
```
*Note: This provides the `/health` endpoint and handles search, lyrics, stem processing, and MP3 generation.*

**2. Start the AI Queue Watcher**
```bash
python queue_watcher.py
```
*Note: This background job processes automated tasks from `ai_queue.json` and updates the heartbeat for the Flutter app.*

**3. Start the Flutter Apps**
- For the Practice App: `cd practice_app && flutter run -d windows`
- For the Host App: `cd ../karaoke_app && flutter run -d windows`

*Pro Tip: You can now monitor and start these Python backend services directly from the Settings > Services dashboard in the Flutter apps!*

## 🧰 Maintenance and Troubleshooting
### Fixing Orphaned AI Vault Folders
If you ever manually drop a folder in the AI Vault or encounter a situation where the processed AI folders become disconnected from their MediaMonkey IDs, you can use the automated cleanup script.

This script scans your databases, finds the orphaned folders, cross-references them against your MediaMonkey database, and reconnects them by renaming the folders, files, and updating the AI database to link them together perfectly.

**How to run it:**
1. Open your terminal.
2. Run the script: `cd core_engine && py migrate_orphans.py`
