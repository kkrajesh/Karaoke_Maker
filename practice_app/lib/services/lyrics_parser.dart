import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class LyricLine {
  Duration startTime;
  final String text;
  String? singerPart;

  LyricLine({required this.startTime, required this.text, this.singerPart});
}

class LyricsData {
  final List<LyricLine> lines;
  bool isSynced;

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

    final dir = Directory(directoryPath);
    if (!await dir.exists()) return SongLyrics();

    List<File> files = [];
    await for (final entity in dir.list()) {
      if (entity is File) files.add(entity);
    }

    // Load Native
    File? nativeFile = files.where((f) => f.path.contains('lyrics_native') || f.path.endsWith('.lrc') && !f.path.contains('english')).firstOrNull;
    if (nativeFile != null) {
      if (nativeFile.path.endsWith('.lrc')) {
        nativeData = _parseLrc(await nativeFile.readAsString());
      } else {
        nativeData = _parseUnsynced(await nativeFile.readAsString());
      }
    }

    // Load English
    File? englishFile = files.where((f) => f.path.contains('lyrics_english')).firstOrNull;
    if (englishFile != null) {
      if (englishFile.path.endsWith('.lrc')) {
        englishData = _parseLrc(await englishFile.readAsString());
      } else {
        englishData = _parseUnsynced(await englishFile.readAsString());
      }
    }

    // Load Meaning
    File? meaningFile = files.where((f) => f.path.contains('lyrics_meaning.txt')).firstOrNull;
    if (meaningFile != null) {
      meaningText = await meaningFile.readAsString();
    }

    // Cross-pollinate sync and singer data if line counts match
    if (nativeData != null && englishData != null && nativeData.lines.length == englishData.lines.length) {
      bool anySynced = nativeData.isSynced || englishData.isSynced;
      for (int i = 0; i < nativeData.lines.length; i++) {
        final nLine = nativeData.lines[i];
        final eLine = englishData.lines[i];

        // Sync timing
        if (nLine.startTime > Duration.zero && eLine.startTime == Duration.zero) {
          eLine.startTime = nLine.startTime;
        } else if (eLine.startTime > Duration.zero && nLine.startTime == Duration.zero) {
          nLine.startTime = eLine.startTime;
        }

        // Sync singer part
        if (nLine.singerPart != null && eLine.singerPart == null) {
          eLine.singerPart = nLine.singerPart;
        } else if (eLine.singerPart != null && nLine.singerPart == null) {
          nLine.singerPart = eLine.singerPart;
        }
      }

      if (anySynced) {
        nativeData.isSynced = true;
        englishData.isSynced = true;
      }
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
          String? singerPart;
          String cleanText = text;
          if (cleanText.startsWith('[1]')) { singerPart = '1'; cleanText = cleanText.substring(3).trim(); }
          else if (cleanText.startsWith('[2]')) { singerPart = '2'; cleanText = cleanText.substring(3).trim(); }
          else if (cleanText.startsWith('[3]')) { singerPart = '3'; cleanText = cleanText.substring(3).trim(); }
          else if (cleanText.startsWith('[B]')) { singerPart = 'B'; cleanText = cleanText.substring(3).trim(); }
          
          lines.add(LyricLine(startTime: time, text: cleanText, singerPart: singerPart));
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
          String? singerPart;
          String cleanText = line.trim();
          if (cleanText.startsWith('[1]')) { singerPart = '1'; cleanText = cleanText.substring(3).trim(); }
          else if (cleanText.startsWith('[2]')) { singerPart = '2'; cleanText = cleanText.substring(3).trim(); }
          else if (cleanText.startsWith('[3]')) { singerPart = '3'; cleanText = cleanText.substring(3).trim(); }
          else if (cleanText.startsWith('[B]')) { singerPart = 'B'; cleanText = cleanText.substring(3).trim(); }
          
          lines.add(LyricLine(startTime: Duration.zero, text: cleanText, singerPart: singerPart));
      }
    }
    return LyricsData(lines: lines, isSynced: false);
  }

  static Future<void> saveLrc(String directoryPath, String language, LyricsData data) async {
    final File file = File("$directoryPath${Platform.pathSeparator}lyrics_$language.lrc");
    final StringBuffer sb = StringBuffer();
    
    for (final line in data.lines) {
      final minutes = line.startTime.inMinutes.toString().padLeft(2, '0');
      final seconds = (line.startTime.inSeconds % 60).toString().padLeft(2, '0');
      final millis = (line.startTime.inMilliseconds % 1000 ~/ 10).toString().padLeft(2, '0');
      
      String prefix = "";
      if (line.singerPart != null) {
        prefix = "[${line.singerPart}] ";
      }
      
      sb.writeln("[$minutes:$seconds.$millis]$prefix${line.text}");
    }
    
    await file.writeAsString(sb.toString());
  }
}
