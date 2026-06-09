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
        2.1 ability to separate individual voices into separate files. Same for different instruments
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
    6.1 enhanced segmentation by adding where segments where instrumental vs vocals to be enabled - to make duet practicing easier. 
    6.2 abillity to generate mp3s with embedded lyrics for the duets for each singer where the vocals for others are present and also including the music with vocals for those who want to practice singing the song with vocals.
    7. **Dual-Pane Lyrics Engine:** Intelligent responsive dual-language display that automatically switches between Portrait (Top/Bottom Stacked) and Landscape (Side-by-Side) synchronized lists when enough vertical space is available.
    8. **Non-Interrupting Settings Architecture:** Converted full-screen settings into seamless modal popups to guarantee that active practice sessions and audio engines remain mounted and undisrupted during configuration changes.
    9. **Intelligent UI Guards:** Dashboard UI contextually parses missing data (audio stems, pitch json, lyrics, video paths) and gracefully disables controls with contextual tooltips to prevent breaking states while maintaining visual consistency.
    10. **Background Audio Playback:** Fully supported Background Audio Playback on Android devices via `vox_player_core`.
    11. **Pitch & tempo controls**: provide ability to adjust pitch and tempo of the song during playback. Potentially create a MP3 for the selected pitch/tempo combination for the user to download and use. This can be done in the core engine using the pitch data and the segments, just like the current Gen mp3s logic but with pitch and tempo controls instead of just segments. 


## 🚩 Phase 6: Universal Search Engine (COMPLETED)
**Task:** Decouple Search Logic for Cross-Platform Reusability.
* **Component:** `UnifiedSearchUI` and `VoxSearchProvider` within `vox_player_core`.
* **Action:**
    1. Built a robust search interface capable of running concurrent futures across multiple injected search providers (e.g., Local Database, Cloud Sheets, Online).
    2. Implemented an `AnimatedSize` intelligent accordion for inline playback previews.
    3. Fully integrated `media_kit` hardware-accelerated video scaling for a cinematic preview experience, alongside a sleek slider widget for audio-only file streams.
    4. Engineered a strictly decoupled `SearchResultActionBuilder` so host apps handle the business logic (Singer role "Sign up to Sing" vs. Requester role "Request").
    5. Integrated flawless **Windows-to-Android Cross-Platform Data Sync** featuring automatic `MANAGE_EXTERNAL_STORAGE` permission gating, case-insensitive path translation, and strict file existence verifications to prevent silent Android media engine failures.

## 🚩 Phase 7: "Karaoke Night Live" Integration (FINAL)
**Task:** Link the maker to the existing host app.
* **Action:** 1. Modify the Host App's `Song` model to include `pitchDataUrl`.
    2. Add a "Practice Mode" toggle in the Singer Dashboard that pulls these AI assets.
    3. Inject host-specific implementation of `VoxSearchProvider` into the `UnifiedSearchUI`.

## ✅ Phase 8: Data Integration & Decoupling (COMPLETED)
**Task:** Ensure reliable cross-platform data synchronization.
* **Action:** 
    1. Built `VoxAiTrackingService` powered by `sqflite_common_ffi` to maintain a robust local SQLite mapping between MediaMonkey DB IDs and AI Vault folders.
    2. Refactored `queue_watcher.py` to seamlessly pass MediaMonkey IDs end-to-end, solving folder-naming drift and data dissociation.
    3. Updated `LyricsParser` within the new `vox_player_core` package to use smart `.contains()` logic, allowing it to adapt to prefixed Vault files effortlessly.
    4. Engineered a `migrate_orphans.py` utility that scans SQLite mapping mismatches and flawlessly auto-renames directories and internal files to sync with legacy MediaMonkey data.

## ✅ Phase 9: Advanced Performance Sequences (COMPLETED)
**Task:** Build a powerful UI to manage A-B loops and AI-generated vocal segments.
* **Action:**
    1. Implemented a timeline-synchronized Sequence Editor allowing merging, splitting, adding, deleting, and previewing segments.
    2. Integrated auto-generation of "Vocal Parts" using intelligent parsing of `vocal_map.json` and heuristics to club close segments.
    3. Engineered robust timeline scrubbing intelligence in `_onControllerUpdate` to strictly enforce playback within defined segments, pausing exactly at boundaries and preventing out-of-bounds playback.
    4. Seamlessly synced live editing to the background `SegmentedProgressBar` to provide instant visual feedback of segment bounds.
    5. **COMPLETED:** Ability to adjust the vocals volume for practice. This intelligently handles 'Both' mode by automatically mixing the guide vocals at an adjustable volume (default 50%).
    6. Advanced: Ability to create a medley by picking segments from multiple songs and creating a new song with those segments in order. 
    7. **COMPLETED:** Ability to save the segments for youtube videos and preserve it for later. Mapped and loaded reliably using the YouTube ID via the AI Vault indexing system.



* **General future ideas**
1.  **Duet Karaoke Generation** ability to use the segments for singer 1/2/3 and use that segment to generate Karaoke files for singer 1 - which will have other vocals and no vocals for singer 1 sections. Similarly for other singers as well
2. ** Karaoke Video Generation with Image + Audio** using AI Video Generation using StableDiffusion+ffmpeg - incorporating lyrics, graph, singer parts, all customizable per generation.
3. ** Platform Sync Up ** 
    now that all functionalies are working across platforms. I need a plan to keep contents on both platforms in sycnc - espcially the AI Hub content. 
    1. Keep AI content in sync - Try to use the cloud storage feature that is already existing for the current media library, but enhance it to support AI content as well. So the plan should include
    2. How to sync AI content and MMDB content in sync on generation of AI content. 
    3. The AI services must be able to be initiated and controlled from the android device and the content should be saved to the cloud storage and synced across devices. 
    3. How to initiate AI Queue from android, and potentially do this while disconnected from the windows services - This would be nice to have feature.

* **Bugs to Fix**
1. after playing a song from Library, playing a youtube video plays both youtube video as well as the library vocals in the background.


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