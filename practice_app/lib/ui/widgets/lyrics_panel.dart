import 'package:flutter/material.dart';
import '../../services/lyrics_parser.dart';
import '../theme/voxpro_theme.dart';

class LyricsPanel extends StatefulWidget {
  final SongLyrics songLyrics;
  final Duration currentPosition;

  const LyricsPanel({
    Key? key,
    required this.songLyrics,
    required this.currentPosition,
  }) : super(key: key);

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  final ScrollController _scrollController = ScrollController();
  bool _isAutoScrollEnabled = true;
  String _selectedLanguage = 'native'; // 'native' or 'english'
  int _lastActiveIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
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
      
      if (_scrollController.hasClients) {
        // Using a fixed itemExtent of 60.0 guarantees mathematically flawless scrolling offset.
        // We subtract a small amount (20.0) to keep it comfortably near the top.
        final targetOffset = (activeIndex * 60.0) - 20.0;
        final clampedOffset = targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent);
        
        _scrollController.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
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

    return Container(
      decoration: BoxDecoration(
        color: VoxProTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VoxProTheme.border),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (hasNative && hasEnglish)
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
            child: data == null || data.lines.isEmpty
                ? const Center(child: Text('No lyrics found', style: TextStyle(color: VoxProTheme.textSecondary)))
                : NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollUpdateNotification && notification.dragDetails != null) {
                        // User manually scrolled
                        if (_isAutoScrollEnabled) {
                          setState(() {
                            _isAutoScrollEnabled = false;
                          });
                        }
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                      itemExtent: 60.0, // Fixed height makes scrolling math 100% accurate
                      itemCount: data.lines.length,
                      itemBuilder: (context, index) {
                        final line = data.lines[index];
                        final isPast = widget.currentPosition >= line.startTime;
                        final isNext = index < data.lines.length - 1 && widget.currentPosition < data.lines[index + 1].startTime;
                        final isActive = isPast && isNext;
                        
                        // Handle the last line specifically
                        final isVeryLastLineActive = index == data.lines.length - 1 && isPast;
                        final finalIsActive = isActive || isVeryLastLineActive;

                        return Container(
                          alignment: Alignment.center,
                          child: Text(
                            line.text,
                            style: TextStyle(
                              fontSize: finalIsActive ? 18.0 : 16.0,
                              fontWeight: finalIsActive ? FontWeight.bold : FontWeight.normal,
                              color: finalIsActive 
                                  ? VoxProTheme.accent 
                                  : (isPast ? VoxProTheme.textSecondary.withOpacity(0.3) : VoxProTheme.textPrimary),
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2, // Allow wrapping but restrict to 2 lines to fit in 60px
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
