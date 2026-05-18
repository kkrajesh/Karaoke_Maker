# Karaoke Maker - Full Project Context

## Overview
**Karaoke Maker** is a two-part system designed to automatically generate, manage, and play karaoke tracks. It takes a song query or URL, downloads the audio, separates the vocals from the instrumental, fetches and transliterates lyrics using LLMs, analyzes pitch profiles for vocal scoring, and serves the fully processed package to a rich Flutter frontend for an interactive singing experience.

The system is composed of two primary layers:
1. **Core Engine**: A Python/Flask backend that orchestrates audio processing, machine learning models, and web scraping.
2. **Practice App**: A Flutter Windows/Desktop (and potentially cross-platform) application that acts as the user interface, library manager, and karaoke player.

---

## 1. Core Engine (Python Backend)

### Technology Stack
* **Language**: Python 3.10+
* **Framework**: Flask (REST API)
* **Audio Processing**: Demucs (Vocal separation), Librosa & Crepe (Pitch Tracking), FFmpeg
* **Web Scraping/APIs**: `yt-dlp` (Audio downloading), `duckduckgo_search` & BeautifulSoup (Web scraping), LRCLib & Genius APIs.
* **LLM Integration**: OpenAI Python Client (Configured for Local/Remote LLMs to handle transliteration and poetic meaning).

### Architecture & Key Components
* **`api_server.py`**: The Flask entry point. Exposes endpoints to trigger asynchronous processing tasks (`/process`, `/reprocess`, `/batch_process`) and check status (`/status/<task_id>`).
* **`maker_service.py`**: The central orchestrator. It manages the pipeline: acquiring audio -> running Demucs -> running Pitch Analysis -> generating Vocal Activity Maps -> calling `LyricAgent`.
* **`agents/audio_agent.py`**: Uses `yt-dlp` to search YouTube/Music domains and download the highest quality audio, standardizing it to `.wav`.
* **`agents/lyric_agent.py`**: A complex, multi-fallback agent. It attempts to find synced (`.lrc`) or unsynced (`.txt`) lyrics via LRCLib, Genius, DuckDuckGo, or YouTube descriptions. If lyrics are in a native script (e.g., Hindi/Devanagari), it strictly transliterates them into the Latin alphabet (Manglish/Hinglish) using an LLM. It also generates a `lyrics_meaning.txt` file summarizing the poetic meaning.
* **`pitch_analyzer.py`**: Uses the Crepe neural network to extract a time-series pitch profile (`pitch_profile.json`) from the isolated vocals.
* **`vocal_activity_analyzer.py`**: Analyzes the isolated vocals to generate a `vocal_map.json`, defining exact timestamps where vocals are active (used for UI scoring/visualization).
* **`run_demucs.py`**: A custom wrapper for the `htdemucs` model that bypasses missing `torchcodec` dependencies to successfully split the audio into `vocals.wav` and `instrumental.wav`.

### Data Structure (The "Hot Zone")
Processed songs are stored in a designated "Hot Zone" directory (e.g., `C:/Users/.../ActiveKaraoke/`). Each song gets its own folder named after the `song_id`.
A fully processed song folder contains:
* `original.wav` - The raw downloaded audio.
* `vocals.wav` - Isolated vocal track.
* `instrumental.wav` - Isolated instrumental/karaoke track.
* `pitch_profile.json` - Frequency data over time.
* `vocal_map.json` - Boolean vocal activity map.
* `lyrics_native.txt` or `.lrc` - Original lyrics (often in native script).
* `lyrics_english.txt` or `.lrc` - Transliterated lyrics (Latin alphabet).
* `lyrics_meaning.txt` - LLM-generated English poetic meaning of the song.

---

## 2. Practice App (Flutter Frontend)

### Technology Stack
* **Framework**: Flutter (Dart)
* **State Management/Architecture**: Standard Stateful/Stateless Widgets, heavily reliant on Service Singletons.
* **Key Packages**: `audioplayers` (Playback), `file_picker` (Local file injection), `http` (API integration).

### Architecture & Key Components
* **`lib/models/song.dart`**: The core data model. Determines a song's status (Ready, Processing, Error) by checking the existence of required files in its Hot Zone folder. It exposes boolean getters (e.g., `hasInstrumental`, `hasEnglishLyrics`) to drive the UI.
* **`lib/services/api_service.dart`**: Communicates with the Flask backend. Handles polling for task status and triggering `/process` and `/reprocess` endpoints.
* **`lib/services/file_explorer_service.dart`**: The bridge between the filesystem and the app. It recursively scans the Hot Zone directory to build the user's `SongLibrary`. It also tracks background processing tasks to seamlessly update UI state when backend tasks complete.
* **`lib/services/lyrics_parser.dart`**: Parses raw `.txt` or `.lrc` (Lyric Timing) files into structured Dart objects (`LyricsData`, `LyricLine`) for synchronized rendering.

### Key Screens
* **`DashboardScreen` (`dashboard_screen.dart`)**: The main library view. It displays a list of processed songs. It features interactive "Component Chips" (Inst, Vocals, Pitch, Map, Lyrics) that are color-coded (Green = Ready, Red = Missing/Error, Orange = Processing). Users can tap these chips to granularly reprocess individual components (e.g., re-run the LLM translation or inject a manual text file) without regenerating the entire song.
* **`CreateSongScreen` (`create_song_screen.dart`)**: A wizard-like UI for adding new songs. Users can search for a track, preview the URL, automatically fetch draft lyrics from the backend (to verify before committing), and then queue the song for full processing.
* **`ActiveSessionScreen` (`active_session_screen.dart`)**: The Karaoke Player. It plays the instrumental track, renders scrolling, synchronized lyrics, and potentially visualizes the pitch profile.

---

## System Workflows & Edge Cases

### 1. Granular Reprocessing & Idempotency
If a specific component fails (e.g., web scraper banned, Demucs crashed), the user can tap the red component chip in the Dashboard. The `api_server.py` exposes a `/reprocess` endpoint that accepts a `component` argument.
* **Safety Mechanism**: If the user reprocesses lyrics, the `LyricAgent` checks if `lyrics_native.txt` already exists. If it does, it skips web scraping and directly feeds the existing text into the LLM for transliteration and meaning extraction. This prevents catastrophic data loss if the scraper fails on a subsequent run.
* **File Locking**: The `maker_service.py` ensures that files (like `original.wav`) are not locked by copying operations when processing components idempotently.

### 2. Manual Lyric Injection
Because LLM web scraping can occasionally fail, the Dashboard allows users to inject manual lyrics. Tapping the Lyrics chip opens an `AlertDialog` where users can either paste text or use the `file_picker` to select a local `.txt` or `.lrc` file. This text is sent to the backend, saved as `lyrics_native.txt`, and immediately processed by the LLMs for transliteration.

### 3. Asynchronous UI Updates
When a song is queued, the Flutter app adds it to the `FileExplorerService._activeTasks` map. A periodic timer polls the backend's `/status/<task_id>` endpoint. When the status turns `completed`, the Flutter app triggers a file system rescan (`loadLibrary`) to update the UI chips from Orange (Processing) to Green (Ready).

### 4. Global Quick Search & Seamless Switching
The UI implements a global Quick Search architecture. In the Library, users can filter a large list of songs instantly. In the `ActiveSessionScreen`, a search overlay (`SongSearchDialog`) can be triggered mid-practice. Tapping a new song from this dialog fires an `onSongSwitched` callback back up the widget tree to tear down the current audio context and seamlessly spin up the new song.

---

## Deployment & Setup Notes
* Both the Python Backend and Flutter App must be pointed to the same `ActiveKaraoke` Hot Zone folder.
* The Python environment requires `ffmpeg` installed on the system path, as well as significant ML dependencies (`demucs`, `librosa`, `crepe`).
* The system utilizes a local/OpenAI-compatible LLM endpoint (configurable via environment variables) to perform the intensive transliteration and semantic translation without relying strictly on paid cloud APIs.
