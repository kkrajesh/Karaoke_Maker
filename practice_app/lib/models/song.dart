import 'dart:io';

class Song {
  final String title;
  final String directoryPath;
  final bool hasInstrumental;
  final bool hasVocals;
  final bool hasPitchProfile;
  final bool hasNativeLyrics;
  final bool hasEnglishLyrics;
  final bool hasVocalMap;

  Song({
    required this.title,
    required this.directoryPath,
    this.hasInstrumental = false,
    this.hasVocals = false,
    this.hasPitchProfile = false,
    this.hasNativeLyrics = false,
    this.hasEnglishLyrics = false,
    this.hasVocalMap = false,
  });

  factory Song.fromDirectory(Directory dir) {
    final title = dir.path.split(Platform.pathSeparator).last.replaceAll('_', ' ');
    final files = dir.listSync().map((e) => e.path.split(Platform.pathSeparator).last).toList();

    return Song(
      title: title,
      directoryPath: dir.path,
      hasInstrumental: files.contains('instrumental.wav'),
      hasVocals: files.contains('vocals.wav'),
      hasPitchProfile: files.contains('pitch_profile.json'),
      hasNativeLyrics: files.contains('lyrics_native.lrc') || files.contains('lyrics_native.txt'),
      hasEnglishLyrics: files.contains('lyrics_english.lrc') || files.contains('lyrics_english.txt'),
      hasVocalMap: files.contains('vocal_map.json'),
    );
  }
}
