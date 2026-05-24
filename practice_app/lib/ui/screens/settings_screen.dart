import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vox_player_core/vox_player_core.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/settings_service.dart';
import '../theme/voxpro_theme.dart';
import 'admin_ingestion_dialog.dart';

class SettingsScreen extends StatefulWidget {
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
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _vaultController;
  late TextEditingController _hotZoneController;
  late TextEditingController _dbController;

  @override
  void initState() {
    super.initState();
    _vaultController = TextEditingController(text: VoxSettingsService.instance.aiVaultPath);
    _hotZoneController = TextEditingController(text: VoxSettingsService.instance.aiHotZonePath);
    _dbController = TextEditingController(text: VoxSettingsService.instance.mediaMonkeyDbPath);
  }

  @override
  void dispose() {
    _vaultController.dispose();
    _hotZoneController.dispose();
    _dbController.dispose();
    super.dispose();
  }

  Future<void> _savePaths() async {
    final oldVault = VoxSettingsService.instance.aiVaultPath;
    final newVault = _vaultController.text;
    final oldHotZone = VoxSettingsService.instance.aiHotZonePath;
    final newHotZone = _hotZoneController.text;

    if (oldVault != newVault) {
      await _promptToMoveContents(oldVault, newVault, 'AI Vault');
    }
    if (oldHotZone != newHotZone) {
      await _promptToMoveContents(oldHotZone, newHotZone, 'AI HotZone');
    }

    await VoxSettingsService.instance.setAiVaultPath(newVault);
    await VoxSettingsService.instance.setAiHotZonePath(newHotZone);
    await VoxSettingsService.instance.setMediaMonkeyDbPath(_dbController.text);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paths saved successfully.')));
    }
  }

  Future<void> _promptToMoveContents(String oldPath, String newPath, String name) async {
    final shouldMove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text('Move $name contents?'),
        content: Text('You changed the $name path.\n\nFrom: $oldPath\nTo: $newPath\n\nWould you like to move the existing files to the new location?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes', style: TextStyle(color: Colors.pinkAccent))),
        ],
      ),
    );

    if (shouldMove == true) {
      try {
        final src = Directory(oldPath);
        final dest = Directory(newPath);
        if (await src.exists()) {
          if (!await dest.exists()) await dest.create(recursive: true);
          await for (final entity in src.list()) {
            final newEntityPath = '${dest.path}\\${entity.uri.pathSegments.lastWhere((e) => e.isNotEmpty)}';
            if (entity is File) {
              await entity.copy(newEntityPath);
              await entity.delete();
            } else if (entity is Directory) {
              await entity.rename(newEntityPath); 
            }
          }
        }
      } catch (e) {
        debugPrint('Failed to move contents: $e');
      }
    }
  }

  Widget _buildPathSelector({
    required TextEditingController controller,
    required Function(String) onPathSelected,
    required bool isDirectory,
    List<String>? allowedExtensions,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: const InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.black45,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.folder_open, color: Colors.white54),
          onPressed: () async {
            String? path;
            if (isDirectory) {
              path = await FilePicker.getDirectoryPath();
            } else {
              final result = await FilePicker.pickFiles(
                type: allowedExtensions != null ? FileType.custom : FileType.any,
                allowedExtensions: allowedExtensions,
              );
              path = result?.files?.single.path;
            }
            if (path != null) {
              onPathSelected(path);
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsService>(context);

    return DefaultTabController(
      length: 3,
      child: AlertDialog(
        backgroundColor: VoxProTheme.cardBg,
        title: const Text('Settings'),
        content: SizedBox(
          width: 500,
          height: 400, // Fixed height to prevent overflow
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const TabBar(
                indicatorColor: VoxProTheme.accent,
                labelColor: VoxProTheme.accent,
                unselectedLabelColor: VoxProTheme.textSecondary,
                tabs: [
                  Tab(text: 'Visualizer'),
                  Tab(text: 'Paths'),
                  Tab(text: 'Admin'),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TabBarView(
                  children: [
                    // Tab 1: Colors
                    SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          _buildColorSection(
                            context,
                            title: 'Target Pitch Line Color',
                            currentColor: settings.targetPitchColor,
                            onColorSelected: settings.setTargetPitchColor,
                          ),
                          const SizedBox(height: 24),
                          _buildColorSection(
                            context,
                            title: 'User Pitch Line Color',
                            currentColor: settings.userPitchColor,
                            onColorSelected: settings.setUserPitchColor,
                          ),
                        ],
                      ),
                    ),
                    // Tab 2: Paths
                    SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          const Text('AI Vault Directory', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 8),
                          _buildPathSelector(
                            controller: _vaultController,
                            onPathSelected: (p) => _vaultController.text = p,
                            isDirectory: true,
                          ),
                          const SizedBox(height: 16),
                          const Text('AI HotZone Directory (Processing Area)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 8),
                          _buildPathSelector(
                            controller: _hotZoneController,
                            onPathSelected: (p) => _hotZoneController.text = p,
                            isDirectory: true,
                          ),
                          const SizedBox(height: 16),
                          const Text('MediaMonkey Database (MM.DB)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 8),
                          _buildPathSelector(
                            controller: _dbController,
                            onPathSelected: (p) => _dbController.text = p,
                            isDirectory: false,
                            allowedExtensions: ['db', 'DB'],
                          ),
                          const SizedBox(height: 24),
                          Center(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.save),
                              label: const Text('Save Paths & Check Moves'),
                              style: ElevatedButton.styleFrom(backgroundColor: VoxProTheme.accent, foregroundColor: Colors.black),
                              onPressed: _savePaths,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Tab 3: Admin
                    SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Text('Maintenance Tools', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: VoxProTheme.textPrimary)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.download),
                            label: const Text('Force Ingest HotZone'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[800]),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => const AdminIngestionDialog(),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.drive_file_rename_outline),
                            label: const Text('Migrate Legacy Vault Files'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[800]),
                            onPressed: () => _migrateLegacyVault(context, VoxSettingsService.instance.aiVaultPath),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
      ),
    );
  }

  Widget _buildColorSection(BuildContext context, {required String title, required Color currentColor, required Function(Color) onColorSelected}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: VoxProTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: SettingsScreen.availableColors.map((color) {
            final isSelected = color.value == currentColor.value;
            return GestureDetector(
              onTap: () => onColorSelected(color),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.transparent,
                    width: 2,
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

  Future<void> _migrateLegacyVault(BuildContext context, String vaultPath) async {
    final vaultDir = Directory(vaultPath);

    if (!await vaultDir.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Vault directory not found: $vaultPath')));
      return;
    }

    int renamedCount = 0;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const AlertDialog(
        backgroundColor: VoxProTheme.cardBg,
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Migrating Vault Files...', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    try {
      await for (final entity in vaultDir.list()) {
        if (entity is Directory) {
          final dirName = entity.path.split(Platform.pathSeparator).last;
          if (dirName == '_HotZone') continue;
          
          final prefix = '${dirName}_';
          
          await for (final subEntity in entity.list()) {
            if (subEntity is File) {
              final fileName = subEntity.path.split(Platform.pathSeparator).last;
              if (!fileName.startsWith(prefix)) {
                final newFileName = '$prefix$fileName';
                final newPath = '${entity.path}${Platform.pathSeparator}$newFileName';
                
                try {
                  await subEntity.rename(newPath);
                  renamedCount++;
                } catch (e) {
                  debugPrint('Failed to rename $fileName: $e');
                }
              }
            }
          }
        }
      }
    } finally {
      Navigator.pop(context); // close progress
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restore complete. Total files renamed: $renamedCount')));
    }
  }
}
