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
We are currently in **Phase 1** of a massive architectural refactoring. The player components inside `practice_app` are being extracted into a standalone package called `vox_player_core` so they can be shared universally with `karaoke_app`.

## Ecosystem Role
Karaoke Maker acts as the "Preparer" and "Practicer". Once it prepares a song (stems, lyrics, pitch), that song is marked as 'Ready' in the global Google Sheets catalog for the Host App to use.
