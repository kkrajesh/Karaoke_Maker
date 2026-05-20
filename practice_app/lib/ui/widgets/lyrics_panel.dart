import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/lyrics_parser.dart';
import '../theme/voxpro_theme.dart';

class LyricsPanel extends StatefulWidget {
  final SongLyrics songLyrics;
  final Duration currentPosition;
  final String directoryPath;
  final void Function(Duration) onSeekRequested;
  final bool isExpanded;

  const LyricsPanel({
    Key? key,
    required this.songLyrics,
    required this.currentPosition,
    required this.directoryPath,
    required this.onSeekRequested,
    this.isExpanded = false,
  }) : super(key: key);

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _altScrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isAutoScrollEnabled = true;
  String _selectedLanguage = 'native'; // 'native' or 'english'
  int _lastActiveIndex = -1;
  bool _isSyncMode = false;
  int _editIndex = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    _altScrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  LyricsData? _getActiveLyricsData() {
    if (_selectedLanguage == 'native' && widget.songLyrics.nativeData != null) {
      return widget.songLyrics.nativeData;
    } else if (_selectedLanguage == 'english' && widget.songLyrics.englishData != null) {
      return widget.songLyrics.englishData;
    }
    // Fallback
    return widget.songLyrics.nativeData ?? widget.songLyrics.englishData;
  }

  @override
  void didUpdateWidget(LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (_isAutoScrollEnabled) {
      _scrollToActiveLine();
    }
  }

  void _scrollToActiveLine() {
    if (_isSyncMode) {
      if (_scrollController.hasClients && _editIndex >= 0) {
        final targetOffset = (_editIndex * 75.0) - 20.0;
        final clampedOffset = targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.animateTo(clampedOffset, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
      }
      if (_altScrollController.hasClients && _editIndex >= 0) {
        final targetOffset = (_editIndex * 75.0) - 20.0;
        final clampedOffset = targetOffset.clamp(0.0, _altScrollController.position.maxScrollExtent);
        _altScrollController.animateTo(clampedOffset, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
      }
      return;
    }

    final data = _getActiveLyricsData();
    if (data == null || !data.isSynced) return;

    int activeIndex = -1;
    for (int i = data.lines.length - 1; i >= 0; i--) {
      if (widget.currentPosition >= data.lines[i].startTime) {
        activeIndex = i;
        break;
      }
    }

    if (activeIndex != -1 && activeIndex != _lastActiveIndex) {
      _lastActiveIndex = activeIndex;
      
      final targetOffset = (activeIndex * 75.0) - 20.0;
      
      if (_scrollController.hasClients) {
        final clampedOffset = targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.animateTo(clampedOffset, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      }
      
      if (_altScrollController.hasClients) {
        final clampedOffset = targetOffset.clamp(0.0, _altScrollController.position.maxScrollExtent);
        _altScrollController.animateTo(clampedOffset, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      }
    }
  }

  Color _getSingerColor(String? singer, bool isActive, bool isPast) {
    if (isActive) return VoxProTheme.accent;
    if (isPast) return VoxProTheme.textSecondary.withOpacity(0.3);
    
    switch (singer) {
      case '1': return Colors.blueAccent;
      case '2': return Colors.pinkAccent;
      case '3': return Colors.amber;
      case 'B': return Colors.purpleAccent;
      default: return VoxProTheme.textPrimary;
    }
  }

  void _updateLine(int index, void Function(LyricLine) updater) {
    if (widget.songLyrics.nativeData != null && index < widget.songLyrics.nativeData!.lines.length) {
      updater(widget.songLyrics.nativeData!.lines[index]);
    }
    if (widget.songLyrics.englishData != null && index < widget.songLyrics.englishData!.lines.length) {
      updater(widget.songLyrics.englishData!.lines[index]);
    }
  }

  void _syncCurrentLine() {
    final data = _getActiveLyricsData();
    if (data == null || _editIndex >= data.lines.length) return;
    
    setState(() {
      _updateLine(_editIndex, (line) => line.startTime = widget.currentPosition);
      _editIndex++;
    });
    _scrollToActiveLine();
  }

  @override
  Widget build(BuildContext context) {
    final data = _getActiveLyricsData();
    
    // Determine which languages are available
    final hasNative = widget.songLyrics.nativeData != null;
    final hasEnglish = widget.songLyrics.englishData != null;
    
    if (_selectedLanguage == 'native' && !hasNative && hasEnglish) {
      _selectedLanguage = 'english';
    } else if (_selectedLanguage == 'english' && !hasEnglish && hasNative) {
      _selectedLanguage = 'native';
    }

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (_isSyncMode && event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
          _syncCurrentLine();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: BoxDecoration(
          color: VoxProTheme.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: VoxProTheme.border),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool showDual = widget.isExpanded || constraints.maxHeight >= 360;
            final bool isPortrait = constraints.maxHeight > constraints.maxWidth;

            return Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(_isSyncMode ? Icons.edit_off : Icons.edit),
                      color: _isSyncMode ? VoxProTheme.vocalAccent : VoxProTheme.textSecondary,
                      tooltip: 'Sync Mode',
                      onPressed: () {
                        setState(() {
                          _isSyncMode = !_isSyncMode;
                          if (_isSyncMode) {
                            _isAutoScrollEnabled = false;
                            _focusNode.requestFocus();
                          } else {
                            _isAutoScrollEnabled = true;
                          }
                        });
                      }
                    ),
                    if (_isSyncMode)
                      IconButton(
                        icon: const Icon(Icons.save),
                        color: Colors.greenAccent,
                        tooltip: 'Save Lyrics',
                        onPressed: () async {
                          bool saved = false;
                          if (widget.songLyrics.nativeData != null) {
                            await LyricsParser.saveLrc(widget.directoryPath, 'native', widget.songLyrics.nativeData!);
                            saved = true;
                          }
                          if (widget.songLyrics.englishData != null) {
                            await LyricsParser.saveLrc(widget.directoryPath, 'english', widget.songLyrics.englishData!);
                            saved = true;
                          }
                          if (saved && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lyrics saved!')));
                          }
                        }
                      ),
                  ],
                ),
                if (hasNative && hasEnglish && !showDual)
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'native', label: Text('Native', style: TextStyle(fontSize: 12))),
                      ButtonSegment(value: 'english', label: Text('English', style: TextStyle(fontSize: 12))),
                    ],
                    selected: {_selectedLanguage},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _selectedLanguage = selection.first;
                        _lastActiveIndex = -1; // Reset to force scroll
                      });
                    },
                    style: SegmentedButton.styleFrom(
                      backgroundColor: VoxProTheme.background,
                      selectedForegroundColor: Colors.white,
                      selectedBackgroundColor: VoxProTheme.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  )
                else if (!showDual)
                  Text(
                    hasNative ? 'Native Lyrics' : 'English Lyrics',
                    style: const TextStyle(color: VoxProTheme.textSecondary, fontWeight: FontWeight.bold),
                  )
                else if (showDual && hasNative && hasEnglish)
                  const Text(
                    'Native  |  English',
                    style: TextStyle(color: VoxProTheme.textSecondary, fontWeight: FontWeight.bold),
                  )
                else
                  Text(
                    hasNative ? 'Native Lyrics' : 'English Lyrics',
                    style: const TextStyle(color: VoxProTheme.textSecondary, fontWeight: FontWeight.bold),
                  ),
                  
                if (!_isAutoScrollEnabled)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _isAutoScrollEnabled = true;
                        _lastActiveIndex = -1;
                      });
                      _scrollToActiveLine();
                    },
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text('Sync', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: VoxProTheme.vocalAccent,
                    ),
                  )
                else
                  const Icon(Icons.sync, size: 16, color: VoxProTheme.textSecondary),
              ],
            ),
          ),
          const Divider(height: 1, color: VoxProTheme.border),
          
          // Lyrics List
          Expanded(
            child: (data == null || data.lines.isEmpty)
                ? const Center(child: Text('No lyrics found', style: TextStyle(color: VoxProTheme.textSecondary)))
                : Builder(builder: (context) {
                    if (showDual && hasNative && hasEnglish) {
                      final primaryData = _selectedLanguage == 'native' ? widget.songLyrics.nativeData! : widget.songLyrics.englishData!;
                      final secondaryData = _selectedLanguage == 'native' ? widget.songLyrics.englishData! : widget.songLyrics.nativeData!;

                      if (isPortrait) {
                        return Column(
                          children: [
                            Expanded(child: _buildListView(primaryData, _scrollController, false, isDual: true)),
                            const Divider(height: 1, color: VoxProTheme.border),
                            Expanded(child: _buildListView(secondaryData, _altScrollController, true, isDual: true)),
                          ],
                        );
                      } else {
                        return Row(
                          children: [
                            Expanded(child: _buildListView(primaryData, _scrollController, false, isDual: true)),
                            const VerticalDivider(width: 1, color: VoxProTheme.border),
                            Expanded(child: _buildListView(secondaryData, _altScrollController, true, isDual: true)),
                          ],
                        );
                      }
                    } else {
                      return _buildListView(data, _scrollController, false, isDual: false);
                    }
                }),
          ),
        ],
      );
    }),
    ),
    );
  }

  Widget _buildListView(LyricsData data, ScrollController controller, bool isSecondary, {bool isDual = false}) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification && notification.dragDetails != null) {
          if (_isAutoScrollEnabled) {
            setState(() { _isAutoScrollEnabled = false; });
          }
        }
        return false;
      },
      child: ListView.builder(
        controller: controller,
        padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
        itemExtent: 75.0,
        itemCount: data.lines.length,
        itemBuilder: (context, index) {
          final line = data.lines[index];
          final isPast = widget.currentPosition >= line.startTime;
          final isNext = index < data.lines.length - 1 && widget.currentPosition < data.lines[index + 1].startTime;
          final isActive = isPast && isNext;
          
          final isVeryLastLineActive = index == data.lines.length - 1 && isPast;
          final finalIsActive = isActive || isVeryLastLineActive;

          return _buildRow(line, finalIsActive, isPast, index, isSecondary: isSecondary, isDual: isDual);
        },
      ),
    );
  }

  Widget _buildRow(LyricLine line, bool isActive, bool isPast, int index, {bool isSecondary = false, bool isDual = false}) {
    if (!_isSyncMode) {
      double fontSizeActive = isDual ? (isSecondary ? 18.0 : 22.0) : 18.0;
      double fontSizeNormal = isDual ? (isSecondary ? 16.0 : 18.0) : 16.0;
      
      return InkWell(
        onTap: () => widget.onSeekRequested(line.startTime),
        child: Container(
          alignment: Alignment.center,
          child: Text(
            line.text,
            style: TextStyle(
              fontSize: isActive ? fontSizeActive : fontSizeNormal,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: _getSingerColor(line.singerPart, isActive, isPast),
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    } else {
      final isEditing = index == _editIndex;
      final isSynced = line.startTime > Duration.zero;
      
      return Container(
        color: isEditing ? Colors.white.withOpacity(0.05) : null,
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Row(
          children: [
            SizedBox(
              width: 45,
              child: Text(
                isSynced ? '${line.startTime.inMinutes}:${(line.startTime.inSeconds % 60).toString().padLeft(2, '0')}' : '--:--',
                style: TextStyle(fontSize: 12, color: isSynced ? Colors.green : Colors.grey),
              ),
            ),
            Expanded(
              child: Text(
                line.text,
                style: TextStyle(
                  fontSize: 16.0,
                  color: _getSingerColor(line.singerPart, false, false),
                  fontWeight: isEditing ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: line.singerPart,
                icon: const Icon(Icons.person, size: 16, color: VoxProTheme.textSecondary),
                dropdownColor: VoxProTheme.cardBg,
                alignment: Alignment.centerRight,
                style: const TextStyle(fontSize: 12),
                items: const [
                  DropdownMenuItem(value: null, child: Text('None', style: TextStyle(color: Colors.grey))),
                  DropdownMenuItem(value: '1', child: Text('S1', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold))),
                  DropdownMenuItem(value: '2', child: Text('S2', style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold))),
                  DropdownMenuItem(value: '3', child: Text('S3', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))),
                  DropdownMenuItem(value: 'B', child: Text('All', style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold))),
                ],
                onChanged: (val) {
                  setState(() {
                    _updateLine(index, (l) => l.singerPart = val);
                  });
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.check_circle_outline, size: 20),
              color: isEditing ? VoxProTheme.accent : Colors.grey,
              onPressed: () {
                setState(() {
                  _updateLine(index, (l) => l.startTime = widget.currentPosition);
                  _editIndex = index + 1;
                });
                _scrollToActiveLine();
              },
            ),
            IconButton(
              icon: const Icon(Icons.clear, size: 20),
              color: Colors.redAccent,
              onPressed: () {
                setState(() {
                  _updateLine(index, (l) => l.startTime = Duration.zero);
                });
              },
            ),
          ],
        ),
      );
    }
  }
}
