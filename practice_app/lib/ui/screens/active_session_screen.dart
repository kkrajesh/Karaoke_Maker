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
import 'package:vox_player_core/src/api/vox_api_service.dart';

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
  String? _currentLyricsDir;
  String? _currentVocalsPath;
  
  double _currentPitch = 0.0;
  double _currentTempo = 1.0;

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
      _currentLyricsDir = null;
      _currentVocalsPath = null;
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
    // Local file handling
    String instPath;
    String pitchPath;
    String mapPath;
    String lyricsDir;
    String vocalsPath;

    if (song.mmId != null && song.mmId!.isNotEmpty) {
      final aiService = VoxAiTrackingService.instance;
      instPath = aiService.getInstrumentalPath(song.mmId!, song.title);
      pitchPath = aiService.getPitchDataPath(song.mmId!, song.title);
      mapPath = aiService.getVocalMapPath(song.mmId!, song.title);
      lyricsDir = aiService.getArtifactDirectory(song.mmId!, song.title);
      vocalsPath = aiService.getVocalsPath(song.mmId!, song.title);
    } else {
      lyricsDir = song.directoryPath;
      instPath = "${song.directoryPath}${Platform.pathSeparator}instrumental.wav";
      pitchPath = "${song.directoryPath}${Platform.pathSeparator}pitch_profile.json";
      mapPath = "${song.directoryPath}${Platform.pathSeparator}vocal_map.json";
      vocalsPath = "${song.directoryPath}${Platform.pathSeparator}vocals.wav";
      
      final dir = Directory(song.directoryPath);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            final fPath = entity.path;
            if (fPath.contains('instrumental.wav')) instPath = fPath;
            if (fPath.contains('pitch_profile.json')) pitchPath = fPath;
            if (fPath.contains('vocal_map.json')) mapPath = fPath;
            if (fPath.contains('vocals.wav')) vocalsPath = fPath;
          }
        }
      }
    }

    final File instFile = File(instPath);
    if (await instFile.exists()) {
      _mediaSource = VoxMediaSource(url: instPath);
    } else {
       if (FileSystemEntity.isFileSync(song.directoryPath)) {
          _mediaSource = VoxMediaSource(url: song.directoryPath);
          setState(() => _isLoading = false);
          return;
       }
    }

    // Load pitch profile
    if (song.hasPitchProfile) {
      final file = File(pitchPath);
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
      final file = File(mapPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        _vocalMapData = data['vocal_segments'] ?? [];
      }
    }
    
    // Load lyrics
    if (song.hasNativeLyrics || song.hasEnglishLyrics) {
      _songLyrics = await LyricsParser.parse(lyricsDir);
    }
    
    // Load Performance Profile
    _performanceProfile = await PerformanceProfileService.loadProfile(lyricsDir);

    if (mounted) {
      setState(() {
        _currentLyricsDir = lyricsDir;
        _currentVocalsPath = vocalsPath;
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
                  Builder(
                    builder: (context) {
                      final result = VoxSearchResult(
                        id: widget.selectedSong!.id,
                        title: widget.selectedSong!.title,
                        artist: '',
                        url: widget.selectedSong!.directoryPath,
                        sourceType: widget.selectedSong!.directoryPath.startsWith('http') ? 'youtube' : 'LocalDirectory',
                      );
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.music_note, size: 16),
                            label: const Text('Gen MP3s'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            onPressed: () async {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Starting MP3 generation...')),
                              );
                              try {
                                await VoxApiService.generatePracticeMp3s(
                                  songId: widget.selectedSong!.id,
                                  pitchShift: _currentPitch,
                                  tempoShift: _currentTempo,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('MP3 generation started successfully!')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
                                  );
                                }
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Regenerate Lyrics'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            onPressed: () async {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Re-processing lyrics through AI...')),
                              );
                              try {
                                await VoxApiService.reprocessComponent(
                                  songId: widget.selectedSong!.id,
                                  title: widget.selectedSong!.title,
                                  component: 'lyrics',
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Lyrics regeneration started! Please wait...')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
                                  );
                                }
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          AiQueueButton(result: result, isVisible: true),
                        ],
                      );
                    },
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
            directoryPath: _currentLyricsDir ?? widget.selectedSong!.directoryPath,
            vocalsPath: _currentVocalsPath,
            performanceProfile: _performanceProfile,
            onProfileSaved: (profile) {
              if (widget.selectedSong != null) {
                final saveDir = (widget.selectedSong!.mmId != null && widget.selectedSong!.mmId!.isNotEmpty) ? VoxAiTrackingService.instance.getArtifactDirectory(widget.selectedSong!.mmId!, widget.selectedSong!.title) : widget.selectedSong!.directoryPath;
                PerformanceProfileService.saveProfile(saveDir, profile);
              }
            },
            onAudioAdjustmentsChanged: (pitch, tempo) {
              _currentPitch = pitch;
              _currentTempo = tempo;
            },
            config: VoxDashboardConfig.practiceMode(),
          ),
        ),
      ],
    );
  }
}
