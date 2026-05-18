import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../theme/voxpro_theme.dart';

class SongListTile extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  /// If provided, the component chips will be interactive and trigger this callback.
  /// If null, the chips will be view-only.
  final void Function(BuildContext context, String songId, String label, String component)? onReprocess;

  const SongListTile({
    Key? key,
    required this.song,
    required this.onTap,
    this.onReprocess,
  }) : super(key: key);

  Widget _buildComponentChip(BuildContext context, String label, String component, bool exists) {
    Widget child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(color: VoxProTheme.textSecondary, fontSize: 12)),
          Icon(exists ? Icons.check_box : Icons.cancel, color: exists ? Colors.green : Colors.red, size: 14),
        ],
      ),
    );

    if (onReprocess != null) {
      return InkWell(
        onTap: () => onReprocess!(context, song.id, label, component),
        borderRadius: BorderRadius.circular(4),
        child: child,
      );
    }
    return child;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: VoxProTheme.cardBg,
      margin: const EdgeInsets.only(bottom: 8.0),
      child: ListTile(
        title: Text(song.title, style: const TextStyle(fontWeight: FontWeight.bold, color: VoxProTheme.textPrimary)),
        subtitle: Wrap(
          spacing: 4.0,
          children: [
            _buildComponentChip(context, 'Inst', 'instrumental', song.hasInstrumental),
            const Text('|', style: TextStyle(color: VoxProTheme.textSecondary, fontSize: 12)),
            _buildComponentChip(context, 'Vocals', 'vocals', song.hasVocals),
            const Text('|', style: TextStyle(color: VoxProTheme.textSecondary, fontSize: 12)),
            _buildComponentChip(context, 'Pitch', 'pitch', song.hasPitchProfile),
            const Text('|', style: TextStyle(color: VoxProTheme.textSecondary, fontSize: 12)),
            _buildComponentChip(context, 'Map', 'map', song.hasVocalMap),
            const Text('|', style: TextStyle(color: VoxProTheme.textSecondary, fontSize: 12)),
            _buildComponentChip(context, 'Lyrics', 'lyrics', song.hasNativeLyrics || song.hasEnglishLyrics),
          ],
        ),
        trailing: const Icon(Icons.play_circle_fill, color: VoxProTheme.accent),
        onTap: onTap,
      ),
    );
  }
}
