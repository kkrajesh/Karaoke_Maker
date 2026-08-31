## 1.6.4+1
- Added a "New Window" button to the Dashboard AppBar on Desktop environments, enabling users to launch completely independent concurrent instances of the practice app.

## 1.6.3+1
- Fixed the AI Vault Orchestrator bug where Pitch, Vocal Map, and Lyrics indicators were erroneously showing as missing in the UI by ensuring `vox_meta.json` is correctly finalized.
- Updated `practice_app` to pass song metadata (title/artist) to `vox_player_core` for background notifications.
- Added Notification permissions request in Dashboard.
- Made the Active Session Playlist drawer responsive and added a toggle button.

## 1.6.2+1
- Pulled in `vox_player_core` 0.5.2 to integrate robust Playlist Management and Sleep Timer.
- Updated `SongCard` and `SongListTile` UI components to support adding songs to active playlists.
- Updated core Python backend (`karaoke_orchestrator.py`, `maker_service.py`, `task_worker.py`) for enhanced workflow orchestration.

## 1.6.1+1
- Unified search integrations and UI refinements.
- Core backend orchestrator updates for medley generation, queue items tracking, and async processing.
- Pulled in `vox_player_core` 0.5.1 containing UI bug fixes for `UNKNOWN_` prefixed songs and song library navigation.
- Added various Python engine fixes for file tracking and error resilience.

## 1.6.0+1
- Added skip previous and next buttons to the active session screen.
- Added batch rename and AI metadata features.
- Updated dependencies (vox_player_core to 0.5.0).

## 1.5.9+1
- Pulled in `vox_player_core` 0.4.9 which includes a collapsible controls panel.
- Fixed UI text scaling and added a Full Screen toggle to `ActiveSessionScreen` to maximize landscape viewing area on mobile devices.
- Refactored `FileExplorerService` to reliably scan local folders and parse song titles correctly when the local DB is empty.

## 1.5.8+1
- Pulled in vox_player_core 0.4.7 which includes Medley Draft saving and loading features.

## 1.5.7+1
- Integrated MedleyBuilderScreen and MedleyActiveSessionScreen into dashboard.
- Fixed python backend 	ask_worker medley generation path.
- Updated FileExplorerService to support legacy and prefixed profile lookups.

# Changelog

## 1.5.6+1
* Added support to automatically recall saved YouTube sequences from the AI Vault.
* Updated FileExplorerService to ingest and filter YouTube videos with saved performance profiles.
* Fixed an issue where switching back to a YouTube video bypassed profile loading.

