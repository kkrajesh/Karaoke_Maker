import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:vox_player_core/vox_player_core.dart';
import '../theme/voxpro_theme.dart';

class BackendStatusWidget extends StatefulWidget {
  const BackendStatusWidget({Key? key}) : super(key: key);

  @override
  State<BackendStatusWidget> createState() => _BackendStatusWidgetState();
}

class _BackendStatusWidgetState extends State<BackendStatusWidget> {
  Timer? _pollingTimer;
  bool _apiServerOnline = false;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkStatus());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    // Check Orchestrator Server
    try {
      final response = await http.get(Uri.parse('http://127.0.0.1:5000/health')).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _apiServerOnline = data['status'] == 'online';
      } else {
        _apiServerOnline = false;
      }
    } catch (e) {
      _apiServerOnline = false;
    }

    if (mounted) {
      setState(() {
        _isChecking = false;
      });
    }
  }

  Future<void> _startService(String scriptName, String title) async {
    final enginePath = VoxSettingsService.instance.karaokeMakerEnginePath;
    try {
      // Use cmd to spawn a visible terminal window so the user can monitor/stop the service
      await Process.start(
        'cmd',
        ['/c', 'start', title, 'py', scriptName],
        workingDirectory: enginePath,
      );
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Starting $title...')));
      
      // Force an immediate check and show loading state
      setState(() {
        _isChecking = true;
      });
      await Future.delayed(const Duration(seconds: 4));
      _checkStatus();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to start $title: $e')));
    }
  }

  Widget _buildServiceCard({
    required String title,
    required bool isOnline,
    required String scriptName,
    required List<String> dependentFeatures,
    required IconData icon,
  }) {
    return Card(
      color: Colors.black45,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isOnline ? Colors.green.withOpacity(0.5) : Colors.redAccent.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: isOnline ? Colors.green : Colors.redAccent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_isChecking)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                else if (isOnline)
                  const Chip(
                    label: Text('ONLINE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    backgroundColor: Colors.green,
                    padding: EdgeInsets.zero,
                  )
                else
                  ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('START'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: VoxProTheme.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () => _startService(scriptName, title),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Provided Features:', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: dependentFeatures.map((f) => Chip(
                label: Text(f, style: const TextStyle(fontSize: 11)),
                backgroundColor: Colors.grey[850],
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Text(
            'Backend Services & AI Modules', 
            style: TextStyle(color: VoxProTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)
          ),
          const SizedBox(height: 8),
          const Text(
            'Monitor the health of the local Python engine services required for AI processing, searching, and stem generation.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 24),
          _buildServiceCard(
            title: 'Karaoke Engine Orchestrator',
            scriptName: 'karaoke_orchestrator.py',
            isOnline: _apiServerOnline,
            icon: Icons.hub,
            dependentFeatures: [
              'Universal Song Search', 
              'YouTube Fetcher', 
              'Lyrics Fetcher (AI)', 
              'Practice MP3 Generator', 
              'Stem Processing',
              'Background Job Management', 
              'Database Ingestion'
            ],
          ),
        ],
      ),
    );
  }
}
