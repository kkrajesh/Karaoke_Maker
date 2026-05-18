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

class SongLyrics {
  final LyricsData? nativeData;
  final LyricsData? englishData;
  final String? meaningText;

  SongLyrics({this.nativeData, this.englishData, this.meaningText});
  
  bool get hasAnyLyrics => nativeData != null || englishData != null;
}

class LyricsParser {
  static Future<SongLyrics> parse(String directoryPath) async {
    LyricsData? nativeData;
    LyricsData? englishData;
    String? meaningText;

    // Load Native
    File nativeLrc = File("$directoryPath${Platform.pathSeparator}lyrics_native.lrc");
    if (await nativeLrc.exists()) {
      nativeData = _parseLrc(await nativeLrc.readAsString());
    } else {
      File nativeTxt = File("$directoryPath${Platform.pathSeparator}lyrics_native.txt");
      if (await nativeTxt.exists()) {
        nativeData = _parseUnsynced(await nativeTxt.readAsString());
      }
    }

    // Load English
    File englishLrc = File("$directoryPath${Platform.pathSeparator}lyrics_english.lrc");
    if (await englishLrc.exists()) {
      englishData = _parseLrc(await englishLrc.readAsString());
    } else {
      File englishTxt = File("$directoryPath${Platform.pathSeparator}lyrics_english.txt");
      if (await englishTxt.exists()) {
        englishData = _parseUnsynced(await englishTxt.readAsString());
      }
    }

    // Load Meaning
    File meaningTxt = File("$directoryPath${Platform.pathSeparator}lyrics_meaning.txt");
    if (await meaningTxt.exists()) {
      meaningText = await meaningTxt.readAsString();
    }

    return SongLyrics(nativeData: nativeData, englishData: englishData, meaningText: meaningText);
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
