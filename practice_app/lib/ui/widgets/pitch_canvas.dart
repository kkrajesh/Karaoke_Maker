import 'package:flutter/material.dart';
import '../theme/voxpro_theme.dart';
import '../../services/lyrics_parser.dart';
import 'dart:math';

class PitchCanvas extends StatelessWidget {
  final Duration currentPosition;
  final List<dynamic> targetPitchData;
  final List<dynamic>? vocalMapData;
  final List<Map<String, dynamic>>? userPitchData;
  final String rootNote;
  final Color? targetPitchColor;
  final Color? userPitchColor;

  const PitchCanvas({
    Key? key,
    required this.currentPosition,
    required this.targetPitchData,
    this.vocalMapData,
    this.userPitchData,
    this.rootNote = 'C',
    this.targetPitchColor,
    this.userPitchColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: CustomPaint(
        painter: _PitchPainter(
          currentPosition: currentPosition,
          targetPitchData: targetPitchData,
          vocalMapData: vocalMapData,
          userPitchData: userPitchData,
          rootNote: rootNote,
          targetPitchColor: targetPitchColor ?? VoxProTheme.vocalAccent,
          userPitchColor: userPitchColor ?? const Color(0xFF00FFFF),
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
  final List<Map<String, dynamic>>? userPitchData;
  final String rootNote;
  final Color targetPitchColor;
  final Color userPitchColor;

  static const double visibleSeconds = 4.0;
  static const double minMidi = 43.0; // G2
  static const double maxMidi = 81.0; // A5

  _PitchPainter({
    required this.currentPosition,
    required this.targetPitchData,
    this.vocalMapData,
    this.userPitchData,
    this.rootNote = 'C',
    required this.targetPitchColor,
    required this.userPitchColor,
  });

  int _noteNameToOffset(String note) {
    const notes = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    return notes.indexOf(note) != -1 ? notes.indexOf(note) : 0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final currentTime = currentPosition.inMilliseconds / 1000.0;
    final playheadX = size.width * 0.2;

    // --- Draw Grid and Sargam Lines ---
    final int rootOffset = _noteNameToOffset(rootNote);
    final int middleSa = ((60 - rootOffset) / 12).round() * 12 + rootOffset;
    
    const sargamMap = {
      0: 'Sa', 1: 'r', 2: 'Re', 3: 'g', 4: 'Ga', 5: 'Ma',
      6: 'm', 7: 'Pa', 8: 'd', 9: 'Dha', 10: 'n', 11: 'Ni'
    };

    double freqToMidi(double freq) {
      if (freq <= 0) return 0;
      return 69 + 12 * (log(freq / 440) / ln2);
    }

    double midiToY(double m) {
      double clampM = m.clamp(minMidi, maxMidi);
      double normalized = (clampM - minMidi) / (maxMidi - minMidi);
      return size.height - (normalized * size.height);
    }

    // Draw horizontal lines for semitones
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    
    for (int m = minMidi.floor(); m <= maxMidi.ceil(); m++) {
      double y = midiToY(m.toDouble());
      int relativePitch = (m - rootOffset) % 12;
      if (relativePitch < 0) relativePitch += 12;
      
      bool isSa = relativePitch == 0;
      
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = isSa ? VoxProTheme.border : VoxProTheme.border.withOpacity(0.3)
          ..strokeWidth = isSa ? 1.5 : 0.5,
      );

      // Draw Sargam Label
      String label = sargamMap[relativePitch] ?? '';
      int octDiff = ((m - middleSa) / 12).floor();
      if (octDiff < 0) label += '\u0323'; // Dot below
      else if (octDiff > 0) label += '\u0307'; // Dot above

      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          color: isSa ? VoxProTheme.accent : VoxProTheme.textSecondary.withOpacity(0.7),
          fontSize: isSa ? 14 : 10,
          fontWeight: isSa ? FontWeight.bold : FontWeight.normal,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(8, y - textPainter.height / 2));
    }

    // Draw playhead
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      Paint()..color = VoxProTheme.accent.withOpacity(0.5)..strokeWidth = 2,
    );

    double timeToX(double t) {
      final timeDiff = t - currentTime;
      final pixelsPerSecond = size.width / visibleSeconds;
      return playheadX + (timeDiff * pixelsPerSecond);
    }

    bool isVocalSection(double t) {
      if (vocalMapData == null || vocalMapData!.isEmpty) return true;
      for (final segment in vocalMapData!) {
        final start = (segment['start'] as num).toDouble();
        final end = (segment['end'] as num).toDouble();
        if (t >= start && t <= end) return true;
      }
      return false;
    }

    // Draw Pitch Curve
    final targetPaint = Paint()
      ..color = VoxProTheme.textSecondary.withOpacity(0.5)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.fill;

    if (targetPitchData.isNotEmpty) {
      for (int i = 0; i < targetPitchData.length - 1; i++) {
        final p1 = targetPitchData[i];
        final p2 = targetPitchData[i + 1];

        final t1 = (p1['t'] as num).toDouble();
        final t2 = (p2['t'] as num).toDouble();
        
        // Skip drawing if outside visible window
        if (t2 < currentTime - 1 || t1 > currentTime + visibleSeconds) continue;

        final f1 = (p1['p'] as num).toDouble();
        final f2 = (p2['p'] as num).toDouble();
        
        final m1 = freqToMidi(f1);
        final m2 = freqToMidi(f2);

        final x1 = timeToX(t1);
        final y1 = midiToY(m1);
        final x2 = timeToX(t2);
        final y2 = midiToY(m2);

        // Gap in data (unvoiced or separate notes)
        if (t2 - t1 > 0.1) {
          canvas.drawCircle(Offset(x1, y1), 2, targetPaint);
          continue;
        }

        final activeColor = isVocalSection(t1) 
            ? targetPitchColor 
            : VoxProTheme.textSecondary.withOpacity(0.5);
            
        final linePaint = Paint()
          ..color = activeColor
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round;

        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), linePaint);
      }
    }

    // Draw User Pitch Data
    if (userPitchData != null && userPitchData!.isNotEmpty) {
      final userLinePaint = Paint()
        ..color = userPitchColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
        
      for (int i = 0; i < userPitchData!.length - 1; i++) {
        final p1 = userPitchData![i];
        final p2 = userPitchData![i + 1];

        final t1 = p1['time'] as double;
        final t2 = p2['time'] as double;
        
        // Skip drawing if outside visible window
        if (t2 < currentTime - 2 || t1 > currentTime + visibleSeconds) continue;

        final f1 = p1['pitch'] as double;
        final f2 = p2['pitch'] as double;

        final m1 = freqToMidi(f1);
        final m2 = freqToMidi(f2);

        final x1 = timeToX(t1);
        final y1 = midiToY(m1);
        final x2 = timeToX(t2);
        final y2 = midiToY(m2);

        // Gap in data (unvoiced or separate notes)
        if (t2 - t1 > 0.15) {
          canvas.drawCircle(Offset(x1, y1), 1.5, Paint()..color = userPitchColor);
          continue;
        }

        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), userLinePaint);
      }
      
      // Draw the last point as a dot if it's the very end and standalone
      if (userPitchData!.length > 0) {
          final lastP = userPitchData!.last;
          final t = lastP['time'] as double;
          if (t >= currentTime - 2 && t <= currentTime + visibleSeconds) {
             final f = lastP['pitch'] as double;
             canvas.drawCircle(Offset(timeToX(t), midiToY(freqToMidi(f))), 1.5, Paint()..color = userPitchColor);
          }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PitchPainter oldDelegate) {
    return oldDelegate.currentPosition != currentPosition || 
           oldDelegate.targetPitchData != targetPitchData ||
           oldDelegate.userPitchData != userPitchData ||
           oldDelegate.targetPitchColor != targetPitchColor ||
           oldDelegate.userPitchColor != userPitchColor ||
           oldDelegate.vocalMapData != vocalMapData ||
           oldDelegate.rootNote != rootNote;
  }
}
