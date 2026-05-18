import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../models/song.dart';
import 'api_service.dart';

class FileExplorerService extends ChangeNotifier {
  static const String _dirKey = 'karaoke_hot_zone_dir';
  String? currentDirectory;
  List<Song> songs = [];
  bool isLoading = false;
  Map<String, String> activeTasks = {}; // taskId -> song name

  FileExplorerService() {
    _loadSavedDirectory();
  }

  void trackTask(String taskId, String songName, ScaffoldMessengerState messenger) async {
    activeTasks[taskId] = songName;
    notifyListeners();
    
    messenger.showSnackBar(
      SnackBar(content: Text('Processing "$songName" in background...')),
    );

    bool done = false;
    while (!done) {
      await Future.delayed(const Duration(seconds: 3));
      try {
        final status = await ApiService.getStatus(taskId);
        if (status['status'] == 'completed') {
          done = true;
          activeTasks.remove(taskId);
          scanDirectory(); // Refresh the library
          messenger.showSnackBar(
            SnackBar(content: Text('✅ "$songName" processing complete!')),
          );
        } else if (status['status'] == 'failed') {
          done = true;
          activeTasks.remove(taskId);
          messenger.showSnackBar(
            SnackBar(content: Text('❌ "$songName" failed: ${status['error']}')),
          );
        }
      } catch (e) {
        // Keep polling
      }
    }
    notifyListeners();
  }

  Future<void> _loadSavedDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    currentDirectory = prefs.getString(_dirKey);
    if (currentDirectory != null) {
      scanDirectory();
    }
  }

  Future<void> pickDirectory() async {
    String? selectedDirectory = await FilePicker.getDirectoryPath();
    if (selectedDirectory != null) {
      currentDirectory = selectedDirectory;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dirKey, selectedDirectory);
      scanDirectory();
    }
  }

  void scanDirectory() async {
    if (currentDirectory == null) return;
    
    isLoading = true;
    notifyListeners();

    try {
      final dir = Directory(currentDirectory!);
      if (!await dir.exists()) {
        songs = [];
      } else {
        // Find all subdirectories
        final entities = dir.listSync();
        final List<Song> loadedSongs = [];
        for (var entity in entities) {
          if (entity is Directory) {
            final song = Song.fromDirectory(entity);
            // Only add if it has at least the instrumental or pitch profile
            if (song.hasInstrumental || song.hasPitchProfile) {
              loadedSongs.add(song);
            }
          }
        }
        songs = loadedSongs;
      }
    } catch (e) {
      print("Error scanning directory: $e");
      songs = [];
    }

    isLoading = false;
    notifyListeners();
  }
}
