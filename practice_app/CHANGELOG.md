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
