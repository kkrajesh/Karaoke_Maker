import 'dart:convert';
import 'package:http/http.dart' as http;

class SongMetadata {
  final String title;
  final String album;
  final String year;
  final String artist;

  SongMetadata({
    required this.title,
    required this.album,
    required this.year,
    required this.artist,
  });
}

class MetadataService {
  
  static Future<SongMetadata?> searchMetadata(String rawTitle) async {
    try {
      final url = Uri.parse('http://127.0.0.1:5000/standardize-title?q=${Uri.encodeComponent(rawTitle)}');
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data.isNotEmpty && data['title'] != null) {
          return SongMetadata(
            title: data['title'] ?? '',
            album: data['album'] ?? '',
            year: data['year'] ?? '',
            artist: data['artist'] ?? '',
          );
        }
      }
    } catch (e) {
      // Return null on failure so the rename UI gracefully fails
      print('Failed to contact standardize-title endpoint: $e');
    }
    return null;
  }
}
