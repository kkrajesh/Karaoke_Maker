# Karaoke Maker

Karaoke Maker is an automated pipeline designed to search, download, and process high-fidelity audio tracks to generate clean instrumental and vocal stems. It is currently built to prioritize regional Indian MP3 domains with a fallback to YouTube, ensuring the best possible audio sources are used.

## 🚀 Features

- **Automated Regional Search**: Scrapes preferred regional domains (e.g., mp3chetta.com, masstamilan.dev) via DuckDuckGo before falling back to YouTube.
- **High-Fidelity Extraction**: Uses `yt-dlp` to download audio at the highest available quality directly into `.wav` format to avoid codec decompression loss.
- **AI Vocal Separation**: Leverages Facebook's `demucs` (Hybrid Transformer) to split the track into `vocals.wav` and `instrumental.wav`.
- **Smart Windows Bypass**: Custom-built Python wrapper that monkeypatches `torchaudio` to use `soundfile` instead of `torchcodec`, completely bypassing notorious PyTorch C++ DLL errors on Windows.
- **Automated Metadata Injection**: Uses `ffmpeg` to embed the original source URL directly into the generated `.wav` files as a comment tag.
- **Idempotent Processing**: Automatically skips songs that have already been separated unless forcefully requested.
- **Concurrent Pipeline**: Employs thread-pool execution to download new songs in parallel while previous songs undergo heavy CPU separation and analysis.
- **Mathematical Pitch Profiling**: Uses `librosa.pyin` to extract the fundamental frequency ($F_0$) of vocals at 50 FPS and estimates the song's root Tonic (Sa). Outputs a highly compact JSON payload.
- **Agentic Audio Vetting**: Utilizes a Local LLM to rank and choose the highest-quality authentic Studio Version from search results, actively rejecting covers and live performances.
- **Intelligent Lyric Scraper**: Concurrently fetches lyrics via LRCLib, falls back to web scraping (DuckDuckGo/YouTube), and uses the Local LLM to automatically extract and transliterate native Indian scripts into English characters.

## 🛠️ Tech Stack

- **Language**: Python 3.x
- **Audio Download**: `yt-dlp`
- **AI Separation**: `demucs`, `PyTorch`
- **Pitch Analysis**: `librosa`, `numpy`
- **Agentic Intelligence**: `openai` (Local LLM via LM Studio)
- **Audio Manipulation**: `soundfile`, `FFmpeg`
- **Web Scraping**: `beautifulsoup4`, `duckduckgo-search`

## ⚙️ Setup & Installation

1. **Clone the Repository**
2. **Install FFmpeg**
   - Download FFmpeg and ensure it's accessible on your machine.
3. **Configure Environment Variables**
   - Copy `.env.example` to `.env`.
   - Update `ONEDRIVE_HOT_ZONE` to your desired output folder.
   - Update `FFMPEG_PATH` to point to your `ffmpeg.exe`.
   - Customize `PREFERRED_AUDIO_DOMAINS` to prioritize specific sites.
4. **Install Python Dependencies**
    ```bash
    pip install -r requirements.txt
    pip install duckduckgo-search googlesearch-python
    ```
    *(Note: The `torchcodec` dependency is natively bypassed on Windows using the `soundfile` library via `core_engine/run_demucs.py`)*

5. **Start Local LLM (Optional but Recommended)**
   - Open LM Studio or Ollama and start the local server on `http://localhost:1234/v1`. This powers the Audio Vetting and Lyric Transliteration features.

## 🏃 Execution Instructions

The core engine is now designed to run as a **Flask API Server**, which acts as the backend for the Flutter UI.

To start the local API server:
```bash
cd core_engine
python api_server.py
```
*(The server will run locally on port `5000` and handle background extraction tasks asynchronously).*

You can still use the legacy headless test script if you prefer batch processing:
```bash
python test_pipeline.py
```

### Outputs
For each song, the system creates a dedicated folder in your `ONEDRIVE_HOT_ZONE` containing:
- `original.wav` (The downloaded source audio)
- `vocals.wav` (The separated vocal track)
- `instrumental.wav` (The separated karaoke track)
- `pitch_profile.json` (F0 extraction points mapping the vocals)
- `vocal_map.json` (RMS energy map of the vocal track)
- `lyrics_native.lrc/.txt` (Synchronized or raw lyrics in native script)
- `lyrics_english.lrc/.txt` (LLM-transliterated English lyrics)
- `debug.log` (A local log detailing the LLM decisions, extraction, and separation process)

## 🗺️ Roadmap

- **Phase 1**: High-Fidelity Audio Extraction (✅ Complete)
- **Phase 2**: Mathematical Pitch Profiling (✅ Complete)
- **Phase 3**: Agentic Vetting & Lyrics (✅ Complete)
- **Phase 4**: Flutter Practice Dashboard (✅ Complete)
- **Phase 5**: Live Pitch Visualizer Engine (✅ Complete)
- **Phase 6**: "Karaoke Night Live" Integration
