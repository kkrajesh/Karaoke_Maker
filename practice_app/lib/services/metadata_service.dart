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
    String cleanTitle = _cleanTitleForSearch(rawTitle);
    
    // 1. Try iTunes Search API
    SongMetadata? itunesData = await _searchItunes(cleanTitle);
    if (itunesData != null) {
      return itunesData;
    }
    
    // 2. Try JioSaavn Search API as fallback
    SongMetadata? jiosaavnData = await _searchJioSaavn(cleanTitle);
    if (jiosaavnData != null) {
      return jiosaavnData;
    }
    
    return null;
  }

  static String _cleanTitleForSearch(String raw) {
    String clean = raw.replaceAll('_', ' ');
    // Remove complex junk
    clean = clean.replaceAll(RegExp(r'Full.*?Audio', caseSensitive: false), ' ');
    clean = clean.replaceAll(RegExp(r'High\s*def.*', caseSensitive: false), ' ');
    clean = clean.replaceAll(RegExp(r'with.*?Audio', caseSensitive: false), ' ');
    clean = clean.replaceAll(RegExp(r'\b(HD|4K|1080p|720p|Official Video|Lyrical Video|Karaoke|गाने के बोल|Lyrical|Lyrics|Audio Song|Video Song|Music Video)\b', caseSensitive: false), ' ');
    clean = clean.replaceAll(RegExp(r'\bSong\b', caseSensitive: false), ' ');
    clean = clean.replaceAll(RegExp(r'\b(Malayalam|Tamil|Hindi|Telugu|Kannada|Film|Movie|Actor|Actress|Unknown)\b', caseSensitive: false), ' ');
    clean = clean.replaceAll(RegExp(r'\b\d{10,}\b'), ' '); // Remove long timestamp numbers

    final parts = clean.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.length > 1) {
      // Just take the first part (English title) and maybe the album if present
      String query = parts[0].replaceAll(RegExp(r'\s+'), ' ').trim();
      final indianScriptReg = RegExp(r'[\u0900-\u0D7F]');
      // If part 1 is native script, skip it
      int nextIdx = 1;
      if (parts.length > 2 && indianScriptReg.hasMatch(parts[1]) && !indianScriptReg.hasMatch(parts[0])) {
        nextIdx = 2;
      } else {
        final dashParts = query.split('-');
        if (dashParts.length > 1 && indianScriptReg.hasMatch(dashParts[1])) {
           query = dashParts[0].trim();
        }
      }
      
      // If we have album or artist, append it to narrow down search
      if (parts.length > nextIdx) {
        query += ' ' + parts[nextIdx];
      }
      return query;
    } else {
      final dashParts = clean.split('-');
      if (dashParts.length > 1) {
        return dashParts[1].trim() + ' ' + dashParts[0].trim();
      }
      return clean.replaceAll(RegExp(r'\[.*?\]'), ' ').replaceAll(RegExp(r'\(.*?\)'), ' ').trim();
    }
  }

  static Future<SongMetadata?> _searchItunes(String query) async {
    try {
      final url = Uri.parse('https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&entity=song&limit=5');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['resultCount'] > 0) {
          
          // Try to find a track that isn't a compilation/mix/hits album
          var bestTrack = data['results'][0];
          for (var track in data['results']) {
             String tempAlbum = (track['collectionName'] ?? '').toString().toLowerCase();
             if (!tempAlbum.contains('mix') && !tempAlbum.contains('best of') && !tempAlbum.contains('hits') && !tempAlbum.contains('essential')) {
                bestTrack = track;
                break;
             }
          }
          
          final track = bestTrack;
          String title = track['trackName'] ?? '';
          String album = track['collectionName'] ?? '';
          String artist = track['artistName'] ?? '';
          String year = '';
          if (track['releaseDate'] != null) {
            year = track['releaseDate'].toString().substring(0, 4);
          }
          
          title = _cleanApiResult(title);
          album = _cleanApiResult(album);
          
          // If album is exactly the title + " - Single", clear it out so heuristics can try to find it, or just use it.
          // Wait, if it says "Sooseki (From "Pushpa 2 the Rule") - TELUGU - Single" -> we want to extract Pushpa 2
          
          if (title.contains('(From') || title.contains('( From')) {
             final match = RegExp(r'\(\s*[Ff]rom\s*["\u0027]?(.*?)["\u0027]?\s*\)').firstMatch(title);
             if (match != null && match.group(1) != null) {
                album = match.group(1)!;
             }
             title = title.split(RegExp(r'\(\s*[Ff]rom'))[0].trim();
          }
          
          title = title.replaceAll(RegExp(r'\([^)]*\)'), '').replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();
          title = title.replaceAll(RegExp(r'\s+'), ' ');
          
          if (!_isValidMatch(query, title)) return null;
          
          return SongMetadata(title: title, album: album, year: year, artist: artist);
        }
      }
    } catch (e) {
      // Ignore network errors and return null
    }
    return null;
  }

  static Future<SongMetadata?> _searchJioSaavn(String query) async {
    try {
      final url = Uri.parse('https://www.jiosaavn.com/api.php?__call=autocomplete.get&query=${Uri.encodeComponent(query)}&_format=json&_marker=0&ctx=android');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['songs'] != null && data['songs']['data'] != null) {
          final List songs = data['songs']['data'];
          if (songs.isNotEmpty) {
            var bestTrack = songs[0];
            for (var track in songs) {
               String tempAlbum = (track['album'] ?? '').toString().toLowerCase();
               if (!tempAlbum.contains('mix') && !tempAlbum.contains('best of') && !tempAlbum.contains('hits') && !tempAlbum.contains('essential')) {
                  bestTrack = track;
                  break;
               }
            }
            final track = bestTrack;
            
            String title = track['title'] ?? '';
            String album = track['album'] ?? '';
            String artist = '';
            
            if (track['more_info'] != null && track['more_info']['primary_artists'] != null) {
              artist = track['more_info']['primary_artists'];
            } else if (track['description'] != null) {
               artist = track['description'].toString().split('·').last.trim();
            }
            
            // Clean up html entities
            title = title.replaceAll('&quot;', '"');
            album = album.replaceAll('&quot;', '"');
            artist = artist.replaceAll('&quot;', '"');
            
            title = _cleanApiResult(title);
            album = _cleanApiResult(album);
            
            if (title.contains('(From') || title.contains('( From')) {
               final match = RegExp(r'\(\s*[Ff]rom\s*["\u0027]?(.*?)["\u0027]?\s*\)').firstMatch(title);
               if (match != null && match.group(1) != null) {
                  album = match.group(1)!;
               }
               title = title.split(RegExp(r'\(\s*[Ff]rom'))[0].trim();
            }
            
            title = title.replaceAll(RegExp(r'\([^)]*\)'), '').replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();
            title = title.replaceAll(RegExp(r'\s+'), ' ');
            
            if (!_isValidMatch(query, title)) return null;
            
            return SongMetadata(title: title, album: album, year: '', artist: artist);
          }
        }
      }
    } catch (e) {
      // Ignore network errors and return null
    }
    return null;
  }

  static String _cleanApiResult(String text) {
    String clean = text;
    clean = clean.replaceAll(RegExp(r'\s*-\s*Single', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'\s*-\s*EP', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'\s*-\s*TELUGU', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'\s*-\s*TAMIL', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'\s*-\s*HINDI', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'\s*-\s*MALAYALAM', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'\(\s*Original Motion Picture Soundtrack\s*\)', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'Original Motion Picture Soundtrack', caseSensitive: false), '');
    return clean.trim();
  }

  static bool _isValidMatch(String query, String resultTitle) {
    final qWords = query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').split(' ').where((w) => w.length > 2).toList();
    final rWords = resultTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').split(' ').where((w) => w.length > 2).toList();
    
    if (qWords.isEmpty || rWords.isEmpty) return true; // Cannot reliably check
    
    int matches = 0;
    for (var qw in qWords) {
      if (rWords.contains(qw)) matches++;
    }
    
    if (qWords.length <= 2) {
      return matches == qWords.length;
    } else {
      return (matches / qWords.length) >= 0.6;
    }
  }
}
