import 'package:flutter/material.dart';
import '../theme/voxpro_theme.dart';
import '../../services/lyrics_parser.dart';

class PitchCanvas extends StatelessWidget {
  final Duration currentPosition;
  final List<dynamic> targetPitchData;
  final List<dynamic>? vocalMapData;

  const PitchCanvas({
    Key? key,
    required this.currentPosition,
    required this.targetPitchData,
    this.vocalMapData,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: CustomPaint(
        painter: _PitchPainter(
          currentPosition: currentPosition,
          targetPitchData: targetPitchData,
          vocalMapData: vocalMapData,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _PitchPainter extends CustomPainter {
  final Duration currentPosition;
  final List<dynamic> targetPitchData;
  final List<dynamic>? vocalMapData;

  // Viewport configuration
  static const double visibleSeconds = 4.0; // Show 4 seconds of time on screen
  static const double minFreq = 100.0; // roughly G2
  static const double maxFreq = 1000.0; // roughly B5

  _PitchPainter({
    required this.currentPosition,
    required this.targetPitchData,
    this.vocalMapData,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final currentTime = currentPosition.inMilliseconds / 1000.0;
    
    // Draw background grid (optional, let's keep it clean for now)
    final gridPaint = Paint()
      ..color = VoxProTheme.border
      ..strokeWidth = 1;
    
    // Draw target pitch line
    final targetPaint = Paint()
      ..color = VoxProTheme.textSecondary.withOpacity(0.5)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.fill;

    // Draw active playhead (center of screen or 1/3rd of screen)
    final playheadX = size.width * 0.2; // 20% from left
    
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      Paint()
        ..color = VoxProTheme.accent.withOpacity(0.5)
        ..strokeWidth = 2,
    );

    // Map time to X coordinate
    double timeToX(double t) {
      // t is relative to current time
      final timeDiff = t - currentTime;
      // Map timeDiff to pixels. 0 timeDiff is at playheadX.
      // visibleSeconds is mapped to size.width
      final pixelsPerSecond = size.width / visibleSeconds;
      return playheadX + (timeDiff * pixelsPerSecond);
    }

    // Map frequency to Y coordinate (logarithmic mapping is better, but linear is ok for MVP)
    double freqToY(double p) {
      if (p < minFreq) p = minFreq;
      if (p > maxFreq) p = maxFreq;
      final range = maxFreq - minFreq;
      final normalized = (p - minFreq) / range;
      // Invert Y axis (0 is top, height is bottom)
      return size.height - (normalized * size.height);
    }

    // Helper to determine if time 't' is within an active vocal segment
    bool isVocalSection(double t) {
      if (vocalMapData == null || vocalMapData!.isEmpty) return true; // Default to vocal if no map
      
      for (final segment in vocalMapData!) {
        final start = (segment['start'] as num).toDouble();
        final end = (segment['end'] as num).toDouble();
        if (t >= start && t <= end) {
          return true;
        }
      }
      return false;
    }

    for (int i = 0; i < targetPitchData.length; i++) {
      final point = targetPitchData[i];
      final t = (point['t'] as num).toDouble();
      final p = (point['p'] as num).toDouble();

      // Only draw if within visible window
      if (t >= currentTime - visibleSeconds && t <= currentTime + visibleSeconds) {
        final x = timeToX(t);
        final y = freqToY(p);
        
        // Color dots based on vocal map
        final isVocal = isVocalSection(t);
        final baseColor = isVocal ? VoxProTheme.vocalAccent : VoxProTheme.accent;
        
        final color = (t <= currentTime) ? baseColor : VoxProTheme.textSecondary;
        targetPaint.color = color;

        canvas.drawCircle(Offset(x, y), 3, targetPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PitchPainter oldDelegate) {
    return oldDelegate.currentPosition != currentPosition || 
           oldDelegate.targetPitchData != targetPitchData ||
           oldDelegate.vocalMapData != vocalMapData;
  }
}
