import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vox_player_core/vox_player_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/settings_service.dart';
import '../theme/voxpro_theme.dart';
import 'admin_ingestion_dialog.dart';
import 'backend_status_widget.dart';

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
  late TextEditingController _andMmdbController;
  late TextEditingController _winRootController;
  late TextEditingController _andRootController;
  late TextEditingController _engineController;
  late bool _prioritizeLocalSearch;
  late double _micLatency;

  @override
  void initState() {
    super.initState();
    _vaultController = TextEditingController(text: VoxSettingsService.instance.aiVaultPath);
    _hotZoneController = TextEditingController(text: VoxSettingsService.instance.aiHotZonePath);
    _dbController = TextEditingController(text: VoxSettingsService.instance.mediaMonkeyDbPath);
    _andMmdbController = TextEditingController(text: VoxSettingsService.instance.androidMmdbPath);
    _winRootController = TextEditingController(text: VoxSettingsService.instance.windowsMusicRoot);
    _andRootController = TextEditingController(text: VoxSettingsService.instance.androidMusicRoot);
    _engineController = TextEditingController(text: VoxSettingsService.instance.karaokeMakerEnginePath);
    _prioritizeLocalSearch = VoxSettingsService.instance.prioritizeLocalSearch;
    _micLatency = VoxSettingsService.instance.micLatencyOffset.toDouble();
    
    // In case we opened this screen very fast, wait for settings to finish loading then update UI
    VoxSettingsService.instance.initFuture.then((_) {
      if (mounted) {
        setState(() {
          _vaultController.text = VoxSettingsService.instance.aiVaultPath;
          _hotZoneController.text = VoxSettingsService.instance.aiHotZonePath;
          _dbController.text = VoxSettingsService.instance.mediaMonkeyDbPath;
          _andMmdbController.text = VoxSettingsService.instance.androidMmdbPath;
          _winRootController.text = VoxSettingsService.instance.windowsMusicRoot;
          _andRootController.text = VoxSettingsService.instance.androidMusicRoot;
          _engineController.text = VoxSettingsService.instance.karaokeMakerEnginePath;
          _prioritizeLocalSearch = VoxSettingsService.instance.prioritizeLocalSearch;
          _micLatency = VoxSettingsService.instance.micLatencyOffset.toDouble();
        });
      }
    });
  }

  @override
  void dispose() {
    _vaultController.dispose();
    _hotZoneController.dispose();
    _dbController.dispose();
    _andMmdbController.dispose();
    _winRootController.dispose();
    _andRootController.dispose();
    _engineController.dispose();
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
    await VoxSettingsService.instance.setAndroidMmdbPath(_andMmdbController.text);
    await VoxSettingsService.instance.setWindowsMusicRoot(_winRootController.text);
    await VoxSettingsService.instance.setAndroidMusicRoot(_andRootController.text);
    await VoxSettingsService.instance.setKaraokeMakerEnginePath(_engineController.text);
    await VoxSettingsService.instance.setPrioritizeLocalSearch(_prioritizeLocalSearch);
    await VoxSettingsService.instance.setMicLatencyOffset(_micLatency.toInt());
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved successfully.')));
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
      length: 4,
      child: AlertDialog(
        backgroundColor: VoxProTheme.cardBg,
        title: const Text('Settings'),
        content: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: BoxConstraints(
            maxWidth: 600,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
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
                  Tab(text: 'Services'),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TabBarView(
                  children: [
                    // Tab 1: Colors & Audio
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
                          const SizedBox(height: 24),
                          const Text('Mic Latency Offset (ms)', style: TextStyle(color: VoxProTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                          Slider(
                            value: _micLatency,
                            min: -500,
                            max: 500,
                            divisions: 100,
                            label: '${_micLatency.toInt()} ms',
                            activeColor: VoxProTheme.accent,
                            onChanged: (val) {
                              setState(() {
                                _micLatency = val;
                              });
                            },
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
                          const Text('MediaMonkey Database (MM.DB)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          _buildPathSelector(
                            controller: _dbController,
                            onPathSelected: (p) => _dbController.text = p,
                            isDirectory: false,
                            allowedExtensions: ['db', 'DB'],
                          ),
                          const SizedBox(height: 16),
                          const Text('Android MediaMonkey DB (MM.DB)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          _buildPathSelector(
                            controller: _andMmdbController,
                            onPathSelected: (p) => _andMmdbController.text = p,
                            isDirectory: false,
                            allowedExtensions: ['db', 'DB'],
                          ),
                          const SizedBox(height: 16),
                          const Text('Windows Music Root', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          _buildPathSelector(
                            controller: _winRootController,
                            onPathSelected: (p) => _winRootController.text = p,
                            isDirectory: true,
                          ),
                          const SizedBox(height: 16),
                          const Text('Android Music Root', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          _buildPathSelector(
                            controller: _andRootController,
                            onPathSelected: (p) => _andRootController.text = p,
                            isDirectory: true,
                          ),
                          const SizedBox(height: 16),
                          SwitchListTile(
                            title: const Text('Prioritize Local Database Search', style: TextStyle(color: Colors.white70, fontSize: 14)),
                            subtitle: const Text('Check local DB before falling back to remote host', style: TextStyle(color: Colors.white54, fontSize: 12)),
                            value: _prioritizeLocalSearch,
                            onChanged: (val) {
                              setState(() => _prioritizeLocalSearch = val);
                            },
                            contentPadding: EdgeInsets.zero,
                            activeColor: VoxProTheme.accent,
                          ),
                          const SizedBox(height: 16),
                          const Text('AI Vault Directory', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          _buildPathSelector(
                            controller: _vaultController,
                            onPathSelected: (p) => _vaultController.text = p,
                            isDirectory: true,
                          ),
                          const SizedBox(height: 16),
                          const Text('AI HotZone Directory', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          _buildPathSelector(
                            controller: _hotZoneController,
                            onPathSelected: (p) => _hotZoneController.text = p,
                            isDirectory: true,
                          ),
                          const SizedBox(height: 16),
                          const Text('Karaoke Maker Engine Directory', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          _buildPathSelector(
                            controller: _engineController,
                            onPathSelected: (p) => _engineController.text = p,
                            isDirectory: true,
                          ),
                          const SizedBox(height: 24),
                          Center(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.save),
                              label: const Text('Save Settings'),
                              style: ElevatedButton.styleFrom(backgroundColor: VoxProTheme.accent, foregroundColor: Colors.black),
                              onPressed: _savePaths,
                            ),
                          ),
                          const SizedBox(height: 16),
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
                          if (Platform.isAndroid) ...[
                            ElevatedButton.icon(
                              icon: const Icon(Icons.security),
                              label: const Text('Request Android Permissions'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[800]),
                              onPressed: () async {
                                await [
                                  Permission.microphone,
                                  Permission.storage,
                                  Permission.manageExternalStorage,
                                ].request();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permissions requested')));
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
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
                      // Tab 4: Services
                      const BackendStatusWidget(),
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
