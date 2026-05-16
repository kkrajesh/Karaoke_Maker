# Karaoke Maker

Karaoke Maker is an automated pipeline designed to search, download, and process high-fidelity audio tracks to generate clean instrumental and vocal stems. It is currently built to prioritize regional Indian MP3 domains with a fallback to YouTube, ensuring the best possible audio sources are used.

## 🚀 Features

- **Automated Regional Search**: Scrapes preferred regional domains (e.g., mp3chetta.com, masstamilan.dev) via DuckDuckGo before falling back to YouTube.
- **High-Fidelity Extraction**: Uses `yt-dlp` to download audio at the highest available quality directly into `.wav` format to avoid codec decompression loss.
- **AI Vocal Separation**: Leverages Facebook's `demucs` (Hybrid Transformer) to split the track into `vocals.wav` and `instrumental.wav`.
- **Smart Windows Bypass**: Custom-built Python wrapper that monkeypatches `torchaudio` to use `soundfile` instead of `torchcodec`, completely bypassing notorious PyTorch C++ DLL errors on Windows.
- **Automated Metadata Injection**: Uses `ffmpeg` to embed the original source URL directly into the generated `.wav` files as a comment tag.
- **Idempotent Processing**: Automatically skips songs that have already been separated unless forcefully requested.

## 🛠️ Tech Stack

- **Language**: Python 3.x
- **Audio Download**: `yt-dlp`
- **AI Separation**: `demucs`, `PyTorch`
- **Audio Manipulation**: `soundfile`, `FFmpeg`
- **Web Scraping**: `beautifulsoup4`, `requests`

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
   ```
   *(Note: The `torchcodec` dependency is natively bypassed on Windows using the `soundfile` library via `core_engine/run_demucs.py`)*

## 🏃 Execution Instructions

Currently, the pipeline is verified using the `test_phase1.py` script, which processes a queue of Indian songs.

To start processing the queue:
```bash
python test_phase1.py
```

### Outputs
For each song, the system creates a dedicated folder in your `ONEDRIVE_HOT_ZONE` containing:
- `original.wav` (The downloaded source audio)
- `vocals.wav` (The separated vocal track)
- `instrumental.wav` (The separated karaoke track)
- `debug.log` (A local log detailing the entire extraction and separation process)

## 🗺️ Roadmap

- **Phase 1**: High-Fidelity Audio Extraction (✅ Complete)
- **Phase 2**: Mathematical Pitch Profiling (Extracting fundamental frequencies $F_0$)
- **Phase 3**: Karaoke Timing Synchronization (Matching vocals to timestamps)
- **Phase 4**: Output Generation (Finalizing the Karaoke asset package)
