import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/settings_service.dart';
import '../theme/voxpro_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  static const List<Color> availableColors = [
    Color(0xFF00FFFF), // Neon Cyan
    Color(0xFFFF00FF), // Neon Pink
    Color(0xFF32CD32), // Lime Green
    Color(0xFFFFD700), // Gold
    Color(0xFF00BFFF), // Deep Sky Blue
    Color(0xFFFF4500), // Orange Red
    Color(0xFFFFFFFF), // White
  ];

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);

    return AlertDialog(
      backgroundColor: VoxProTheme.cardBg,
      title: const Text('Settings'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pitch Visualizer Colors', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: VoxProTheme.textPrimary)),
            const SizedBox(height: 24),
            _buildColorSection(
              context,
              title: 'Target Pitch Line Color',
              currentColor: settings.targetPitchColor,
              onColorSelected: settings.setTargetPitchColor,
            ),
            const SizedBox(height: 32),
            _buildColorSection(
              context,
              title: 'User Pitch Line Color',
              currentColor: settings.userPitchColor,
              onColorSelected: settings.setUserPitchColor,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(color: VoxProTheme.textSecondary)),
        )
      ],
    );
  }

  Widget _buildColorSection(BuildContext context, {required String title, required Color currentColor, required Function(Color) onColorSelected}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: VoxProTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: availableColors.map((color) {
            final isSelected = color.value == currentColor.value;
            return GestureDetector(
              onTap: () => onColorSelected(color),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.transparent,
                    width: 3,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.5),
                            blurRadius: 10,
                            spreadRadius: 2,
                          )
                        ]
                      : null,
                ),
                child: isSelected ? const Icon(Icons.check, color: Colors.black) : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
