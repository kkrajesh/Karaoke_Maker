import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/file_explorer_service.dart';
import '../theme/voxpro_theme.dart';
import '../../models/song.dart';
import '../../services/metadata_service.dart';

class BatchRenameScreen extends StatefulWidget {
  const BatchRenameScreen({Key? key}) : super(key: key);

  @override
  State<BatchRenameScreen> createState() => _BatchRenameScreenState();
}

class _SongEditRow {
  final Song originalSong;
  final TextEditingController titleCtrl;
  final TextEditingController albumCtrl;
  final TextEditingController yearCtrl;
  final TextEditingController artistCtrl;
  bool isModified = false;
  bool isSelected = true;

  _SongEditRow(this.originalSong, String title, String album, String year, String artist)
      : titleCtrl = TextEditingController(text: title),
        albumCtrl = TextEditingController(text: album),
        yearCtrl = TextEditingController(text: year),
        artistCtrl = TextEditingController(text: artist);

  String get newTitle => '${titleCtrl.text.trim()} | ${albumCtrl.text.trim()} | ${yearCtrl.text.trim()} | ${artistCtrl.text.trim()}';
}

class _BatchRenameScreenState extends State<BatchRenameScreen> {
  final List<_SongEditRow> _rows = [];
  bool _isSaving = false;

  bool _isExtracting = false;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  void _loadSongs() {
    final service = Provider.of<FileExplorerService>(context, listen: false);
    _rows.clear();
    for (final song in service.songs) {
      if (song.isMissing) continue;
      
      final parts = song.title.split('|').map((e) => e.trim()).toList();
      
      String title = song.title;
      String album = '';
      String year = '';
      String artist = '';

      if (parts.length >= 4 && RegExp(r'^\d{4}$').hasMatch(parts[2].trim())) {
        title = parts[0];
        album = parts[1];
        year = parts[2];
        artist = parts[3];
      }

      final row = _SongEditRow(song, title, album, year, artist);
      row.titleCtrl.addListener(() => _checkModified(row));
      row.albumCtrl.addListener(() => _checkModified(row));
      row.yearCtrl.addListener(() => _checkModified(row));
      row.artistCtrl.addListener(() => _checkModified(row));
      _rows.add(row);
    }
  }

  void _checkModified(_SongEditRow row) {
    setState(() {
      row.isModified = row.newTitle != row.originalSong.title;
    });
  }

  Future<void> _smartExtract() async {
    setState(() {
      _isExtracting = true;
    });
    
    for (var row in _rows) {
      if (!row.isSelected) continue;
      
      if (row.titleCtrl.text.isNotEmpty && row.albumCtrl.text.isNotEmpty && row.artistCtrl.text.isNotEmpty) {
        continue; // Skip if already filled
      }
      
      String raw = row.titleCtrl.text.isEmpty ? row.originalSong.title : row.titleCtrl.text;
      
      if (raw.toLowerCase().contains(' x ') || raw.toLowerCase().contains('medley')) {
         row.isSelected = false; // Ignore medleys completely
         continue;
      }
      
      // 1. Web Lookup
      final webData = await MetadataService.searchMetadata(raw);
      if (webData != null) {
         row.titleCtrl.text = webData.title;
         row.albumCtrl.text = webData.album;
         row.yearCtrl.text = webData.year;
         row.artistCtrl.text = webData.artist;
         continue; // Successfully retrieved from Web
      }
      
      // 2. Heuristic Fallback
      String clean = raw.replaceAll('_', ' ');
      
      clean = clean.replaceAll(RegExp(r'Full.*?Audio', caseSensitive: false), ' ');
      clean = clean.replaceAll(RegExp(r'High\s*def.*', caseSensitive: false), ' ');
      clean = clean.replaceAll(RegExp(r'with.*?Audio', caseSensitive: false), ' ');
      clean = clean.replaceAll(RegExp(r'\b(HD|4K|1080p|720p|Official Video|Lyrical Video|Karaoke|गाने के बोल|Lyrical|Lyrics|Audio Song|Video Song|Music Video)\b', caseSensitive: false), ' ');
      clean = clean.replaceAll(RegExp(r'\bSong\b', caseSensitive: false), ' ');
      
      // Try splitting by pipes (YouTube often uses this)
      final parts = clean.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (parts.length > 1) {
         row.titleCtrl.text = parts[0].replaceAll(RegExp(r'\s+'), ' ').trim();
         int albumIndex = 1;
         
         final indianScriptReg = RegExp(r'[\u0900-\u0D7F]');
         if (parts.length > 2 && indianScriptReg.hasMatch(parts[1]) && !indianScriptReg.hasMatch(parts[0])) {
           albumIndex = 2; // Skip native title
         } else {
           final dashParts = row.titleCtrl.text.split('-');
           if (dashParts.length > 1 && indianScriptReg.hasMatch(dashParts[1])) {
              row.titleCtrl.text = dashParts[0].trim();
           }
         }
         
         if (parts.length > albumIndex && row.albumCtrl.text.isEmpty) {
            row.albumCtrl.text = parts[albumIndex];
         }
         
         if (parts.length > albumIndex + 1) {
            row.artistCtrl.text = parts.sublist(albumIndex + 1).where((e) => e.isNotEmpty).join(', ');
         }
      } else {
        // No pipes. Split by -
        final dashParts = clean.split('-');
        if (dashParts.length > 1) {
          final indianScriptReg = RegExp(r'[\u0900-\u0D7F]');
          if (indianScriptReg.hasMatch(dashParts[1]) && !indianScriptReg.hasMatch(dashParts[0])) {
             row.titleCtrl.text = dashParts[0].trim().replaceAll(RegExp(r'\s+'), ' ');
          } else if (indianScriptReg.hasMatch(dashParts[0]) && !indianScriptReg.hasMatch(dashParts[1])) {
             row.titleCtrl.text = dashParts[1].trim().replaceAll(RegExp(r'\s+'), ' ');
          } else {
             row.artistCtrl.text = dashParts[0].trim().replaceAll(RegExp(r'\s+'), ' ');
             row.titleCtrl.text = dashParts[1].trim().replaceAll(RegExp(r'\s+'), ' ');
          }
        } else {
          row.titleCtrl.text = clean.trim().replaceAll(RegExp(r'\s+'), ' ');
        }
      }
      
      row.titleCtrl.text = row.titleCtrl.text.replaceAll(RegExp(r'-\s*$'), '').trim();
      
      // Extract from brackets
      final bracketReg = RegExp(r'\[(.*?)\]');
      final parenReg = RegExp(r'\((.*?)\)');
      
      final brackets = bracketReg.allMatches(raw).map((m) => m.group(1) ?? '').toList();
      final parens = parenReg.allMatches(raw).map((m) => m.group(1) ?? '').toList();
      
      // Try to guess year from brackets
      for (final b in [...brackets, ...parens]) {
        if (RegExp(r'^\d{4}$').hasMatch(b.trim())) {
          row.yearCtrl.text = b.trim();
        } else if (b.trim().isNotEmpty && row.albumCtrl.text.isEmpty) {
           row.albumCtrl.text = b.trim();
        }
      }
      
      // Final title cleanup
      row.titleCtrl.text = row.titleCtrl.text.replaceAll(bracketReg, ' ').replaceAll(parenReg, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      
      String toTitleCase(String text) {
        if (text.isEmpty) return text;
        return text.split(' ').map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        }).join(' ');
      }
      
      row.titleCtrl.text = toTitleCase(row.titleCtrl.text);
      row.albumCtrl.text = toTitleCase(row.albumCtrl.text);
      row.artistCtrl.text = toTitleCase(row.artistCtrl.text);
      
      // Remove duplication like "Kalipattamai Kalipattamai" -> "Kalipattamai"
      List<String> words = row.titleCtrl.text.split(' ');
      if (words.length == 2 && words[0].toLowerCase() == words[1].toLowerCase()) {
         row.titleCtrl.text = words[0];
      } else if (words.length == 4 && words[0].toLowerCase() == words[2].toLowerCase() && words[1].toLowerCase() == words[3].toLowerCase()) {
         row.titleCtrl.text = '${words[0]} ${words[1]}';
      }
    }
    
    setState(() {
      _isExtracting = false;
    });
  }

  Future<void> _saveAll() async {
    final modifiedRows = _rows.where((r) => r.isModified && r.isSelected).toList();
    if (modifiedRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No changes to save.')));
      return;
    }

    setState(() => _isSaving = true);
    
    final service = Provider.of<FileExplorerService>(context, listen: false);
    int successCount = 0;
    
    // Track duplicates by name to prevent overwriting
    final Map<String, int> nameCounts = {};
    
    for (final row in modifiedRows) {
      try {
        String safeName = row.newTitle;
        if (nameCounts.containsKey(safeName)) {
           nameCounts[safeName] = nameCounts[safeName]! + 1;
           safeName = '$safeName (${nameCounts[safeName]})';
        } else {
           nameCounts[safeName] = 1;
        }
        
        await service.renameSong(row.originalSong.mmId ?? row.originalSong.id, row.originalSong.title, safeName);
        successCount++;
      } catch (e) {
        debugPrint('Failed to rename ${row.originalSong.title}: $e');
      }
    }
    
    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Successfully renamed $successCount songs.')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VoxProTheme.background,
      appBar: AppBar(
        title: const Text('Batch Rename Songs'),
        backgroundColor: VoxProTheme.cardBg,
        actions: [
          TextButton.icon(
            onPressed: () {
              bool allSelected = _rows.every((r) => r.isSelected);
              setState(() {
                for (var r in _rows) {
                  r.isSelected = !allSelected;
                }
              });
            },
            icon: const Icon(Icons.checklist, color: VoxProTheme.textSecondary),
            label: const Text('Toggle All', style: TextStyle(color: VoxProTheme.textSecondary)),
          ),
          if (_isExtracting)
             const Center(child: Padding(padding: EdgeInsets.only(right: 16.0), child: CircularProgressIndicator(color: VoxProTheme.accent))),
          if (!_isExtracting)
            TextButton.icon(
              onPressed: _smartExtract,
              icon: const Icon(Icons.auto_awesome, color: VoxProTheme.accent),
              label: const Text('Smart Extract', style: TextStyle(color: VoxProTheme.accent)),
            ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveAll,
            icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
            label: const Text('Save Changes'),
            style: ElevatedButton.styleFrom(backgroundColor: VoxProTheme.accent, foregroundColor: VoxProTheme.background),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _rows.isEmpty
          ? const Center(child: Text('No songs to rename.', style: TextStyle(color: VoxProTheme.textSecondary)))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _rows.length,
              separatorBuilder: (context, index) => const Divider(color: VoxProTheme.border, height: 32),
              itemBuilder: (context, index) {
                final row = _rows[index];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: row.isSelected,
                      onChanged: (val) {
                        setState(() {
                          row.isSelected = val ?? false;
                        });
                      },
                      activeColor: VoxProTheme.accent,
                    ),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Original Title:', style: TextStyle(color: VoxProTheme.textSecondary, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(row.originalSong.title, style: const TextStyle(color: VoxProTheme.textPrimary)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: row.titleCtrl,
                        style: const TextStyle(color: VoxProTheme.textPrimary, fontSize: 13),
                        decoration: const InputDecoration(labelText: 'Title', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: row.albumCtrl,
                        style: const TextStyle(color: VoxProTheme.textPrimary, fontSize: 13),
                        decoration: const InputDecoration(labelText: 'Album/Movie', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: row.yearCtrl,
                        style: const TextStyle(color: VoxProTheme.textPrimary, fontSize: 13),
                        decoration: const InputDecoration(labelText: 'Year', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: row.artistCtrl,
                        style: const TextStyle(color: VoxProTheme.textPrimary, fontSize: 13),
                        decoration: const InputDecoration(labelText: 'Artist(s)', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      row.isModified ? Icons.edit_note : Icons.check,
                      color: row.isModified ? VoxProTheme.accent : Colors.green,
                    ),
                  ],
                );
              },
            ),
    );
  }
}
