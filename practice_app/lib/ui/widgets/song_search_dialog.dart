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
  
  bool? _filterVocals;
  bool? _filterInst;
  bool? _filterPitch;
  bool? _filterMap;
  bool? _filterLyrics;

  bool? _nextFilterState(bool? current) {
    if (current == null) return true;
    if (current == true) return false;
    return null;
  }

  Widget _buildTriStateChip(String label, bool? state, ValueChanged<bool?> onChanged, Color accentColor) {
    final isSelected = state != null;
    final isExclude = state == false;
    final activeColor = isExclude ? Colors.redAccent : accentColor;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onChanged(_nextFilterState(state)),
      selectedColor: activeColor.withValues(alpha: 0.3),
      checkmarkColor: activeColor,
      showCheckmark: false,
      avatar: isSelected ? Icon(isExclude ? Icons.block : Icons.check, color: activeColor, size: 18) : null,
      side: BorderSide(color: isSelected ? activeColor : VoxProTheme.border),
    );
  }

  @override
  void initState() {
    super.initState();
    _filteredSongs = widget.allSongs;
  }

  void _applyFilters() {
    setState(() {
      var filtered = widget.allSongs;
      
      final query = _searchController.text.trim().toLowerCase();
      if (query.isNotEmpty) {
        filtered = filtered.where((song) => song.title.toLowerCase().contains(query)).toList();
      }
      
      if (_filterVocals == true) filtered = filtered.where((s) => s.hasVocals).toList();
      if (_filterVocals == false) filtered = filtered.where((s) => !s.hasVocals).toList();
      
      if (_filterInst == true) filtered = filtered.where((s) => s.hasInstrumental).toList();
      if (_filterInst == false) filtered = filtered.where((s) => !s.hasInstrumental).toList();
      
      if (_filterPitch == true) filtered = filtered.where((s) => s.hasPitchProfile).toList();
      if (_filterPitch == false) filtered = filtered.where((s) => !s.hasPitchProfile).toList();
      
      if (_filterMap == true) filtered = filtered.where((s) => s.hasVocalMap).toList();
      if (_filterMap == false) filtered = filtered.where((s) => !s.hasVocalMap).toList();
      
      if (_filterLyrics == true) filtered = filtered.where((s) => s.hasEnglishLyrics || s.hasNativeLyrics).toList();
      if (_filterLyrics == false) filtered = filtered.where((s) => !(s.hasEnglishLyrics || s.hasNativeLyrics)).toList();
      
      _filteredSongs = filtered;
    });
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
        constraints: const BoxConstraints(maxWidth: 600),
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
                          _applyFilters();
                        },
                      ),
                      border: const OutlineInputBorder(),
                      enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: VoxProTheme.border)),
                      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: VoxProTheme.accent)),
                    ),
                    onChanged: (_) => _applyFilters(),
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
            Wrap(
              spacing: 8.0,
              runSpacing: 4.0,
              children: [
                _buildTriStateChip('Vocals', _filterVocals, (v) { _filterVocals = v; _applyFilters(); }, VoxProTheme.vocalAccent),
                _buildTriStateChip('Instrumental', _filterInst, (v) { _filterInst = v; _applyFilters(); }, VoxProTheme.instAccent),
                _buildTriStateChip('Pitch', _filterPitch, (v) { _filterPitch = v; _applyFilters(); }, VoxProTheme.pitchAccent),
                _buildTriStateChip('Map', _filterMap, (v) { _filterMap = v; _applyFilters(); }, VoxProTheme.mapAccent),
                _buildTriStateChip('Lyrics', _filterLyrics, (v) { _filterLyrics = v; _applyFilters(); }, VoxProTheme.lyricsAccent),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _filteredSongs.isEmpty
                  ? const Center(
                      child: Text('No songs found', style: TextStyle(color: VoxProTheme.textSecondary)),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text('${_filteredSongs.length} songs found', style: const TextStyle(color: VoxProTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                        Expanded(
                          child: ListView.builder(
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
          ],
        ),
      ),
    );
  }
}
