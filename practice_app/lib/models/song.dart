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
  final String? mmId; // MediaMonkey ID
  bool isMissing; // Added to track missing folders
  bool hasPerformanceProfile; // Tracks if sequences have been saved
  final DateTime? dateModified; // Tracks when AI artifacts were updated

  String get id => mmId ?? directoryPath.split(Platform.pathSeparator).last;

  Song({
    required this.title,
    required this.directoryPath,
    this.hasInstrumental = false,
    this.hasVocals = false,
    this.hasPitchProfile = false,
    this.hasNativeLyrics = false,
    this.hasEnglishLyrics = false,
    this.hasVocalMap = false,
    this.mmId,
    this.isMissing = false,
    this.hasPerformanceProfile = false,
    this.dateModified,
  });

  factory Song.fromDirectory(Directory dir) {
    final title = dir.path.split(Platform.pathSeparator).last.replaceAll('_', ' ');
    final files = dir.listSync().map((e) => e.path.split(Platform.pathSeparator).last).toList();

    return Song(
      title: title,
      directoryPath: dir.path,
      hasInstrumental: files.any((f) => f.contains('instrumental.wav')),
      hasVocals: files.any((f) => f.contains('vocals.wav')),
      hasPitchProfile: files.any((f) => f.contains('pitch_profile.json')),
      hasNativeLyrics: files.any((f) => f.contains('lyrics_native.lrc') || f.contains('lyrics_native.txt')),
      hasEnglishLyrics: files.any((f) => f.contains('lyrics_english.lrc') || f.contains('lyrics_english.txt')),
      hasVocalMap: files.any((f) => f.contains('vocal_map.json')),
    );
  }

  factory Song.fromAiArtifact(Map<String, dynamic> row, String aiVaultPath) {
    final String mmId = row['mm_id']?.toString() ?? '';
    final String title = row['title']?.toString() ?? 'Unknown Title';
    
    DateTime? lastProcessed;
    if (row['last_processed'] != null) {
      lastProcessed = DateTime.tryParse(row['last_processed'] as String);
    }
    
    // In the new system, we just map everything logically.
    return Song(
      title: title,
      directoryPath: aiVaultPath, // Just a placeholder, as the actual paths will be derived using mmId and title
      mmId: mmId,
      hasInstrumental: row['has_instrumental'] == 1,
      hasVocals: row['has_vocals'] == 1,
      hasPitchProfile: row['has_pitch_data'] == 1,
      hasNativeLyrics: row['has_lyrics'] == 1,
      hasEnglishLyrics: false, // For now, track single lyrics
      hasVocalMap: row['has_vocal_map'] == 1,
      dateModified: lastProcessed,
    );
  }
}
