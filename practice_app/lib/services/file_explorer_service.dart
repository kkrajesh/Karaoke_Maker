import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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
  }

  void trackTask(String taskId, String songId, String title, ScaffoldMessengerState messenger) async {
    activeTasks[taskId] = title;
    notifyListeners();
    
    messenger.showSnackBar(
      SnackBar(content: Text('Processing "$title" in background...')),
    );

    bool done = false;
    while (!done) {
      await Future.delayed(const Duration(seconds: 3));
      try {
        final status = await VoxApiService.getStatus(taskId);
        if (status['status'] == 'completed') {
          done = true;
          activeTasks.remove(taskId);
          
          await VoxAiTrackingService.instance.ingestProcessedFiles(songId, title);
          
          scanDirectory(); // Refresh the library
          messenger.showSnackBar(
            SnackBar(content: Text('✅ "$title" processing complete!')),
          );
        } else if (status['status'] == 'failed') {
          done = true;
          activeTasks.remove(taskId);
          messenger.showSnackBar(
            SnackBar(content: Text('❌ "$title" failed: ${status['error']}')),
          );
        }
      } catch (e) {
        // Keep polling
      }
    }
    notifyListeners();
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
        song.isMissing = !Directory(song.directoryPath).existsSync();
        
        song.hasPerformanceProfile = PerformanceProfileService.hasProfileSync(song.directoryPath);
        
        verifiedSongs.add(song);
      }
      
      final vaultDir = Directory(vaultPath);
      if (vaultDir.existsSync()) {
        final dirs = vaultDir.listSync().whereType<Directory>();
        for (final dir in dirs) {
          final dirName = dir.path.split(Platform.pathSeparator).last;
          
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
               mmId = 'UNKNOWN_$dirName';
               title = dirName;
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
}
