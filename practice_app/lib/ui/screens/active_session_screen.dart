import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:convert';
import '../../models/song.dart';
import '../theme/voxpro_theme.dart';
import '../widgets/pitch_canvas.dart';
import '../../services/lyrics_parser.dart';

class ActiveSessionScreen extends StatefulWidget {
  final Song? selectedSong;

  const ActiveSessionScreen({Key? key, this.selectedSong}) : super(key: key);

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _vocalPlayer = AudioPlayer();
  bool _isPlaying = false;
  String _playbackMode = 'instrumental'; // 'instrumental', 'both', 'vocals'
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  List<dynamic> _targetPitchData = [];
  List<dynamic> _vocalMapData = [];
  LyricsData? _lyricsData;
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
          _lyricsData = lyrics;
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

  String _getCurrentLyric() {
    if (_lyricsData == null || _lyricsData!.lines.isEmpty) return "";
    if (!_lyricsData!.isSynced) return "Lyrics available (unsynced)";
    
    // Find the current active line
    for (int i = _lyricsData!.lines.length - 1; i >= 0; i--) {
      if (_position >= _lyricsData!.lines[i].startTime) {
        return _lyricsData!.lines[i].text;
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
          padding: const EdgeInsets.all(24.0),
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
              ),
            ],
          ),
        ),
        
        if (widget.selectedSong!.hasVocals)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('Root (Sa): ', style: TextStyle(color: VoxProTheme.textSecondary)),
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
                const SizedBox(width: 24),
                const Text('Playback Mode: ', style: TextStyle(color: VoxProTheme.textSecondary)),
                const SizedBox(width: 8),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'instrumental', label: Text('Instrumental')),
                    ButtonSegment(value: 'both', label: Text('Both')),
                    ButtonSegment(value: 'vocals', label: Text('Vocals Only')),
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
              ],
            ),
          ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
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
                      ),
                
                // Overlay Lyrics at the bottom of the canvas
                if (_lyricsData != null)
                  Positioned(
                    bottom: 24.0,
                    left: 24.0,
                    right: 24.0,
                    child: Text(
                      _getCurrentLyric(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: VoxProTheme.textPrimary,
                        shadows: [
                          Shadow(
                            blurRadius: 8.0,
                            color: Colors.black87,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
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
            ],
          ),
        ),
      ],
    );
  }
}
