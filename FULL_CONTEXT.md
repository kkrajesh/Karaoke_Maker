# Karaoke Maker - Full Context

## Overview
Karaoke Maker is the engine of the Karaoke Ecosystem. It consists of a robust Python processing pipeline and an interactive Flutter Practice App. It is designed to take raw audio (YouTube or Local), separate it into stems, extract pitch profiles, transliterate native lyrics into English, and provide a visually rich singing practice environment.

## Architecture
- **core_engine (Python)**: Uses `demucs` for vocal separation, `crepe` for pitch extraction, and local LLMs for lyric parsing and meaning generation. It manages the "Hot Zone" directory containing processed files.
- **practice_app (Flutter)**: A Windows desktop application. Key components include:
  - `LyricsPanel`: A responsive, dual-pane engine that adapts to landscape (side-by-side) or portrait (stacked) views.
  - `PitchCanvas`: A real-time `CustomPainter` that visualizes the singer's microphone input against the original artist's pitch curve.
  - `SegmentEditor`: A timeline tool for precise A-B loop practice.
  - **Modal Settings**: A non-interrupting overlay architecture allowing live config changes without tearing down the audio player state.

## Current Migration Phase
We have **Completed Phase 8** of a massive architectural refactoring. The player components inside `practice_app` have been successfully extracted into a standalone package called `vox_player_core`. 
Additionally, the system now uses a robust local SQLite database (`vox_ai_metadata.db`) mapping to the MediaMonkey `MM.DB` to handle all artifact tracking, eliminating brittle folder-name parsing.

## Ecosystem Role
Karaoke Maker acts as the "Preparer" and "Practicer". Once it prepares a song (stems, lyrics, pitch), that song is tracked locally via `vox_ai_db.dart` and marked as 'Ready' for the Host App to use via global sync.
