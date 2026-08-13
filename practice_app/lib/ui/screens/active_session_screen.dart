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
  final Playlist? activePlaylist;
  final Function(Song)? onSongSwitched;
  final VoidCallback? onToggleSidebar;
  final bool isFullScreen;
  final bool isTv;
  final VoidCallback? onToggleFullScreen;

  const ActiveSessionScreen({
    Key? key, 
    this.selectedSong,
    this.activePlaylist,
    this.onSongSwitched,
    this.onToggleSidebar,
    this.isFullScreen = false,
    this.isTv = false,
    this.onToggleFullScreen,
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

  int _playlistIndex = 0;
  bool _isShuffle = false;
  int _repeatMode = 0; // 0=none, 1=all, 2=one
  bool _isHoveringPlaylist = false;
  bool _isPlaylistPinned = false;

  Song? get _currentSong {
    if (widget.activePlaylist != null && widget.activePlaylist!.items.isNotEmpty) {
      if (_playlistIndex >= widget.activePlaylist!.items.length) {
        _playlistIndex = 0;
      }
      final item = widget.activePlaylist!.items[_playlistIndex];
      return Song(
        mmId: item.source == 'vault' ? item.songId : null,
        title: item.title,
        artist: item.artist,
        directoryPath: item.directoryPath ?? (item.source == 'youtube' ? 'https://youtube.com/watch?v=${item.songId}' : ''),
      );
    }
    return widget.selectedSong;
  }

  @override
  void initState() {
    super.initState();
    _loadSong();
  }

  @override
  void didUpdateWidget(covariant ActiveSessionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedSong != oldWidget.selectedSong || widget.activePlaylist != oldWidget.activePlaylist) {
      if (widget.activePlaylist != oldWidget.activePlaylist) {
        _playlistIndex = 0;
      }
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

    if (_currentSong == null) {
      setState(() => _isLoading = false);
      return;
    }

    final song = _currentSong!;
    
    // Check if YouTube
    if (song.directoryPath.startsWith('http')) {
      String lyricsDir = '';
      if (song.mmId != null && song.mmId!.isNotEmpty && !song.mmId!.startsWith('UNKNOWN_')) {
        final aiService = VoxAiTrackingService.instance;
        lyricsDir = aiService.getArtifactDirectory(song.mmId!, song.title);
        _performanceProfile = await PerformanceProfileService.loadProfile(lyricsDir);
      }
      
      setState(() {
        if (lyricsDir.isNotEmpty) _currentLyricsDir = lyricsDir;
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

    if (song.mmId != null && song.mmId!.isNotEmpty && !song.mmId!.startsWith('UNKNOWN_')) {
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
    _songLyrics = await LyricsParser.parse(lyricsDir);
    
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

  void _handleSongFinished() {
    if (widget.activePlaylist == null || widget.activePlaylist!.items.isEmpty) return;
    
    if (_repeatMode == 2) {
      _loadSong();
      return;
    }

    if (_isShuffle) {
      setState(() {
        _playlistIndex = (DateTime.now().millisecondsSinceEpoch % widget.activePlaylist!.items.length);
        _loadSong();
      });
      return;
    }

    if (_playlistIndex < widget.activePlaylist!.items.length - 1) {
      setState(() {
        _playlistIndex++;
        _loadSong();
      });
    } else if (_repeatMode == 1) {
      setState(() {
        _playlistIndex = 0;
        _loadSong();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentSong == null) {
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

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.isFullScreen)
              Padding(
                padding: EdgeInsets.all(MediaQuery.of(context).size.width < 600 ? 12.0 : 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _currentSong!.title,
                                style: TextStyle(
                                  color: VoxProTheme.accent,
                                  fontSize: MediaQuery.of(context).size.width < 600 ? 16 : 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.skip_previous, color: VoxProTheme.textSecondary),
                                  onPressed: () {
                                    if (widget.activePlaylist != null) {
                                      setState(() {
                                        _playlistIndex = (_playlistIndex - 1) % widget.activePlaylist!.items.length;
                                        if (_playlistIndex < 0) _playlistIndex += widget.activePlaylist!.items.length;
                                      });
                                      _loadSong();
                                      return;
                                    }
                                    if (widget.selectedSong == null || widget.onSongSwitched == null) return;
                                    final service = Provider.of<FileExplorerService>(context, listen: false);
                                    final songs = service.songs;
                                    if (songs.isEmpty) return;
                                    final currentIndex = songs.indexWhere((s) => s.id == widget.selectedSong!.id);
                                    if (currentIndex > 0) {
                                      widget.onSongSwitched!(songs[currentIndex - 1]);
                                    }
                                  },
                                  tooltip: 'Previous Song',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.skip_next, color: VoxProTheme.textSecondary),
                                  onPressed: () {
                                    if (widget.activePlaylist != null) {
                                      setState(() {
                                        if (_isShuffle) {
                                          _playlistIndex = DateTime.now().millisecondsSinceEpoch % widget.activePlaylist!.items.length;
                                        } else {
                                          _playlistIndex = (_playlistIndex + 1) % widget.activePlaylist!.items.length;
                                        }
                                      });
                                      _loadSong();
                                      return;
                                    }
                                    if (widget.selectedSong == null || widget.onSongSwitched == null) return;
                                    final service = Provider.of<FileExplorerService>(context, listen: false);
                                    final songs = service.songs;
                                    if (songs.isEmpty) return;
                                    final currentIndex = songs.indexWhere((s) => s.id == widget.selectedSong!.id);
                                    if (currentIndex >= 0 && currentIndex < songs.length - 1) {
                                      widget.onSongSwitched!(songs[currentIndex + 1]);
                                    }
                                  },
                                  tooltip: 'Next Song',
                                ),
                                if (widget.onToggleFullScreen != null)
                                  IconButton(
                                    icon: const Icon(Icons.fullscreen, color: VoxProTheme.textSecondary),
                                    onPressed: widget.onToggleFullScreen,
                                    tooltip: 'Full Screen Mode',
                                  ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                  Builder(
                    builder: (context) {
                      final result = VoxSearchResult(
                        id: _currentSong!.id,
                        title: _currentSong!.title,
                        artist: _currentSong!.artist,
                        url: _currentSong!.directoryPath,
                        sourceType: _currentSong!.directoryPath.startsWith('http') ? 'youtube' : 'LocalDirectory',
                      );
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_currentSong!.id.startsWith('UNKNOWN_'))
                              ElevatedButton.icon(
                                icon: const Icon(Icons.link, size: 16),
                                label: const Text('Link to MediaMonkey'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                onPressed: () {
                                  _showLinkDialog(context, _currentSong!);
                                },
                              ),
                            if (_currentSong!.id.startsWith('UNKNOWN_'))
                              const SizedBox(width: 8),
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
                                    songId: _currentSong!.id,
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
                                    songId: _currentSong!.id,
                                    title: _currentSong!.title,
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
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
            child: Builder(
              builder: (context) {
                String finalDirPath = _currentLyricsDir ?? _currentSong!.directoryPath;
                if (_currentSong != null && _currentSong!.mmId != null && _currentSong!.mmId!.isNotEmpty && !_currentSong!.mmId!.startsWith('UNKNOWN_')) {
                  finalDirPath = VoxAiTrackingService.instance.getArtifactDirectory(_currentSong!.mmId!, _currentSong!.title);
                }
                
                return VoxPlayerDashboard(
                  source: _mediaSource,
                  lyrics: _songLyrics,
                  pitchData: _targetPitchData,
                  vocalMapData: _vocalMapData,
                  directoryPath: finalDirPath,
                  vocalsPath: _currentVocalsPath,
                  performanceProfile: _performanceProfile,
                  onFinished: _handleSongFinished,
                  onProfileSaved: (profile) {
                    if (_currentSong != null) {
                      PerformanceProfileService.saveProfile(finalDirPath, profile);
                    }
                    setState(() {
                      _performanceProfile = profile;
                    });
                  },
                  onAudioAdjustmentsChanged: (pitch, tempo) {
                    _currentPitch = pitch;
                    _currentTempo = tempo;
                  },
                  config: (widget.isFullScreen && widget.isTv) 
                      ? VoxDashboardConfig.tvFullScreen()
                      : VoxDashboardConfig.practiceMode(),
                );
              }
            ),
          ),
        ],
      ),
      if (widget.isFullScreen && widget.onToggleFullScreen != null)
        Positioned(
          top: 16,
          right: 16,
          child: IconButton(
            icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black54,
              padding: const EdgeInsets.all(8),
            ),
            onPressed: widget.onToggleFullScreen,
            tooltip: 'Exit Full Screen',
          ),
        ),
      if (widget.activePlaylist != null && !widget.isFullScreen)
        _buildPlaylistDrawer(),
    ]);
  }

  Widget _buildPlaylistDrawer() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      right: (_isHoveringPlaylist || _isPlaylistPinned) ? 0 : -300,
      top: 0,
      bottom: 0,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHoveringPlaylist = true),
        onExit: (_) => setState(() => _isHoveringPlaylist = false),
        child: Container(
          width: 320,
          decoration: BoxDecoration(
            color: VoxProTheme.sidebar.withOpacity(0.95),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 10,
                offset: const Offset(-2, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: VoxProTheme.background,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Up Next', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: Icon(_isPlaylistPinned ? Icons.push_pin : Icons.push_pin_outlined, color: _isPlaylistPinned ? VoxProTheme.accent : Colors.white54),
                          onPressed: () => setState(() => _isPlaylistPinned = !_isPlaylistPinned),
                          tooltip: _isPlaylistPinned ? 'Unpin Playlist' : 'Pin Playlist',
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: Icon(Icons.shuffle, color: _isShuffle ? VoxProTheme.accent : Colors.white54),
                          onPressed: () => setState(() => _isShuffle = !_isShuffle),
                          tooltip: 'Shuffle',
                        ),
                        IconButton(
                          icon: Icon(
                            _repeatMode == 2 ? Icons.repeat_one : Icons.repeat,
                            color: _repeatMode > 0 ? VoxProTheme.accent : Colors.white54,
                          ),
                          onPressed: () {
                            setState(() {
                              _repeatMode = (_repeatMode + 1) % 3;
                            });
                          },
                          tooltip: 'Repeat',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.activePlaylist!.items.length,
                  itemBuilder: (context, index) {
                    final item = widget.activePlaylist!.items[index];
                    final isPlaying = index == _playlistIndex;
                    return ListTile(
                      tileColor: isPlaying ? VoxProTheme.accent.withOpacity(0.2) : null,
                      leading: isPlaying 
                        ? const Icon(Icons.volume_up, color: VoxProTheme.accent)
                        : Text('${index + 1}', style: const TextStyle(color: Colors.white54)),
                      title: Text(item.title, style: TextStyle(color: isPlaying ? VoxProTheme.accent : Colors.white, fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal)),
                      subtitle: Text(item.artist, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      onTap: () {
                        setState(() {
                          _playlistIndex = index;
                          _loadSong();
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLinkDialog(BuildContext context, Song song) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: VoxProTheme.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 800,
            height: 600,
            padding: const EdgeInsets.all(16),
            child: UnifiedSearchUI(
              initialQuery: song.title,
              providers: [MediaMonkeySearchProvider(prioritizeLocal: true)],
              actionBuilder: (ctx, result) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: VoxProTheme.vocalAccent),
                      onPressed: () async {
                        Navigator.pop(dialogContext); // close dialog
                        try {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Linking "${song.title}" to MediaMonkey...')),
                          );
                          await VoxApiService.linkMediaMonkey(
                            oldId: song.id,
                            newMmId: result.id,
                            cleanTitle: song.title,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Successfully linked! Please refresh your library.')),
                            );
                            Provider.of<FileExplorerService>(context, listen: false).scanDirectory();
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      child: const Text('Link This Song'),
                    ),
                  ],
                );
              },
              onAddNotFound: () async {
                Navigator.pop(dialogContext);
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Add to MediaMonkey'),
                    content: const Text(
                      'Please ensure MediaMonkey is OPEN before clicking Proceed. '
                      'This will instruct MediaMonkey to add this song to your library via the COM API.'
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          try {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Adding "${song.title}" to MediaMonkey...')),
                            );
                            await VoxApiService.addMediaMonkey(
                              oldId: song.id,
                              cleanTitle: song.title,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Successfully added and linked! Please refresh.')),
                              );
                              Provider.of<FileExplorerService>(context, listen: false).scanDirectory();
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 10)),
                              );
                            }
                          }
                        },
                        child: const Text('Proceed'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
