import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class PlaybackSegment {
  Duration start;
  Duration end;

  PlaybackSegment({required this.start, required this.end});

  factory PlaybackSegment.fromJson(Map<String, dynamic> json) {
    return PlaybackSegment(
      start: Duration(milliseconds: json['start_ms'] ?? 0),
      end: Duration(milliseconds: json['end_ms'] ?? 0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'start_ms': start.inMilliseconds,
      'end_ms': end.inMilliseconds,
    };
  }
}

class NamedSequence {
  String name;
  List<PlaybackSegment> segments;

  NamedSequence({required this.name, required this.segments});

  factory NamedSequence.fromJson(Map<String, dynamic> json) {
    return NamedSequence(
      name: json['name'] ?? 'Untitled',
      segments: (json['segments'] as List?)?.map((e) => PlaybackSegment.fromJson(e)).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'segments': segments.map((e) => e.toJson()).toList(),
    };
  }
}

class PerformanceProfile {
  PlaybackSegment? lastAbLoop;
  List<NamedSequence> sequences;

  PerformanceProfile({this.lastAbLoop, List<NamedSequence>? sequences})
      : sequences = sequences ?? [];

  factory PerformanceProfile.fromJson(Map<String, dynamic> json) {
    return PerformanceProfile(
      lastAbLoop: json['last_ab_loop'] != null ? PlaybackSegment.fromJson(json['last_ab_loop']) : null,
      sequences: (json['sequences'] as List?)?.map((e) => NamedSequence.fromJson(e)).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'last_ab_loop': lastAbLoop?.toJson(),
      'sequences': sequences.map((e) => e.toJson()).toList(),
    };
  }
}

class PerformanceProfileService {
  static Future<PerformanceProfile> loadProfile(String directoryPath) async {
    final file = File('$directoryPath${Platform.pathSeparator}performance_profiles.json');
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final json = jsonDecode(content);
        return PerformanceProfile.fromJson(json);
      } catch (e) {
        debugPrint('Error loading performance profile: $e');
      }
    }
    return PerformanceProfile();
  }

  static Future<void> saveProfile(String directoryPath, PerformanceProfile profile) async {
    final file = File('$directoryPath${Platform.pathSeparator}performance_profiles.json');
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(profile.toJson()));
  }
}
