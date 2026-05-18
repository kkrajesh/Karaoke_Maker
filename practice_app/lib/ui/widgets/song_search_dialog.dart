import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../theme/voxpro_theme.dart';
import 'song_list_tile.dart';

class SongSearchDialog extends StatefulWidget {
  final List<Song> allSongs;

  const SongSearchDialog({Key? key, required this.allSongs}) : super(key: key);

  @override
  State<SongSearchDialog> createState() => _SongSearchDialogState();
}

class _SongSearchDialogState extends State<SongSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Song> _filteredSongs = [];

  @override
  void initState() {
    super.initState();
    _filteredSongs = widget.allSongs;
  }

  void _filterSongs(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredSongs = widget.allSongs;
      });
    } else {
      setState(() {
        _filteredSongs = widget.allSongs
            .where((song) => song.title.toLowerCase().contains(query.toLowerCase()))
            .toList();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: VoxProTheme.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 600,
        height: 500,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: const TextStyle(color: VoxProTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search songs...',
                      hintStyle: const TextStyle(color: VoxProTheme.textSecondary),
                      prefixIcon: const Icon(Icons.search, color: VoxProTheme.textSecondary),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear, color: VoxProTheme.textSecondary),
                        onPressed: () {
                          _searchController.clear();
                          _filterSongs('');
                        },
                      ),
                      border: const OutlineInputBorder(),
                      enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: VoxProTheme.border)),
                      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: VoxProTheme.accent)),
                    ),
                    onChanged: _filterSongs,
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.close, color: VoxProTheme.textSecondary),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _filteredSongs.isEmpty
                  ? const Center(
                      child: Text('No songs found', style: TextStyle(color: VoxProTheme.textSecondary)),
                    )
                  : ListView.builder(
                      itemCount: _filteredSongs.length,
                      itemBuilder: (context, index) {
                        return SongListTile(
                          song: _filteredSongs[index],
                          onTap: () {
                            Navigator.pop(context, _filteredSongs[index]);
                          },
                          // onReprocess is explicitly null so chips are view-only here
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
