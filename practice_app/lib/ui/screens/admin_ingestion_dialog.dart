import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vox_player_core/vox_player_core.dart';
import '../theme/voxpro_theme.dart';

class AdminIngestionDialog extends StatefulWidget {
  const AdminIngestionDialog({Key? key}) : super(key: key);

  @override
  State<AdminIngestionDialog> createState() => _AdminIngestionDialogState();
}

class _AdminIngestionDialogState extends State<AdminIngestionDialog> {
  List<String> _pendingDirs = [];
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _scanHotZone();
  }

  Future<void> _scanHotZone() async {
    setState(() => _isLoading = true);
    final hotZonePath = VoxSettingsService.instance.aiHotZonePath;
    final dir = Directory(hotZonePath);
    
    List<String> dirs = [];
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final name = entity.path.split(Platform.pathSeparator).last;
          dirs.add(name);
        }
      }
    }
    
    if (mounted) {
      setState(() {
        _pendingDirs = dirs;
        _isLoading = false;
      });
    }
  }

  Future<void> _ingest(String dirName) async {
    setState(() => _isProcessing = true);
    try {
      // dirName is usually [songId]
      // We pass it to ingestProcessedFiles
      // The backend uses sanitizeTitle for the second arg if needed, but if we pass it exactly, it will find it.
      await VoxAiTrackingService.instance.ingestProcessedFiles(dirName, dirName);
      _pendingDirs.remove(dirName);
    } catch (e) {
      debugPrint('Failed to ingest $dirName: $e');
    }
    if (mounted) {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _bulkIngest() async {
    setState(() => _isProcessing = true);
    for (final dirName in List<String>.from(_pendingDirs)) {
      try {
        await VoxAiTrackingService.instance.ingestProcessedFiles(dirName, dirName);
        _pendingDirs.remove(dirName);
        setState(() {}); // update UI progress
      } catch (e) {
        debugPrint('Failed to ingest $dirName: $e');
      }
    }
    if (mounted) {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: VoxProTheme.cardBg,
      title: const Text('Force Ingest HotZone', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 500,
        height: 400,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _pendingDirs.isEmpty
                ? const Center(child: Text('HotZone is empty.', style: TextStyle(color: Colors.white70)))
                : Column(
                    children: [
                      Text('Found ${_pendingDirs.length} pending folders in HotZone:', style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _pendingDirs.length,
                          itemBuilder: (context, index) {
                            final dirName = _pendingDirs[index];
                            return ListTile(
                              title: Text(dirName, style: const TextStyle(color: Colors.white70)),
                              trailing: IconButton(
                                icon: const Icon(Icons.download, color: VoxProTheme.accent),
                                onPressed: _isProcessing ? null : () => _ingest(dirName),
                                tooltip: 'Ingest this folder',
                              ),
                            );
                          },
                        ),
                      ),
                      if (_isProcessing) const LinearProgressIndicator(),
                    ],
                  ),
      ),
      actions: [
        if (_pendingDirs.isNotEmpty)
          TextButton(
            onPressed: _isProcessing ? null : _bulkIngest,
            child: const Text('Bulk Ingest All', style: TextStyle(color: VoxProTheme.accent)),
          ),
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.pop(context),
          child: const Text('Close', style: TextStyle(color: VoxProTheme.textSecondary)),
        ),
      ],
    );
  }
}
