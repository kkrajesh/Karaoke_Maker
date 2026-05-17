import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/api_service.dart';
import '../theme/voxpro_theme.dart';

class CreateSongScreen extends StatefulWidget {
  const CreateSongScreen({Key? key}) : super(key: key);

  @override
  _CreateSongScreenState createState() => _CreateSongScreenState();
}

class _CreateSongScreenState extends State<CreateSongScreen> {
  int _currentStep = 0;
  
  // Step 1: Search / Local File
  final TextEditingController _queryController = TextEditingController();
  String? _localAudioPath;
  bool _isLocalAudio = false;

  // Step 2: Select Source
  List<dynamic> _searchResults = [];
  bool _isSearching = false;
  String? _selectedUrl;

  // Step 3: Lyrics
  final TextEditingController _lyricsController = TextEditingController();
  bool _isFetchingLyrics = false;
  String _lyricsType = 'txt'; // 'txt' or 'lrc'
  
  // Step 4: Process
  bool _isProcessing = false;
  String _processStatus = "Ready to start...";

  Future<void> _searchOnline() async {
    final q = _queryController.text.trim();
    if (q.isEmpty) return;

    setState(() {
      _isSearching = true;
      _isLocalAudio = false;
      _localAudioPath = null;
    });

    try {
      final results = await ApiService.search(q);
      setState(() {
        _searchResults = results;
        _isSearching = false;
        _currentStep = 1; // Move to next step automatically
      });
    } catch (e) {
      setState(() { _isSearching = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Search failed: $e')));
    }
  }

  Future<void> _pickLocalAudio() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.audio,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _localAudioPath = result.files.single.path;
        _isLocalAudio = true;
        // Skip Step 2 because we have a local file
        _currentStep = 2;
      });
    }
  }

  Future<void> _fetchLyrics() async {
    final q = _queryController.text.trim();
    if (q.isEmpty) return;

    setState(() { _isFetchingLyrics = true; });

    try {
      final data = await ApiService.fetchLyrics(q);
      setState(() {
        _lyricsController.text = data['text'] ?? '';
        _lyricsType = data['type'] ?? 'txt';
        _isFetchingLyrics = false;
      });
    } catch (e) {
      setState(() { _isFetchingLyrics = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lyrics fetch failed: $e')));
    }
  }

  Future<void> _pickLocalLyrics() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'lrc'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final text = await file.readAsString();
      final isLrc = result.files.single.extension?.toLowerCase() == 'lrc';
      
      setState(() {
        _lyricsController.text = text;
        _lyricsType = isLrc ? 'lrc' : 'txt';
      });
    }
  }

  Future<void> _startProcessing() async {
    final q = _queryController.text.trim();
    if (q.isEmpty) return;

    final songId = q.replaceAll(' ', '_').replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');

    setState(() {
      _isProcessing = true;
      _processStatus = "Sending request to Core Engine...";
    });

    try {
      final taskId = await ApiService.processSong(
        songId: songId,
        url: _isLocalAudio ? null : _selectedUrl,
        localAudioPath: _isLocalAudio ? _localAudioPath : null,
        lyricsText: _lyricsController.text.trim(),
        lyricsType: _lyricsType,
      );

      _pollStatus(taskId);
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _processStatus = 'Failed: $e';
      });
    }
  }

  Future<void> _pollStatus(String taskId) async {
    bool done = false;
    while (!done) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) break;
      
      try {
        final status = await ApiService.getStatus(taskId);
        setState(() {
          _processStatus = "Status: ${status['status']}...";
        });
        
        if (status['status'] == 'completed') {
          done = true;
          setState(() {
            _processStatus = "Successfully Generated Assets!";
            _isProcessing = false;
          });
          // Show success and maybe pop after a delay
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Processing Complete! Song added to dashboard.")),
          );
        } else if (status['status'] == 'failed') {
          done = true;
          setState(() {
            _processStatus = "Failed: ${status['error']}";
            _isProcessing = false;
          });
        }
      } catch (e) {
        // Just keep polling, server might be busy
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VoxProTheme.background,
      appBar: AppBar(
        title: const Text('Create New Song'),
        backgroundColor: VoxProTheme.sidebar,
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: VoxProTheme.accent,
            background: VoxProTheme.background,
            surface: VoxProTheme.cardBg,
          ),
        ),
        child: Stepper(
          currentStep: _currentStep,
          onStepTapped: (step) => setState(() => _currentStep = step),
          onStepContinue: () {
            if (_currentStep == 0 && _queryController.text.isNotEmpty) {
              if (!_isLocalAudio) _searchOnline();
              else setState(() => _currentStep = 2);
            } else if (_currentStep == 1 && _selectedUrl != null) {
              setState(() => _currentStep = 2);
            } else if (_currentStep == 2) {
              setState(() => _currentStep = 3);
            } else if (_currentStep == 3) {
              if (!_isProcessing) _startProcessing();
            }
          },
          onStepCancel: () {
            if (_currentStep > 0) {
              setState(() => _currentStep -= 1);
            }
          },
          steps: [
            // STEP 1: Search
            Step(
              title: const Text('Song Details', style: TextStyle(color: VoxProTheme.textPrimary)),
              content: Column(
                children: [
                  TextField(
                    controller: _queryController,
                    style: const TextStyle(color: VoxProTheme.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Song Name & Context (e.g. "Tum Hi Ho Arijit Singh")',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isSearching ? null : _searchOnline,
                        icon: _isSearching 
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.search),
                        label: const Text("Search Online"),
                      ),
                      const SizedBox(width: 16),
                      const Text("OR", style: TextStyle(color: VoxProTheme.textSecondary)),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: _pickLocalAudio,
                        icon: const Icon(Icons.folder),
                        label: const Text("Select Local Audio"),
                        style: ElevatedButton.styleFrom(backgroundColor: VoxProTheme.sidebar),
                      ),
                    ],
                  ),
                  if (_isLocalAudio && _localAudioPath != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Text("Selected: $_localAudioPath", style: const TextStyle(color: VoxProTheme.accent)),
                    ),
                ],
              ),
              isActive: _currentStep >= 0,
            ),
            
            // STEP 2: Select Source
            Step(
              title: const Text('Select Source', style: TextStyle(color: VoxProTheme.textPrimary)),
              content: _isLocalAudio 
                  ? const Text("Skipped (Using local audio file)", style: TextStyle(color: VoxProTheme.textSecondary))
                  : Column(
                      children: _searchResults.map((res) {
                        final bool isRecommended = res['recommended'] == true;
                        return Card(
                          color: _selectedUrl == res['url'] ? VoxProTheme.accent.withOpacity(0.2) : VoxProTheme.cardBg,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                              color: isRecommended ? VoxProTheme.vocalAccent : VoxProTheme.border,
                              width: isRecommended ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListTile(
                            title: Text(res['title'], style: const TextStyle(color: VoxProTheme.textPrimary)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(res['url'], style: const TextStyle(color: VoxProTheme.textSecondary, fontSize: 12)),
                                if (isRecommended)
                                  Text("AI Top Pick: ${res['reason']}", style: const TextStyle(color: VoxProTheme.vocalAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            trailing: _selectedUrl == res['url'] ? const Icon(Icons.check_circle, color: VoxProTheme.accent) : null,
                            onTap: () {
                              setState(() { _selectedUrl = res['url']; });
                            },
                          ),
                        );
                      }).toList(),
                    ),
              isActive: _currentStep >= 1,
            ),
            
            // STEP 3: Lyrics
            Step(
              title: const Text('Review Lyrics', style: TextStyle(color: VoxProTheme.textPrimary)),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isFetchingLyrics ? null : _fetchLyrics,
                        icon: _isFetchingLyrics 
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.cloud_download),
                        label: const Text("Auto-Fetch via AI"),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: _pickLocalLyrics,
                        icon: const Icon(Icons.upload_file),
                        label: const Text("Load Local .lrc/.txt"),
                        style: ElevatedButton.styleFrom(backgroundColor: VoxProTheme.sidebar),
                      ),
                      const SizedBox(width: 16),
                      Text("Type: $_lyricsType", style: const TextStyle(color: VoxProTheme.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _lyricsController,
                    maxLines: 15,
                    style: const TextStyle(color: VoxProTheme.textPrimary, fontFamily: 'Courier'),
                    decoration: const InputDecoration(
                      hintText: "Lyrics will appear here for review and editing...",
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: VoxProTheme.cardBg,
                    ),
                  ),
                ],
              ),
              isActive: _currentStep >= 2,
            ),
            
            // STEP 4: Process
            Step(
              title: const Text('Extract & Process', style: TextStyle(color: VoxProTheme.textPrimary)),
              content: Column(
                children: [
                  if (_isProcessing)
                    const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: CircularProgressIndicator(color: VoxProTheme.vocalAccent),
                    ),
                  Text(
                    _processStatus,
                    style: TextStyle(
                      color: _processStatus.contains("Failed") ? Colors.red : VoxProTheme.accent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "This will trigger Demucs separation and pyin pitch extraction. "
                    "This usually takes 2-5 minutes depending on the song length.",
                    style: TextStyle(color: VoxProTheme.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              isActive: _currentStep >= 3,
            ),
          ],
        ),
      ),
    );
  }
}
