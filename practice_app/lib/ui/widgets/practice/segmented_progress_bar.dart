import 'package:flutter/material.dart';
import '../../theme/voxpro_theme.dart';
import '../../../services/performance_profile_service.dart';

enum DragType { none, leftEdge, rightEdge, center, seek }

class DragTargetInfo {
  final int segmentIndex; // -1 for A-B Loop, >= 0 for Sequence segments
  final DragType type;
  DragTargetInfo(this.segmentIndex, this.type);
}

class SegmentedProgressBar extends StatefulWidget {
  final Duration duration;
  final Duration position;
  final Function(Duration) onSeek;
  
  final bool isLoopMode;
  final Duration? loopA;
  final Duration? loopB;
  final Function(Duration a, Duration b) onLoopChanged;
  
  final bool isSequenceMode;
  final List<PlaybackSegment> segments;
  final Function(List<PlaybackSegment>) onSegmentsChanged;
  
  final VoidCallback onInteractionEnd;

  const SegmentedProgressBar({
    Key? key,
    required this.duration,
    required this.position,
    required this.onSeek,
    required this.isLoopMode,
    this.loopA,
    this.loopB,
    required this.onLoopChanged,
    required this.isSequenceMode,
    required this.segments,
    required this.onSegmentsChanged,
    required this.onInteractionEnd,
  }) : super(key: key);

  @override
  State<SegmentedProgressBar> createState() => _SegmentedProgressBarState();
}

class _SegmentedProgressBarState extends State<SegmentedProgressBar> {
  DragTargetInfo? _dragInfo;
  double _initialDragX = 0;
  Duration _initialA = Duration.zero;
  Duration _initialB = Duration.zero;

  static const double _edgeTolerance = 12.0;

  double _durationToX(Duration d, double width) {
    if (widget.duration.inMilliseconds == 0) return 0;
    return (d.inMilliseconds / widget.duration.inMilliseconds) * width;
  }

  Duration _xToDuration(double x, double width) {
    if (width == 0) return Duration.zero;
    final ms = (x / width) * widget.duration.inMilliseconds;
    return Duration(milliseconds: ms.clamp(0, widget.duration.inMilliseconds.toDouble()).toInt());
  }

  void _handlePanStart(DragStartDetails details, double width) {
    if (widget.duration.inMilliseconds == 0) return;
    
    final x = details.localPosition.dx;
    _initialDragX = x;

    setState(() {
      // Check A-B Loop first
      if (widget.isLoopMode && widget.loopA != null && widget.loopB != null) {
        final startX = _durationToX(widget.loopA!, width);
        final endX = _durationToX(widget.loopB!, width);

        if ((x - startX).abs() <= _edgeTolerance) {
          _dragInfo = DragTargetInfo(-1, DragType.leftEdge);
          _initialA = widget.loopA!;
          _initialB = widget.loopB!;
          return;
        } else if ((x - endX).abs() <= _edgeTolerance) {
          _dragInfo = DragTargetInfo(-1, DragType.rightEdge);
          _initialA = widget.loopA!;
          _initialB = widget.loopB!;
          return;
        } else if (x > startX && x < endX) {
          _dragInfo = DragTargetInfo(-1, DragType.center);
          _initialA = widget.loopA!;
          _initialB = widget.loopB!;
          return;
        }
      }

      // Check Sequence Segments
      if (widget.isSequenceMode) {
        for (int i = 0; i < widget.segments.length; i++) {
          final seg = widget.segments[i];
          final startX = _durationToX(seg.start, width);
          final endX = _durationToX(seg.end, width);

          if ((x - startX).abs() <= _edgeTolerance) {
            _dragInfo = DragTargetInfo(i, DragType.leftEdge);
            _initialA = seg.start;
            _initialB = seg.end;
            return;
          } else if ((x - endX).abs() <= _edgeTolerance) {
            _dragInfo = DragTargetInfo(i, DragType.rightEdge);
            _initialA = seg.start;
            _initialB = seg.end;
            return;
          } else if (x > startX && x < endX) {
            _dragInfo = DragTargetInfo(i, DragType.center);
            _initialA = seg.start;
            _initialB = seg.end;
            return;
          }
        }
      }

      // Otherwise, it's a seek
      _dragInfo = DragTargetInfo(-2, DragType.seek);
    });
    widget.onSeek(_xToDuration(x, width));
  }

  void _handlePanUpdate(DragUpdateDetails details, double width) {
    if (_dragInfo == null) return;
    
    final x = details.localPosition.dx;
    
    if (_dragInfo!.type == DragType.seek) {
      widget.onSeek(_xToDuration(x, width));
      return;
    }
    
    final deltaMs = _xToDuration(x - _initialDragX, width).inMilliseconds;
    // Handle negatives correctly since _xToDuration clamps to 0
    final realDeltaMs = ((x - _initialDragX) / width) * widget.duration.inMilliseconds;
    
    Duration newA = _initialA;
    Duration newB = _initialB;
    
    if (_dragInfo!.type == DragType.leftEdge) {
      newA = Duration(milliseconds: (_initialA.inMilliseconds + realDeltaMs).toInt().clamp(0, newB.inMilliseconds - 100));
    } else if (_dragInfo!.type == DragType.rightEdge) {
      newB = Duration(milliseconds: (_initialB.inMilliseconds + realDeltaMs).toInt().clamp(newA.inMilliseconds + 100, widget.duration.inMilliseconds));
    } else if (_dragInfo!.type == DragType.center) {
      final segDurationMs = _initialB.inMilliseconds - _initialA.inMilliseconds;
      int proposedAMs = (_initialA.inMilliseconds + realDeltaMs).toInt();
      if (proposedAMs < 0) proposedAMs = 0;
      if (proposedAMs + segDurationMs > widget.duration.inMilliseconds) {
        proposedAMs = widget.duration.inMilliseconds - segDurationMs;
      }
      newA = Duration(milliseconds: proposedAMs);
      newB = Duration(milliseconds: proposedAMs + segDurationMs);
    }
    
    if (_dragInfo!.segmentIndex == -1) {
      widget.onLoopChanged(newA, newB);
    } else if (_dragInfo!.segmentIndex >= 0) {
      final updatedSegments = List<PlaybackSegment>.from(widget.segments);
      updatedSegments[_dragInfo!.segmentIndex] = PlaybackSegment(start: newA, end: newB);
      widget.onSegmentsChanged(updatedSegments);
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_dragInfo != null && _dragInfo!.type != DragType.seek) {
      widget.onInteractionEnd();
    }
    setState(() {
      _dragInfo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onPanStart: (d) => _handlePanStart(d, width),
          onPanUpdate: (d) => _handlePanUpdate(d, width),
          onPanEnd: _handlePanEnd,
          onPanCancel: () {
            setState(() { _dragInfo = null; });
          },
          onTapDown: (d) {
             // For simple taps that don't become a pan
             _handlePanStart(DragStartDetails(localPosition: d.localPosition, globalPosition: d.globalPosition), width);
          },
          onTapUp: (d) => _handlePanEnd(DragEndDetails()),
          child: Container(
            height: 40,
            color: Colors.transparent, // Capture gestures
            child: CustomPaint(
              size: Size(width, 40),
              painter: _ProgressBarPainter(
                duration: widget.duration,
                position: widget.position,
                isLoopMode: widget.isLoopMode,
                loopA: widget.loopA,
                loopB: widget.loopB,
                isSequenceMode: widget.isSequenceMode,
                segments: widget.segments,
                dragInfo: _dragInfo,
              ),
            ),
          ),
        );
      }
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  final Duration duration;
  final Duration position;
  final bool isLoopMode;
  final Duration? loopA;
  final Duration? loopB;
  final bool isSequenceMode;
  final List<PlaybackSegment> segments;
  final DragTargetInfo? dragInfo;

  static const List<Color> _sequenceColors = [
    Colors.deepPurpleAccent,
    Colors.orangeAccent,
    Colors.lightBlueAccent,
    Colors.pinkAccent,
    Colors.tealAccent,
  ];

  _ProgressBarPainter({
    required this.duration,
    required this.position,
    required this.isLoopMode,
    this.loopA,
    this.loopB,
    required this.isSequenceMode,
    required this.segments,
    this.dragInfo,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()
      ..color = VoxProTheme.border
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final playedPaint = Paint()
      ..color = VoxProTheme.accent.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    final thumbPaint = Paint()
      ..color = VoxProTheme.accent
      ..style = PaintingStyle.fill;

    final double trackHeight = 6.0;
    final double trackY = size.height / 2 - trackHeight / 2;
    
    // Draw Background Track
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, trackY, size.width, trackHeight), const Radius.circular(3)),
      trackPaint,
    );

    double _durToX(Duration d) {
      if (duration.inMilliseconds == 0) return 0;
      return (d.inMilliseconds / duration.inMilliseconds) * size.width;
    }

    String formatMs(Duration d) {
      final m = d.inMinutes.toString().padLeft(2, '0');
      final s = (d.inSeconds % 60).toString().padLeft(2, '0');
      final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0').substring(0, 1);
      return "$m:$s.$ms";
    }

    void drawTimeLabel(String text, double x, Color color) {
      final textSpan = TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      // Ensure text stays within canvas width
      double paintX = x - textPainter.width / 2;
      if (paintX < 0) paintX = 0;
      if (paintX + textPainter.width > size.width) paintX = size.width - textPainter.width;
      
      textPainter.paint(canvas, Offset(paintX, trackY - 18));
    }

    // Draw Loop Area
    if (isLoopMode && loopA != null && loopB != null) {
      final startX = _durToX(loopA!);
      final endX = _durToX(loopB!);
      final loopPaint = Paint()..color = Colors.greenAccent.withOpacity(0.4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(startX, trackY - 2, endX - startX, trackHeight + 4), const Radius.circular(4)),
        loopPaint,
      );
      // Draw handles
      canvas.drawRect(Rect.fromLTWH(startX - 2, trackY - 4, 4, trackHeight + 8), Paint()..color = Colors.greenAccent);
      canvas.drawRect(Rect.fromLTWH(endX - 2, trackY - 4, 4, trackHeight + 8), Paint()..color = Colors.greenAccent);
      
      if (dragInfo != null && dragInfo!.segmentIndex == -1) {
         drawTimeLabel(formatMs(loopA!), startX, Colors.greenAccent);
         drawTimeLabel(formatMs(loopB!), endX, Colors.greenAccent);
      }
    }

    // Draw Sequence Areas
    if (isSequenceMode) {
      for (int i = 0; i < segments.length; i++) {
        final seg = segments[i];
        final startX = _durToX(seg.start);
        final endX = _durToX(seg.end);
        final color = _sequenceColors[i % _sequenceColors.length];
        
        final segPaint = Paint()..color = color.withOpacity(0.4);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(startX, trackY - 2, endX - startX, trackHeight + 4), const Radius.circular(4)),
          segPaint,
        );
        // Draw handles
        canvas.drawRect(Rect.fromLTWH(startX - 2, trackY - 4, 4, trackHeight + 8), Paint()..color = color);
        canvas.drawRect(Rect.fromLTWH(endX - 2, trackY - 4, 4, trackHeight + 8), Paint()..color = color);

        if (dragInfo != null && dragInfo!.segmentIndex == i) {
           drawTimeLabel(formatMs(seg.start), startX, color);
           drawTimeLabel(formatMs(seg.end), endX, color);
        }
      }
    }

    // Draw Played Progress
    final posX = _durToX(position);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, trackY, posX, trackHeight), const Radius.circular(3)),
      playedPaint,
    );

    // Draw Thumb
    canvas.drawCircle(Offset(posX, size.height / 2), 8.0, thumbPaint);
  }

  @override
  bool shouldRepaint(covariant _ProgressBarPainter oldDelegate) {
    return oldDelegate.position != position ||
           oldDelegate.duration != duration ||
           oldDelegate.isLoopMode != isLoopMode ||
           oldDelegate.loopA != loopA ||
           oldDelegate.loopB != loopB ||
           oldDelegate.isSequenceMode != isSequenceMode ||
           oldDelegate.segments != segments ||
           oldDelegate.dragInfo != dragInfo;
  }
}
