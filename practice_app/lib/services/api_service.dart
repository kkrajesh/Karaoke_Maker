import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:5000';

  static Future<List<dynamic>> search(String query) async {
    final response = await http.get(Uri.parse('$baseUrl/search?q=${Uri.encodeComponent(query)}'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['results'] ?? [];
    } else {
      throw Exception('Failed to load search results: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> fetchLyrics(String query) async {
    final response = await http.get(Uri.parse('$baseUrl/lyrics?q=${Uri.encodeComponent(query)}'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['lyrics'] ?? {"text": "", "type": "txt", "source": "None"};
    } else {
      throw Exception('Failed to load lyrics: ${response.body}');
    }
  }

  static Future<String> processSong({
    required String songId,
    String? url,
    String? localAudioPath,
    String? lyricsText,
    String? lyricsType,
  }) async {
    final body = {
      'song_id': songId,
      if (url != null) 'url': url,
      if (localAudioPath != null) 'local_audio_path': localAudioPath,
      if (lyricsText != null) 'lyrics_text': lyricsText,
      if (lyricsType != null) 'lyrics_type': lyricsType,
    };

    final response = await http.post(
      Uri.parse('$baseUrl/process'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['task_id'];
    } else {
      throw Exception('Failed to start processing: ${response.body}');
    }
  }

  static Future<String> reprocessComponent({
    required String songId,
    required String component,
    String? lyricsText,
    String? lyricsType,
  }) async {
    final body = {
      'song_id': songId,
      'component': component,
      if (lyricsText != null) 'lyrics_text': lyricsText,
      if (lyricsType != null) 'lyrics_type': lyricsType,
    };

    final response = await http.post(
      Uri.parse('$baseUrl/reprocess'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['task_id'];
    } else {
      throw Exception('Failed to start reprocessing: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getStatus(String taskId) async {
    final response = await http.get(Uri.parse('$baseUrl/status/$taskId'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get status: ${response.body}');
    }
  }
}
