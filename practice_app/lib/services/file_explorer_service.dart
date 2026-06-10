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
          if (dirName.startsWith('YT_')) {
            final mmId = dirName.split('_').take(2).join('_');
            if (verifiedSongs.any((s) => s.mmId == mmId)) {
               continue;
            }
            final profileFile = File('${dir.path}${Platform.pathSeparator}performance_profiles.json');
            if (profileFile.existsSync()) {
               final title = dirName.substring(mmId.length).replaceFirst(RegExp(r'^_'), '');
               final ytUrl = 'https://youtube.com/watch?v=${mmId.replaceFirst('YT_', '')}';
               final song = Song(
                 title: title.isEmpty ? 'YouTube Video' : title,
                 directoryPath: ytUrl,
                 mmId: mmId,
                 isMissing: false,
               );
               song.hasPerformanceProfile = true;
               verifiedSongs.add(song);
            }
          }
        }
      }
      
      songs = verifiedSongs;
      currentDirectory = vaultPath; // Just to satisfy UI display
    } catch (e, st) {
      print("Error scanning AI Vault: $e");
      songs = [];
    }

    isLoading = false;
    notifyListeners();
  }
}
