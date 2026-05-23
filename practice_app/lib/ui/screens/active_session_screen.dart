import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import '../../models/song.dart';
import '../theme/voxpro_theme.dart';
import 'package:vox_player_core/vox_player_core.dart';
import '../../services/settings_service.dart';
import 'package:provider/provider.dart';
import '../../services/file_explorer_service.dart';

class ActiveSessionScreen extends StatefulWidget {
  final Song? selectedSong;
  final Function(Song)? onSongSwitched;
  final VoidCallback? onToggleSidebar;

  const ActiveSessionScreen({
    Key? key, 
    this.selectedSong,
    this.onSongSwitched,
    this.onToggleSidebar,
  }) : super(key: key);

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  VoxMediaSource? _mediaSource;
  List<Map<String, dynamic>> _targetPitchData = [];
  List<dynamic> _vocalMapData = [];
  SongLyrics? _songLyrics;
  String _selectedRootNote = 'C';
  PerformanceProfile? _performanceProfile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSong();
  }

  @override
  void didUpdateWidget(covariant ActiveSessionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedSong != oldWidget.selectedSong) {
      _loadSong();
    }
  }

  Future<void> _loadSong() async {
    setState(() {
      _isLoading = true;
      _mediaSource = null;
      _targetPitchData = [];
      _vocalMapData = [];
      _songLyrics = null;
      _performanceProfile = null;
    });

    if (widget.selectedSong == null) {
      setState(() => _isLoading = false);
      return;
    }

    final song = widget.selectedSong!;
    
    // Check if YouTube
    if (song.directoryPath.startsWith('http')) {
      setState(() {
        _mediaSource = VoxMediaSource(url: song.directoryPath, isYoutube: true);
        _isLoading = false;
      });
      return;
    }

    // Local file handling
    final String path = "${song.directoryPath}${Platform.pathSeparator}instrumental.wav";
    final File instFile = File(path);
    if (await instFile.exists()) {
      _mediaSource = VoxMediaSource(url: path);
    } else {
       if (FileSystemEntity.isFileSync(song.directoryPath)) {
          _mediaSource = VoxMediaSource(url: song.directoryPath);
          setState(() => _isLoading = false);
          return;
       }
    }

    // Load pitch profile
    if (song.hasPitchProfile) {
      final jsonPath = "${song.directoryPath}${Platform.pathSeparator}pitch_profile.json";
      final file = File(jsonPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        List<dynamic> rawPitchData = data['pitch_data'] ?? [];
        _targetPitchData = rawPitchData.cast<Map<String, dynamic>>();
        if (data['metadata'] != null && data['metadata']['estimated_sa_note'] != null) {
          String note = data['metadata']['estimated_sa_note'];
          _selectedRootNote = note.replaceAll(RegExp(r'\d'), '');
        }
      }
    }

    // Load vocal map
    if (song.hasVocalMap) {
      final mapPath = "${song.directoryPath}${Platform.pathSeparator}vocal_map.json";
      final file = File(mapPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        _vocalMapData = data['vocal_segments'] ?? [];
      }
    }
    
    // Load lyrics
    if (song.hasNativeLyrics || song.hasEnglishLyrics) {
      _songLyrics = await LyricsParser.parse(song.directoryPath);
    }
    
    // Load Performance Profile
    _performanceProfile = await PerformanceProfileService.loadProfile(song.directoryPath);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedSong == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mic_off, size: 64, color: VoxProTheme.textSecondary),
            SizedBox(height: 16),
            Text(
              'No Song Selected',
              style: TextStyle(color: VoxProTheme.textSecondary, fontSize: 18),
            ),
            SizedBox(height: 8),
            Text(
              'Please select a song from the Library to begin practice.',
              style: TextStyle(color: VoxProTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: VoxProTheme.accent));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.all(MediaQuery.of(context).size.width < 600 ? 16.0 : 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Active Session',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.selectedSong!.title,
                          style: const TextStyle(
                            color: VoxProTheme.accent,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        Expanded(
          child: VoxPlayerDashboard(
            source: _mediaSource,
            lyrics: _songLyrics,
            pitchData: _targetPitchData,
            vocalMapData: _vocalMapData,
            directoryPath: widget.selectedSong!.directoryPath,
            performanceProfile: _performanceProfile,
            onProfileSaved: (profile) {
              if (widget.selectedSong != null) {
                PerformanceProfileService.saveProfile(widget.selectedSong!.directoryPath, profile);
              }
            },
            config: VoxDashboardConfig.practiceMode(),
          ),
        ),
      ],
    );
  }
}
