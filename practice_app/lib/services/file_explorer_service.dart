import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:vox_player_core/vox_player_core.dart';
import '../models/song.dart';

class FileExplorerService extends ChangeNotifier {
  static const String _dirKey = 'karaoke_hot_zone_dir';
  String? currentDirectory;
  List<Song> songs = [];
  bool isLoading = false;
  Map<String, String> activeTasks = {}; // taskId -> song name

  FileExplorerService() {
    VoxSettingsService.instance.initFuture.then((_) {
      scanDirectory();
    });
    
    VoxQueueManager.instance.onTaskCompleted.listen((task) {
      if (task['status'] == 'completed' || task['status'] == 'done' || task['status'] == 'audio_ready' || task['status'] == 'audioReady') {
        scanDirectory(); // Refresh the library
      }
    });
  }

  void trackTask(String taskId, String songId, String title, ScaffoldMessengerState messenger) {
    VoxQueueManager.instance.trackExistingTask(taskId, title, songId);
    
    messenger.showSnackBar(
      SnackBar(content: Text('Processing "$title" in background...')),
    );
  }

  // Pick directory is obsolete in Phase 9, but we keep the signature so UI doesn't break instantly
  Future<void> pickDirectory() async {
    String? path = await FilePicker.getDirectoryPath();
    if (path != null) {
      await VoxSettingsService.instance.setAiVaultPath(path);
      scanDirectory();
    }
  }

  Future<void> removeFromLibrary(String mmId) async {
    await VoxAiTrackingService.instance.deleteArtifact(mmId);
    scanDirectory(); // Refresh list after deletion
  }

  Future<void> renameSong(String mmId, String oldTitle, String newTitle) async {
    try {
      await VoxAiTrackingService.instance.renameArtifact(mmId, oldTitle, newTitle);
      scanDirectory();
    } catch (e) {
      print('Error renaming song: $e');
    }
  }

  void scanDirectory() async {
    isLoading = true;
    notifyListeners();

    try {
      final rows = await VoxAiTrackingService.instance.getAllArtifacts();
      final vaultPath = VoxSettingsService.instance.aiVaultPath;
      
      final List<Song> verifiedSongs = [];
      for (final row in rows) {
        final String mmId = row['mm_id']?.toString() ?? '';
        final String title = row['title']?.toString() ?? '';
        final actualDirPath = VoxAiTrackingService.instance.getArtifactDirectory(mmId, title);
        
        final song = Song.fromAiArtifact(row, actualDirPath);
        
        if (song.externalRelativePath != null) {
          final root = Platform.isAndroid 
              ? VoxSettingsService.instance.androidMusicRoot 
              : VoxSettingsService.instance.windowsMusicRoot;
          
          // Normalize path separators for cross-platform compatibility (e.g., Windows \ to Android /)
          final normalizedRelative = song.externalRelativePath!.replaceAll('\\', '/');
          final absolutePath = p.join(root, normalizedRelative);
          
          song.isMissing = !File(absolutePath).existsSync();
          
          // Fallback to case-insensitive search on Android if not found
          if (song.isMissing && Platform.isAndroid) {
            final resolvedFile = resolveFileCaseInsensitive(root, normalizedRelative);
            if (resolvedFile != null) {
              song.isMissing = false;
              // Update the absolute path dynamically for playback if needed,
              // though currently playback might rely on the original logic. 
              // We should probably just rely on this for the 'isMissing' flag 
              // for now, but also update active_session_screen to use it.
            }
          }
        } else {
          song.isMissing = !Directory(song.directoryPath).existsSync();
        }
        
        song.hasPerformanceProfile = PerformanceProfileService.hasProfileSync(song.directoryPath);
        
        verifiedSongs.add(song);
      }
      
      final vaultDir = Directory(vaultPath);
      if (vaultDir.existsSync()) {
        final dirs = vaultDir.listSync().whereType<Directory>();
        for (final dir in dirs) {
          final dirName = dir.path.split(Platform.pathSeparator).last;
          if (dirName.startsWith('.')) continue; // Ignore .tmp and other hidden folders
          if (dirName.toLowerCase() == 'playlists' || dirName.toLowerCase() == 'playlist') continue; // Ignore Playlists folder
          
          String mmId = '';
          String title = dirName;
          
          if (dirName.startsWith('YT_')) {
             mmId = dirName.split('_').take(2).join('_'); // 'YT_xxxxx'
             title = dirName.substring(mmId.length).replaceFirst(RegExp(r'^_'), '');
          } else {
             final parts = dirName.split('_');
             if (parts.length > 1 && RegExp(r'^\d+$').hasMatch(parts[0])) {
               // Standard mmId_title format (e.g. 12345_Song_Name)
               mmId = parts[0];
               title = parts.sublist(1).join('_');
             } else {
               if (dirName.startsWith('UNKNOWN_')) {
                 mmId = dirName;
                 title = dirName.substring(8);
               } else {
                 mmId = 'UNKNOWN_$dirName';
                 title = dirName;
               }
             }
          }

          if (verifiedSongs.any((s) => s.directoryPath == dir.path || (s.mmId == mmId && mmId.isNotEmpty && !mmId.startsWith('UNKNOWN_')))) {
             continue; // Already processed via SQLite
          }
          
          // Check what files exist
          final files = dir.listSync().map((e) => e.path.split(Platform.pathSeparator).last).toList();
          final hasInst = files.any((f) => f.contains('instrumental.'));
          final hasVocals = files.any((f) => f.contains('vocals.'));
          final hasPitch = files.any((f) => f.contains('pitch_profile.json'));
          final hasMap = files.any((f) => f.contains('vocal_map.json'));
          final hasLyrics = files.any((f) => f.contains('lyrics') && (f.endsWith('.lrc') || f.endsWith('.txt')));
          final hasProfile = files.any((f) => f.contains('performance_profiles.json'));
          
          final hasOriginal = files.any((f) => f.contains('original.'));

          if (!hasInst && !hasVocals && !hasOriginal) {
            continue; // Not a valid audio directory
          }

          final stat = dir.statSync();

          final song = Song(
            title: title.isEmpty ? dirName : title.replaceAll('_', ' '),
            directoryPath: dir.path, // We MUST use dir.path so the player can load local files
            mmId: mmId,
            isMissing: false,
            dateModified: stat.modified,
            hasInstrumental: hasInst,
            hasVocals: hasVocals,
            hasPitchProfile: hasPitch,
            hasVocalMap: hasMap,
            hasEnglishLyrics: hasLyrics,
            hasNativeLyrics: hasLyrics,
          );
          song.hasPerformanceProfile = hasProfile;
          
          verifiedSongs.add(song);
        }
      }
      
      songs = verifiedSongs;
      currentDirectory = vaultPath; // Just to satisfy UI display
    } catch (e, st) {
      print("Error scanning AI Vault: $e");
      songs = [
        Song(
          title: 'ERROR: $e',
          directoryPath: '',
          mmId: 'ERROR',
        )
      ];
    }

    isLoading = false;
    notifyListeners();
  }

  static File? resolveFileCaseInsensitive(String rootPath, String relativePath) {
    try {
      final parts = relativePath.split('/');
      Directory current = Directory(rootPath);
      
      if (!current.existsSync()) return null;
      
      for (int i = 0; i < parts.length; i++) {
        final part = parts[i];
        final isLast = i == parts.length - 1;
        
        bool found = false;
        final entities = current.listSync();
        for (final entity in entities) {
          final name = entity.path.split(Platform.pathSeparator).last;
          if (name.toLowerCase() == part.toLowerCase()) {
            if (isLast && entity is File) {
              return entity;
            } else if (!isLast && entity is Directory) {
              current = entity;
              found = true;
              break;
            }
          }
        }
        if (!found) return null;
      }
    } catch (e) {
      return null;
    }
    return null;
  }
}
