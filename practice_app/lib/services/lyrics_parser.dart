import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class LyricLine {
  final Duration startTime;
  final String text;

  LyricLine({required this.startTime, required this.text});
}

class LyricsData {
  final List<LyricLine> lines;
  final bool isSynced;

  LyricsData({required this.lines, required this.isSynced});
}

class LyricsParser {
  static Future<LyricsData?> parse(String directoryPath) async {
    final nativePath = "\$directoryPath\${Platform.pathSeparator}lyrics_native.lrc";
    final englishPath = "\$directoryPath\${Platform.pathSeparator}lyrics_english.lrc";
    
    File file = File(nativePath);
    if (!await file.exists()) {
      file = File(englishPath);
    }
    
    if (!await file.exists()) {
      // Try txt files as fallback
      final txtNative = File("\$directoryPath\${Platform.pathSeparator}lyrics_native.txt");
      if (await txtNative.exists()) {
        final content = await txtNative.readAsString();
        return _parseUnsynced(content);
      }
      return null;
    }

    final content = await file.readAsString();
    return _parseLrc(content);
  }

  static LyricsData _parseLrc(String content) {
    final List<LyricLine> lines = [];
    final RegExp timePattern = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');

    for (final line in LineSplitter.split(content)) {
      final match = timePattern.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final milliseconds = int.parse(match.group(3)!) * (match.group(3)!.length == 2 ? 10 : 1);
        
        final time = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );
        
        final text = line.substring(match.end).trim();
        if (text.isNotEmpty) {
          lines.add(LyricLine(startTime: time, text: text));
        }
      }
    }

    // Sort by time just in case
    lines.sort((a, b) => a.startTime.compareTo(b.startTime));
    return LyricsData(lines: lines, isSynced: true);
  }

  static LyricsData _parseUnsynced(String content) {
    final List<LyricLine> lines = [];
    for (final line in LineSplitter.split(content)) {
      if (line.trim().isNotEmpty) {
        lines.add(LyricLine(startTime: Duration.zero, text: line.trim()));
      }
    }
    return LyricsData(lines: lines, isSynced: false);
  }
}
