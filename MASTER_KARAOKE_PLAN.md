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

## 🚩 Phase 4: Flutter Practice Dashboard
**Task:** Establish the cross-platform shell.
* **Target:** Windows & Android (Native).
* **Action:** Build a file-explorer widget that reads the OneDrive "Hot Zone" and displays song cards with metadata.
* **Sync:** Verify folder-reading on Android via OneSync/FolderSync.

## 🚩 Phase 5: Live Pitch Visualizer Engine
**Task:** Real-time interactive feedback.
* **UI:** `practice_app/widgets/pitch_canvas.dart`.
* **Action:** 1. Capture low-latency Mic input.
    2. Plot user pitch dots over the `pitch_profile.json` target line on a scrolling `CustomPainter` canvas.

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