import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:convert';
import 'dart:async';
import '../../models/song.dart';
import '../theme/voxpro_theme.dart';
import '../widgets/pitch_canvas.dart';
import '../../services/lyrics_parser.dart';
import 'package:provider/provider.dart';
import '../../services/file_explorer_service.dart';
import '../widgets/song_search_dialog.dart';
import '../widgets/lyrics_panel.dart';
import '../../services/mic_pitch_service.dart';
import '../../services/settings_service.dart';

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
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _vocalPlayer = AudioPlayer();
  bool _isPlaying = false;
  String _playbackMode = 'both'; // instrumental, vocals, both
  bool _showLyricsPanel = false;
  final MicPitchService _micService = MicPitchService();
  StreamSubscription<double>? _pitchSub;
  final List<Map<String, dynamic>> _userPitches = [];
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  List<dynamic> _targetPitchData = [];
  List<dynamic> _vocalMapData = [];
  SongLyrics? _songLyrics;
  String _selectedRootNote = 'C';

  @override
  void initState() {
    super.initState();
    _initAudioPlayer();
  }

  @override
  void didUpdateWidget(covariant ActiveSessionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedSong != oldWidget.selectedSong) {
      _loadSong();
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    // Ensure the song loads if we hot reload while on this screen
    _loadSong();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _vocalPlayer.dispose();
    _pitchSub?.cancel();
    _micService.dispose();
    super.dispose();
  }

  void _initAudioPlayer() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((newDuration) {
      if (mounted) {
        setState(() {
          _duration = newDuration;
        });
      }
    });

    _audioPlayer.onPositionChanged.listen((newPosition) {
      if (mounted) {
        setState(() {
          _position = newPosition;
        });
      }
    });

    if (widget.selectedSong != null) {
      _loadSong();
    }
  }

  Future<void> _loadSong() async {
    await _audioPlayer.stop();
    await _vocalPlayer.stop();
    setState(() {
      _position = Duration.zero;
    });

    if (widget.selectedSong != null && widget.selectedSong!.hasInstrumental) {
      final String path = "${widget.selectedSong!.directoryPath}${Platform.pathSeparator}instrumental.wav";
      await _audioPlayer.setSource(DeviceFileSource(path));
      
      // Load pitch profile
      if (widget.selectedSong!.hasPitchProfile) {
        final jsonPath = "${widget.selectedSong!.directoryPath}${Platform.pathSeparator}pitch_profile.json";
        final file = File(jsonPath);
        if (await file.exists()) {
          final content = await file.readAsString();
          final data = jsonDecode(content);
          setState(() {
            _targetPitchData = data['pitch_data'] ?? [];
            if (data['metadata'] != null && data['metadata']['estimated_sa_note'] != null) {
              String note = data['metadata']['estimated_sa_note'];
              // Extract pitch class (e.g. 'C' from 'C3')
              _selectedRootNote = note.replaceAll(RegExp(r'\d'), '');
            } else {
              _selectedRootNote = 'C';
            }
          });
        }
      }

      // Load vocal map
      if (widget.selectedSong!.hasVocalMap) {
        final mapPath = "${widget.selectedSong!.directoryPath}${Platform.pathSeparator}vocal_map.json";
        final file = File(mapPath);
        if (await file.exists()) {
          final content = await file.readAsString();
          final data = jsonDecode(content);
          setState(() {
            _vocalMapData = data['vocal_segments'] ?? [];
          });
        }
      }
      
      // Load lyrics
      if (widget.selectedSong!.hasNativeLyrics || widget.selectedSong!.hasEnglishLyrics) {
        final lyrics = await LyricsParser.parse(widget.selectedSong!.directoryPath);
        setState(() {
          _songLyrics = lyrics;
        });
      }
      // Load vocals if available
      if (widget.selectedSong!.hasVocals) {
        final String vocalPath = "${widget.selectedSong!.directoryPath}${Platform.pathSeparator}vocals.wav";
        await _vocalPlayer.setSource(DeviceFileSource(vocalPath));
        await _vocalPlayer.setVolume(_playbackMode == 'instrumental' ? 0.0 : 1.0);
        await _audioPlayer.setVolume(_playbackMode == 'vocals' ? 0.0 : 1.0);
      }
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  String _getCurrentLyric(LyricsData? data) {
    if (data == null || data.lines.isEmpty) return "";
    if (!data.isSynced) return "Lyrics available (unsynced)";
    
    // Find the current active line
    for (int i = data.lines.length - 1; i >= 0; i--) {
      if (_position >= data.lines[i].startTime) {
        return data.lines[i].text;
      }
    }
    return "";
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_songLyrics != null && _songLyrics!.hasAnyLyrics)
                        IconButton(
                          icon: Icon(_showLyricsPanel ? Icons.subtitles_off : Icons.subtitles, size: 28),
                          color: _showLyricsPanel ? VoxProTheme.accent : VoxProTheme.textSecondary,
                          onPressed: () {
                            setState(() {
                              _showLyricsPanel = !_showLyricsPanel;
                            });
                          },
                          tooltip: 'Toggle Lyrics Panel',
                        ),
                      IconButton(
                        icon: const Icon(Icons.search, size: 32),
                        color: VoxProTheme.textSecondary,
                        onPressed: () async {
                          final service = Provider.of<FileExplorerService>(context, listen: false);
                          final newSong = await showDialog<Song>(
                            context: context,
                            builder: (context) => SongSearchDialog(allSongs: service.songs),
                          );
                          if (newSong != null && widget.onSongSwitched != null) {
                            widget.onSongSwitched!(newSong);
                          }
                        },
                        tooltip: 'Quick Search Songs',
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        
        if (widget.selectedSong!.hasVocals)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).size.width < 600 ? 16.0 : 24.0),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 16,
              children: [
                const Text('Root: ', style: TextStyle(color: VoxProTheme.textSecondary)),
                DropdownButton<String>(
                  value: _selectedRootNote,
                  dropdownColor: VoxProTheme.cardBg,
                  style: const TextStyle(color: VoxProTheme.textPrimary),
                  underline: const SizedBox(),
                  items: ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
                      .map((note) => DropdownMenuItem(value: note, child: Text(note)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedRootNote = val);
                  },
                ),
                const SizedBox(width: 8),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: 'instrumental', 
                      label: MediaQuery.of(context).size.width < 600 ? const Icon(Icons.music_note, size: 16) : const Text('Inst')
                    ),
                    ButtonSegment(
                      value: 'both', 
                      label: MediaQuery.of(context).size.width < 600 ? const Icon(Icons.library_music, size: 16) : const Text('Both')
                    ),
                    ButtonSegment(
                      value: 'vocals', 
                      label: MediaQuery.of(context).size.width < 600 ? const Icon(Icons.mic, size: 16) : const Text('Vocals')
                    ),
                  ],
                  selected: {_playbackMode},
                  onSelectionChanged: (Set<String> newSelection) async {
                    setState(() {
                      _playbackMode = newSelection.first;
                    });
                    await _audioPlayer.setVolume(_playbackMode == 'vocals' ? 0.0 : 1.0);
                    await _vocalPlayer.setVolume(_playbackMode == 'instrumental' ? 0.0 : 1.0);
                  },
                  style: SegmentedButton.styleFrom(
                    backgroundColor: VoxProTheme.cardBg,
                    selectedForegroundColor: Colors.white,
                    selectedBackgroundColor: VoxProTheme.accent,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(_micService.isRecording ? Icons.mic : Icons.mic_off),
                  color: _micService.isRecording ? Colors.red : VoxProTheme.textSecondary,
                  tooltip: _micService.isRecording ? 'Disable Mic Pitch' : 'Enable Mic Pitch',
                  onPressed: () async {
                    if (_micService.isRecording) {
                      await _micService.stop();
                      _pitchSub?.cancel();
                    } else {
                      final success = await _micService.start();
                      if (success) {
                        _pitchSub = _micService.pitchStream.listen((pitch) {
                          if (_audioPlayer.state == PlayerState.playing) {
                            setState(() {
                              _userPitches.add({
                                'time': _position.inMilliseconds / 1000.0,
                                'pitch': pitch,
                              });
                            });
                          }
                        });
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission denied.')));
                        }
                      }
                    }
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 600;
              
              final canvasWidget = Container(
                margin: EdgeInsets.symmetric(
                  horizontal: isNarrow ? 16.0 : 24.0, 
                  vertical: 8.0,
                ),
                decoration: BoxDecoration(
                  color: VoxProTheme.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: VoxProTheme.border),
                ),
                child: Stack(
                  children: [
                    _targetPitchData.isEmpty 
                        ? const Center(
                            child: Text(
                              'No pitch data available for this song.',
                              style: TextStyle(color: VoxProTheme.textSecondary),
                            ),
                          )
                        : PitchCanvas(
                            currentPosition: _position,
                            targetPitchData: _targetPitchData,
                            vocalMapData: _vocalMapData,
                            rootNote: _selectedRootNote,
                            userPitchData: _userPitches,
                            targetPitchColor: context.watch<SettingsService>().targetPitchColor,
                            userPitchColor: context.watch<SettingsService>().userPitchColor,
                          ),
                    
                    // Overlay Lyrics at the bottom of the canvas (only if panel is hidden)
                    if (!_showLyricsPanel && _songLyrics != null && _songLyrics!.hasAnyLyrics)
                  Positioned(
                    bottom: 24.0,
                    left: 24.0,
                    right: 24.0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_songLyrics!.nativeData != null)
                          Text(
                            _getCurrentLyric(_songLyrics!.nativeData),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.normal,
                              color: VoxProTheme.textSecondary.withOpacity(0.8),
                              shadows: const [
                                Shadow(blurRadius: 4.0, color: Colors.black, offset: Offset(0, 1)),
                              ],
                            ),
                          ),
                        if (_songLyrics!.englishData != null)
                          Text(
                            _getCurrentLyric(_songLyrics!.englishData),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: VoxProTheme.textPrimary,
                              shadows: [
                                Shadow(blurRadius: 8.0, color: Colors.black87, offset: Offset(0, 2)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          );

          if (!_showLyricsPanel || _songLyrics == null || !_songLyrics!.hasAnyLyrics) {
            return canvasWidget;
          }

          final lyricsWidget = Container(
            width: isNarrow ? null : 350,
            height: isNarrow ? 250 : null,
            margin: EdgeInsets.only(
              right: isNarrow ? 16.0 : 24.0,
              left: isNarrow ? 16.0 : 0.0,
              bottom: 8.0,
              top: 8.0,
            ),
            child: LyricsPanel(
              songLyrics: _songLyrics!,
              currentPosition: _position,
            ),
          );

          if (isNarrow) {
            return Column(
              children: [
                Expanded(child: canvasWidget),
                lyricsWidget,
              ],
            );
          } else {
            return Row(
              children: [
                Expanded(child: canvasWidget),
                lyricsWidget,
              ],
            );
          }
        },
      ),
    ),
        
        // Progress Slider
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Row(
            children: [
              Text(_formatDuration(_position), style: const TextStyle(color: VoxProTheme.textSecondary)),
              Expanded(
                child: Slider(
                  activeColor: VoxProTheme.accent,
                  inactiveColor: VoxProTheme.border,
                  min: 0,
                  max: _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1,
                  value: _position.inSeconds.toDouble().clamp(0, _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1),
                  onChanged: (value) async {
                    final newPosition = Duration(seconds: value.toInt());
                    await _audioPlayer.seek(newPosition);
                    if (widget.selectedSong!.hasVocals) {
                      await _vocalPlayer.seek(newPosition);
                    }
                  },
                ),
              ),
              Text(_formatDuration(_duration), style: const TextStyle(color: VoxProTheme.textSecondary)),
            ],
          ),
        ),

        // Controls
        Container(
          padding: const EdgeInsets.only(bottom: 24.0, left: 24.0, right: 24.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous, size: 36),
                onPressed: () async {
                  await _audioPlayer.seek(Duration.zero);
                  if (widget.selectedSong!.hasVocals) {
                    await _vocalPlayer.seek(Duration.zero);
                  }
                },
                color: VoxProTheme.textPrimary,
              ),
              const SizedBox(width: 24),
              Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: VoxProTheme.accent,
                ),
                child: IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 40),
                  onPressed: () async {
                    if (_isPlaying) {
                      await _audioPlayer.pause();
                      if (widget.selectedSong!.hasVocals) await _vocalPlayer.pause();
                    } else {
                      await _audioPlayer.resume();
                      if (widget.selectedSong!.hasVocals) await _vocalPlayer.resume();
                    }
                  },
                  color: VoxProTheme.background,
                ),
              ),
              const SizedBox(width: 24),
              IconButton(
                icon: const Icon(Icons.stop, size: 36),
                onPressed: () async {
                  await _audioPlayer.stop();
                  if (widget.selectedSong!.hasVocals) await _vocalPlayer.stop();
                  setState(() {
                    _position = Duration.zero;
                  });
                },
                color: VoxProTheme.textPrimary,
              ),
              const SizedBox(width: 24),
              IconButton(
                icon: const Icon(Icons.info_outline, size: 36),
                onPressed: () {
                  if (_songLyrics?.meaningText != null) {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: VoxProTheme.cardBg,
                        title: const Text('Poetic Meaning', style: TextStyle(color: VoxProTheme.accent)),
                        content: SingleChildScrollView(
                          child: Text(
                            _songLyrics!.meaningText!,
                            style: const TextStyle(color: VoxProTheme.textPrimary, fontSize: 16),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close', style: TextStyle(color: VoxProTheme.accent)),
                          ),
                        ],
                      ),
                    );
                  }
                },
                color: _songLyrics?.meaningText != null ? VoxProTheme.textPrimary : VoxProTheme.textSecondary.withOpacity(0.3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
