import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../theme/voxpro_theme.dart';

class SongListTile extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  /// If provided, the component chips will be interactive and trigger this callback.
  /// If null, the chips will be view-only.
  final void Function(BuildContext context, String songId, String label, String component)? onReprocess;
  final VoidCallback? onRemove;

  const SongListTile({
    Key? key,
    required this.song,
    required this.onTap,
    this.onReprocess,
    this.onRemove,
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
    return Opacity(
      opacity: song.isMissing ? 0.6 : 1.0,
      child: Card(
        color: VoxProTheme.cardBg,
        margin: const EdgeInsets.only(bottom: 8.0),
        child: ListTile(
          title: Row(
            children: [
              Expanded(
                child: Text(
                  song.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: song.isMissing ? Colors.redAccent : VoxProTheme.textPrimary,
                    decoration: song.isMissing ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (song.isMissing)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                  child: const Text('Missing', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
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
          trailing: song.isMissing
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onReprocess != null)
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.amberAccent),
                        onPressed: () => onReprocess!(context, song.id, 'Full Song', 'all'),
                        tooltip: 'Reprocess Missing Song',
                      ),
                    if (onRemove != null)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: onRemove,
                        tooltip: 'Remove from Database',
                      ),
                  ],
                )
              : const Icon(Icons.play_circle_fill, color: VoxProTheme.accent),
          onTap: song.isMissing ? null : onTap,
        ),
      ),
    );
  }
}
