# 📑 MASTER_KARAOKE_PLAN.md

**Objective:** Build a cross-platform (Windows/Android) AI-driven Karaoke Maker and Practice Ecosystem, eventually integrating it as a content-generation module for the existing *Karaoke Night Live* host app.

---

## 🛠 Project Lifecycle Strategy
This project is executed in **Linear Incremental Phases**. Each phase must be verified as "Functional" before Antigravity is tasked with the next.

| Phase | Title | Primary Tech | Deliverable |
| :--- | :--- | :--- | :--- |
| **0** | Foundation & Config | Python / .env | Cross-machine environment parity |
| **1** | Audio Extraction | yt-dlp / Demucs | "Smart Bundle" (Instrumental + Original) |
| **2** | Pitch Analysis | SciPy / Librosa | `pitch_profile.json` (Target data) |
| **3** | Agentic Logic | Local LLM / APIs | Vetted song selection & lyrics |
| **4** | Practice App (UI) | Flutter / Dart | Cross-platform dashboard & sync |
| **5** | Pitch Engine (Core) | Flutter / C++ | Real-time visual tracking |
| **6** | Host Integration | Flutter (Host App) | Unified "Karaoke Night Live" Module |

---

## 🚩 Phase 0: Environment & Parity
**Task:** Ensure Windows 10/11 path consistency.
* **File:** `core_engine/config.py`
* **Action:** Create a `.env` loader that dynamically maps `ONEDRIVE_HOT_ZONE` based on machine-specific names.
* **Verification:** Run `python config.py` to print and verify FFmpeg and local LLM connectivity.

## 🚩 Phase 1: High-Fidelity Audio Extraction
**Task:** Automate the "Karaoke Maker" core.
* **File:** `core_engine/maker_service.py`
* **Action:** 1. `yt-dlp` download at 320kbps MP3 (Original Reference).
    2. `demucs` separation (OpenVINO accelerated) to produce `instrumental.wav` and `vocals.wav`.
* **Storage:** Write outputs to `OneDrive/ActiveKaraoke/[SongID]/`.
* **Logging:** Implement `debug.log` inside each song folder for troubleshooting.
* **Metadata:** Embed source URL into the final audio files using FFmpeg.
* **Improvement:** Add logic to skip processing if the song folder already exists and contains the necessary files (auto-resume).
* **Improvement:** Force re-processing of existing folders if a flag is passed.
* **Improvement:** make download/separation two parallel process so the subseqent songs can start downloading while already downloaded song is being processed for pitch analysis.

## 🚩 Phase 2: Mathematical Pitch Profiling
**Task:** Build the "Target Line" for the visualizer.
* **File:** `core_engine/pitch_analyzer.py`
* **Action:** Analyze `vocals.wav` (or original) to extract fundamental frequencies ($F_0$).
* **Output:** Export a compact `pitch_profile.json` containing time/frequency coordinate arrays.

## 🚩 Phase 3: Agentic Vetting & Lyrics
**Task:** Add intelligence to the search.
* **File:** `core_engine/agents/`
* **Action:** 1. **Audio Agent:** Query Local LLM (Ollama/LM Studio) to pick the best "Studio Version" from search results.
    2. **Lyric Agent:** Fetch `.lrc` (timed) or `.txt` (raw) from Genius/LRCLib.
**Task:** Ensure high-quality source audio and lyrics.
* **Action:**
    * Integrate **Ollama/LM Studio** to query and rank audio sources.
    * Implement logic to select the highest-rated "Studio Version" from search results.
    * Fetch synchronized lyrics (.lrc) or raw lyrics from sources like Genius.
    * Store lyrics in the song folder as `lyrics.lrc`.
    * **Logging:** Update `debug.log` to show which source was chosen and why.

## 🚩 Phase 4: Flutter Practice Dashboard
**Task:** Establish the cross-platform shell.
* **Target:** Windows & Android (Native).
* **Action:** Build a file-explorer widget that reads the OneDrive "Hot Zone" and displays song cards with metadata.
* **Sync:** Verify folder-reading on Android via OneSync/FolderSync.

## ✅ Phase 5: Live Pitch Visualizer Engine (COMPLETED)
**Task:** Real-time interactive feedback & Practice Tools.
* **UI:** `practice_app/widgets/pitch_canvas.dart`, `lyrics_panel.dart`, and Practice Tool Dialogs.
* **Action:** 
    1. Capture low-latency Mic input using `record` and extract frequency using `pitch_detector_dart`.
    2. Plot user pitch dots over the `pitch_profile.json` target line on a scrolling `CustomPainter` canvas.
    3. Add a responsive, auto-scrolling **Lyrics Panel** that parses `.txt` or `.lrc` files, allows language toggling, and mathematically guarantees accurate scrolling.
    4. Integrate **Sync Mode** with inline Multi-Singer assignment, allowing precise real-time `.lrc` generation and dual-language auto-syncing.
    5. Implement advanced **Practice Mode** featuring dynamic A-B looping and Multi-Segment Sequences, complete with precision millisecond UI editors and JSON profile persistence.
    6. Build a custom **Interactive Segmented Progress Bar** allowing users to visually scrub, drag-to-resize, and drag-to-shift sequence segments directly on the timeline, with dynamic time overlays and anti-spam auto-seeking logic.
    7. **Dual-Pane Lyrics Engine:** Intelligent responsive dual-language display that automatically switches between Portrait (Top/Bottom Stacked) and Landscape (Side-by-Side) synchronized lists when enough vertical space is available.
    8. **Non-Interrupting Settings Architecture:** Converted full-screen settings into seamless modal popups to guarantee that active practice sessions and audio engines remain mounted and undisrupted during configuration changes.
    9. **Intelligent UI Guards:** Dashboard UI contextually parses missing data (audio stems, pitch json, lyrics, video paths) and gracefully disables controls with contextual tooltips to prevent breaking states while maintaining visual consistency.

## 🚩 Phase 6: "Karaoke Night Live" Integration (FINAL)
**Task:** Link the maker to the existing host app.
* **Action:** 1. Modify the Host App's `Song` model to include `pitchDataUrl`.
    2. Add a "Practice Mode" toggle in the Singer Dashboard that pulls these AI assets.

---

## ⚙️ Configuration Specification (.env.example)
```ini
# --- Machine Specific Paths ---
ONEDRIVE_HOT_ZONE="C:/Users/USER/OneDrive/ActiveKaraoke"
FFMPEG_PATH="C:/ffmpeg/bin/ffmpeg.exe"

# --- Local LLM Config ---
# For LM Studio: http://localhost:1234/v1
# For Ollama: http://localhost:11434/v1
LLM_BASE_URL="http://localhost:1234/v1"
LLM_MODEL="model-name-here"

# --- API Keys (Optional) ---
GENIUS_TOKEN="your_token"