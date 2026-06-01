import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../theme/voxpro_theme.dart';

class SongCard extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final void Function(BuildContext, String, String, String)? onReprocess;

  const SongCard({Key? key, required this.song, required this.onTap, this.onRemove, this.onReprocess}) : super(key: key);

  Widget _buildBadge(IconData icon, String label, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: active ? VoxProTheme.accent.withOpacity(0.1) : VoxProTheme.background,
        border: Border.all(color: active ? VoxProTheme.accent.withOpacity(0.5) : VoxProTheme.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: active ? VoxProTheme.accent : VoxProTheme.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: active ? VoxProTheme.accent : VoxProTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: song.isMissing ? 0.6 : 1.0,
      child: InkWell(
        onTap: song.isMissing ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // Cover art placeholder
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: song.isMissing ? Colors.red.withOpacity(0.1) : VoxProTheme.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: song.isMissing ? Colors.red.withOpacity(0.3) : VoxProTheme.border),
                  ),
                  child: Center(
                    child: song.isMissing 
                        ? const Icon(Icons.error_outline, size: 48, color: Colors.redAccent)
                        : const Icon(Icons.music_note, size: 48, color: VoxProTheme.border),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      song.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 16,
                        color: song.isMissing ? Colors.redAccent : VoxProTheme.textPrimary,
                        decoration: song.isMissing ? TextDecoration.lineThrough : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onReprocess != null)
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.refresh, color: Colors.amberAccent, size: 20),
                          tooltip: 'Reprocess Options',
                          padding: EdgeInsets.zero,
                          onSelected: (value) {
                            if (value == 'all') {
                              onReprocess!(context, song.id, 'Full Song', 'all');
                            } else if (value == 'redownload') {
                              onReprocess!(context, song.id, 'Full Re-download', 'redownload');
                            } else if (value == 'lyrics') {
                              onReprocess!(context, song.id, 'Lyrics', 'lyrics');
                            } else if (value == 'audio') {
                              onReprocess!(context, song.id, 'Audio (Demucs)', 'audio');
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'all', child: Text('Reprocess Full Song')),
                            const PopupMenuItem(value: 'redownload', child: Text('Reprocess Entirely (Re-download Audio)')),
                            const PopupMenuItem(value: 'lyrics', child: Text('Reprocess Lyrics Only')),
                            const PopupMenuItem(value: 'audio', child: Text('Reprocess Audio Only')),
                          ],
                        ),
                      if (onReprocess != null && song.isMissing && onRemove != null)
                        const SizedBox(width: 12),
                      if (song.isMissing && onRemove != null)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                          onPressed: onRemove,
                          tooltip: 'Remove from Database',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildBadge(Icons.multitrack_audio, 'AUDIO', song.hasInstrumental),
                  _buildBadge(Icons.show_chart, 'PITCH', song.hasPitchProfile),
                  _buildBadge(Icons.lyrics, 'LYRICS', song.hasEnglishLyrics || song.hasNativeLyrics),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}
