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
import '../widgets/practice/ab_loop_editor_dialog.dart';
import '../widgets/practice/sequence_editor_dialog.dart';
import '../widgets/practice/segmented_progress_bar.dart';
import '../../services/mic_pitch_service.dart';
import '../../services/settings_service.dart';
import '../../services/performance_profile_service.dart';
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
  bool _showPitchGraph = true;
  final MicPitchService _micService = MicPitchService();
  StreamSubscription<double>? _pitchSub;
  final List<Map<String, dynamic>> _userPitches = [];
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  List<dynamic> _targetPitchData = [];
  List<dynamic> _vocalMapData = [];
  SongLyrics? _songLyrics;
  String _selectedRootNote = 'C';

  // Practice Mode State
  PerformanceProfile? _performanceProfile;
  bool _isLoopMode = false;
  Duration? _loopA;
  Duration? _loopB;
  
  bool _isSequenceMode = false;
  NamedSequence? _activeSequence;
  int _currentSequenceIndex = 0;
  bool _isSeekingToEnforce = false;
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
        if (_isSeekingToEnforce) return;

        // Enforce Loop Mode
        if (_isLoopMode && _loopA != null && _loopB != null) {
          if (newPosition >= _loopB!) {
            _isSeekingToEnforce = true;
            Future.microtask(() async {
               await _audioPlayer.seek(_loopA!);
               if (widget.selectedSong!.hasVocals) await _vocalPlayer.seek(_loopA!);
               _isSeekingToEnforce = false;
            });
            return;
          }
        }
        
        // Enforce Sequence Mode
        if (_isSequenceMode && _activeSequence != null && _activeSequence!.segments.isNotEmpty) {
           if (_currentSequenceIndex < _activeSequence!.segments.length) {
             final currentSegment = _activeSequence!.segments[_currentSequenceIndex];
             
             if (newPosition + const Duration(milliseconds: 300) < currentSegment.start) {
                _isSeekingToEnforce = true;
                Future.microtask(() async {
                   await _audioPlayer.seek(currentSegment.start);
                   if (widget.selectedSong!.hasVocals) await _vocalPlayer.seek(currentSegment.start);
                   _isSeekingToEnforce = false;
                });
                return;
             }
             
             if (newPosition >= currentSegment.end) {
               _currentSequenceIndex++;
               if (_currentSequenceIndex < _activeSequence!.segments.length) {
                  final nextSegment = _activeSequence!.segments[_currentSequenceIndex];
                  _isSeekingToEnforce = true;
                  Future.microtask(() async {
                     await _audioPlayer.seek(nextSegment.start);
                     if (widget.selectedSong!.hasVocals) await _vocalPlayer.seek(nextSegment.start);
                     _isSeekingToEnforce = false;
                  });
                  return;
               } else {
                  // Sequence finished
                  _audioPlayer.pause();
                  if (widget.selectedSong!.hasVocals) _vocalPlayer.pause();
               }
             }
           }
        }

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
      
      // Load Performance Profile
      _performanceProfile = await PerformanceProfileService.loadProfile(widget.selectedSong!.directoryPath);
      if (_performanceProfile!.lastAbLoop != null) {
        _loopA = _performanceProfile!.lastAbLoop!.start;
        _loopB = _performanceProfile!.lastAbLoop!.end;
      } else {
        _loopA = null;
        _loopB = null;
      }
      _isLoopMode = false;
      _isSequenceMode = false;
      _activeSequence = null;

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

  void _jumpToActiveSequenceStart() async {
    if (_isSequenceMode && _activeSequence != null && _activeSequence!.segments.isNotEmpty) {
      final startPos = _activeSequence!.segments[0].start;
      setState(() {
        _currentSequenceIndex = 0;
      });
      _isSeekingToEnforce = true;
      await _audioPlayer.seek(startPos);
      if (widget.selectedSong != null && widget.selectedSong!.hasVocals) {
        await _vocalPlayer.seek(startPos);
      }
      _isSeekingToEnforce = false;
    }
  }

  void _showABLoopEditor() {
    if (widget.selectedSong == null) return;
    showDialog(
      context: context,
      builder: (context) => ABLoopEditorDialog(
        totalDuration: _duration,
        initialA: _loopA ?? _position,
        initialB: _loopB ?? (_position + const Duration(seconds: 10)),
        onSave: (a, b) async {
          setState(() {
            _loopA = a;
            _loopB = b;
            _isLoopMode = true;
            _isSequenceMode = false;
          });
          
          if (_performanceProfile != null) {
            _performanceProfile!.lastAbLoop = PlaybackSegment(start: a, end: b);
            await PerformanceProfileService.saveProfile(widget.selectedSong!.directoryPath, _performanceProfile!);
          }
        },
      ),
    );
  }

  void _showSequenceEditor() {
    if (widget.selectedSong == null) return;
    showDialog(
      context: context,
      builder: (context) => SequenceEditorDialog(
        totalDuration: _duration,
        initialSequence: _activeSequence,
        onSave: (seq) async {
          setState(() {
            _activeSequence = seq;
            _isSequenceMode = true;
            _isLoopMode = false;
            _currentSequenceIndex = 0;
            
            if (_performanceProfile != null) {
              // Update or add sequence
              final idx = _performanceProfile!.sequences.indexWhere((e) => e.name == seq.name);
              if (idx >= 0) {
                _performanceProfile!.sequences[idx] = seq;
              } else {
                _performanceProfile!.sequences.add(seq);
              }
            }
          });
          
          if (_performanceProfile != null) {
            await PerformanceProfileService.saveProfile(widget.selectedSong!.directoryPath, _performanceProfile!);
          }
        },
      ),
    );
  }

  Widget _buildPracticeToolbar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilterChip(
            label: const Text('A-B Loop'),
            selected: _isLoopMode,
            onSelected: (val) {
              setState(() {
                _isLoopMode = val;
                if (_isLoopMode) _isSequenceMode = false;
                if (_isLoopMode && _loopA == null) {
                  _loopA = _position;
                  _loopB = _position + const Duration(seconds: 10);
                }
              });
            },
            selectedColor: VoxProTheme.accent.withOpacity(0.3),
            avatar: const Icon(Icons.repeat, size: 18),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Sequence'),
            selected: _isSequenceMode,
            onSelected: (val) {
              setState(() {
                _isSequenceMode = val;
                if (_isSequenceMode) _isLoopMode = false;
              });
              if (val) {
                _jumpToActiveSequenceStart();
              }
            },
            selectedColor: VoxProTheme.accent.withOpacity(0.3),
            avatar: const Icon(Icons.queue_music, size: 18),
          ),
          const SizedBox(width: 16),
          if (_isLoopMode) ...[
            TextButton(
              onPressed: () => setState(() => _loopA = _position),
              child: const Text('Set A'),
            ),
            TextButton(
              onPressed: () => setState(() => _loopB = _position),
              child: const Text('Set B'),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: _showABLoopEditor,
            ),
          ],
          if (_isSequenceMode) ...[
            DropdownButtonHideUnderline(
              child: DropdownButton<NamedSequence>(
                value: _activeSequence,
                hint: const Text('Select Sequence', style: TextStyle(color: VoxProTheme.textSecondary, fontSize: 14)),
                dropdownColor: VoxProTheme.cardBg,
                items: (_performanceProfile?.sequences ?? []).map((seq) {
                  return DropdownMenuItem(
                    value: seq,
                    child: Text(seq.name, style: const TextStyle(fontSize: 14)),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _activeSequence = val;
                    _currentSequenceIndex = 0;
                  });
                  _jumpToActiveSequenceStart();
                },
              ),
            ),
            if (_activeSequence != null && 
                _activeSequence!.segments.isNotEmpty && 
                _currentSequenceIndex >= 0 && 
                _currentSequenceIndex < _activeSequence!.segments.length) ...[
              TextButton(
                onPressed: () {
                  setState(() {
                    _activeSequence!.segments[_currentSequenceIndex].start = _position;
                  });
                  if (_performanceProfile != null && widget.selectedSong != null) {
                    PerformanceProfileService.saveProfile(widget.selectedSong!.directoryPath, _performanceProfile!);
                  }
                },
                child: const Text('Set Start'),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _activeSequence!.segments[_currentSequenceIndex].end = _position;
                  });
                  if (_performanceProfile != null && widget.selectedSong != null) {
                    PerformanceProfileService.saveProfile(widget.selectedSong!.directoryPath, _performanceProfile!);
                  }
                },
                child: const Text('Set End'),
              ),
            ],
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: _showSequenceEditor,
            ),
            if (_activeSequence != null)
              IconButton(
                icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent),
                onPressed: () async {
                  // Confirm deletion
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: VoxProTheme.cardBg,
                      title: const Text('Delete Sequence?'),
                      content: Text('Are you sure you want to delete "${_activeSequence!.name}"?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel', style: TextStyle(color: VoxProTheme.textSecondary)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true && _performanceProfile != null && widget.selectedSong != null) {
                    setState(() {
                      _performanceProfile!.sequences.removeWhere((s) => s.name == _activeSequence!.name);
                      _activeSequence = null;
                      _currentSequenceIndex = 0;
                    });
                    await PerformanceProfileService.saveProfile(widget.selectedSong!.directoryPath, _performanceProfile!);
                  }
                },
              ),
          ]
        ],
      ),
    );
  }

  Color _getSingerColor(String? singer, {bool isUpcoming = false}) {
    Color baseColor;
    switch (singer) {
      case '1': baseColor = Colors.blueAccent; break;
      case '2': baseColor = Colors.pinkAccent; break;
      case '3': baseColor = Colors.amber; break;
      case 'B': baseColor = Colors.purpleAccent; break;
      default: baseColor = VoxProTheme.textPrimary;
    }
    return isUpcoming ? baseColor.withOpacity(0.6) : baseColor;
  }

  List<LyricLine> _getActiveLines(LyricsData? data) {
    if (data == null || data.lines.isEmpty) return [];
    if (!data.isSynced) {
      return [LyricLine(startTime: Duration.zero, text: "Lyrics available (unsynced)")];
    }
    
    int activeIndex = -1;
    for (int i = data.lines.length - 1; i >= 0; i--) {
      if (_position >= data.lines[i].startTime) {
        activeIndex = i;
        break;
      }
    }
    
    List<LyricLine> lines = [];
    if (activeIndex != -1) {
      lines.add(data.lines[activeIndex]);
    } else if (data.lines.isNotEmpty) {
      // Empty placeholder for the active line so the next line renders correctly
      lines.add(LyricLine(startTime: Duration.zero, text: ""));
    }
    
    int nextIndex = activeIndex == -1 ? 0 : activeIndex + 1;
    if (nextIndex < data.lines.length) {
      lines.add(data.lines[nextIndex]);
    }
    
    return lines;
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
                        icon: Icon(_showPitchGraph ? Icons.show_chart : Icons.stacked_line_chart, size: 28),
                        color: _showPitchGraph ? VoxProTheme.accent : VoxProTheme.textSecondary,
                        onPressed: () {
                          setState(() {
                            _showPitchGraph = !_showPitchGraph;
                          });
                        },
                        tooltip: 'Toggle Pitch Graph',
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
                    if (_showPitchGraph)
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
                          ..._getActiveLines(_songLyrics!.nativeData).asMap().entries.map((entry) {
                            bool isCurrent = entry.key == 0 && entry.value.text.isNotEmpty;
                            return Text(
                              entry.value.text,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: isCurrent ? 18 : 14,
                                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                                color: _getSingerColor(entry.value.singerPart, isUpcoming: !isCurrent),
                                shadows: const [Shadow(blurRadius: 4.0, color: Colors.black, offset: Offset(0, 1))],
                              ),
                            );
                          }),
                        if (_songLyrics!.englishData != null && _songLyrics!.nativeData != null)
                          const SizedBox(height: 8),
                        if (_songLyrics!.englishData != null)
                          ..._getActiveLines(_songLyrics!.englishData).asMap().entries.map((entry) {
                            bool isCurrent = entry.key == 0 && entry.value.text.isNotEmpty;
                            return Text(
                              entry.value.text,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: isCurrent ? 26 : 18,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                color: _getSingerColor(entry.value.singerPart, isUpcoming: !isCurrent),
                                shadows: const [Shadow(blurRadius: 8.0, color: Colors.black87, offset: Offset(0, 2))],
                              ),
                            );
                          }),
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
            width: isNarrow ? null : (!_showPitchGraph ? null : 350),
            height: isNarrow ? (!_showPitchGraph ? null : 250) : null,
            margin: EdgeInsets.only(
              right: isNarrow ? 16.0 : 24.0,
              left: isNarrow ? 16.0 : (!_showPitchGraph ? 24.0 : 0.0),
              bottom: 8.0,
              top: 8.0,
            ),
            child: LyricsPanel(
              songLyrics: _songLyrics!,
              currentPosition: _position,
              directoryPath: widget.selectedSong!.directoryPath,
              isExpanded: !_showPitchGraph,
              onSeekRequested: (time) async {
                await _audioPlayer.seek(time);
                if (widget.selectedSong!.hasVocals) {
                  await _vocalPlayer.seek(time);
                }
              },
            ),
          );

          if (!_showPitchGraph) {
            return lyricsWidget;
          }

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
                child: SegmentedProgressBar(
                  duration: _duration,
                  position: _position,
                  isLoopMode: _isLoopMode,
                  loopA: _loopA,
                  loopB: _loopB,
                  isSequenceMode: _isSequenceMode,
                  segments: _activeSequence?.segments ?? [],
                  onSeek: (newPosition) async {
                    if (_isSequenceMode && _activeSequence != null) {
                      int newIdx = _activeSequence!.segments.indexWhere((seg) => newPosition < seg.end);
                      if (newIdx == -1) newIdx = _activeSequence!.segments.length;
                      setState(() {
                         _currentSequenceIndex = newIdx;
                      });
                    }
                    _isSeekingToEnforce = true;
                    await _audioPlayer.seek(newPosition);
                    if (widget.selectedSong!.hasVocals) {
                      await _vocalPlayer.seek(newPosition);
                    }
                    _isSeekingToEnforce = false;
                  },
                  onLoopChanged: (a, b) {
                    setState(() {
                      _loopA = a;
                      _loopB = b;
                    });
                    if (_performanceProfile != null) {
                      _performanceProfile!.lastAbLoop = PlaybackSegment(start: a, end: b);
                    }
                  },
                  onSegmentsChanged: (newSegments) {
                    if (_activeSequence != null) {
                      setState(() {
                        _activeSequence!.segments = newSegments;
                      });
                      if (_performanceProfile != null) {
                        final idx = _performanceProfile!.sequences.indexWhere((e) => e.name == _activeSequence!.name);
                        if (idx >= 0) _performanceProfile!.sequences[idx] = _activeSequence!;
                      }
                    }
                  },
                  onInteractionEnd: () async {
                    if (_performanceProfile != null && widget.selectedSong != null) {
                      await PerformanceProfileService.saveProfile(widget.selectedSong!.directoryPath, _performanceProfile!);
                    }
                  },
                ),
              ),
              Text(_formatDuration(_duration), style: const TextStyle(color: VoxProTheme.textSecondary)),
            ],
          ),
        ),

        // Practice Toolbar
        _buildPracticeToolbar(),

        // Controls
        Container(
          padding: const EdgeInsets.only(bottom: 24.0, left: 24.0, right: 24.0),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8.0, // Used instead of fixed SizedBoxes for Wrap
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
