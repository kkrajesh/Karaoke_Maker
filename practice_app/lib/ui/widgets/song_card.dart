import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../theme/voxpro_theme.dart';

class SongCard extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;

  const SongCard({Key? key, required this.song, required this.onTap}) : super(key: key);

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
    return InkWell(
      onTap: onTap,
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
                    color: VoxProTheme.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: VoxProTheme.border),
                  ),
                  child: const Center(
                    child: Icon(Icons.music_note, size: 48, color: VoxProTheme.border),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                song.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
    );
  }
}
