import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../services/api_service.dart';
import '../../services/file_explorer_service.dart';
import '../theme/voxpro_theme.dart';
import '../widgets/song_card.dart';
import 'active_session_screen.dart';
import 'create_song_screen.dart';
import '../../models/song.dart';
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  Song? _selectedSong;
  bool _isListView = true;

  Widget _buildSidebar() {
    return Container(
      width: 250,
      color: VoxProTheme.sidebar,
      child: Column(
        children: [
          const SizedBox(height: 32),
          Text(
            'KARAOKE MAKER',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              color: VoxProTheme.accent,
            ),
          ),
          const SizedBox(height: 32),
          _buildSidebarItem(Icons.library_music, 'Library', 0),
          _buildSidebarItem(Icons.mic, 'Active Session', 1),
          const Spacer(),
          _buildSidebarItem(Icons.settings, 'Settings', 2),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(IconData icon, String title, int index) {
    final isActive = _selectedIndex == index;
    return ListTile(
      leading: Icon(icon, color: isActive ? VoxProTheme.accent : VoxProTheme.textSecondary),
      title: Text(
        title,
        style: TextStyle(
          color: isActive ? VoxProTheme.accent : VoxProTheme.textSecondary,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isActive,
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
    );
  }

  void _showReprocessDialog(BuildContext context, String songId, String label, String component) {
    final TextEditingController lyricsController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: VoxProTheme.cardBg,
          title: Text('Reprocess $label?', style: const TextStyle(color: VoxProTheme.accent)),
          content: component == 'lyrics'
              ? SizedBox(
                  width: 500,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'This will delete existing lyrics and regenerate them. You can paste manual lyrics below or upload a local file. Leave blank to automatically scrape the web.',
                        style: TextStyle(color: VoxProTheme.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            FilePickerResult? result = await FilePicker.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['txt', 'lrc'],
                            );
                            if (result != null) {
                              File file = File(result.files.single.path!);
                              String content = await file.readAsString();
                              lyricsController.text = content;
                            }
                          },
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Upload Local File'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: VoxProTheme.border,
                            foregroundColor: VoxProTheme.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: lyricsController,
                        maxLines: 8,
                        style: const TextStyle(color: VoxProTheme.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'Paste lyrics here...',
                          hintStyle: TextStyle(color: VoxProTheme.textSecondary),
                          border: OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: VoxProTheme.border)),
                          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: VoxProTheme.accent)),
                        ),
                      ),
                    ],
                  ),
                )
              : Text('This will delete the existing $label data and regenerate it in the background.',
                  style: const TextStyle(color: VoxProTheme.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: VoxProTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  final service = Provider.of<FileExplorerService>(context, listen: false);
                  final taskId = await ApiService.reprocessComponent(
                    songId: songId,
                    component: component,
                    lyricsText: component == 'lyrics' && lyricsController.text.isNotEmpty ? lyricsController.text : null,
                  );
                  if (context.mounted) {
                    service.trackTask(taskId, songId, ScaffoldMessenger.of(context));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: VoxProTheme.vocalAccent),
              child: const Text('Reprocess', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildComponentChip(BuildContext context, String songId, String label, String component, bool exists) {
    return InkWell(
      onTap: () => _showReprocessDialog(context, songId, label, component),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label: ', style: const TextStyle(color: VoxProTheme.textSecondary, fontSize: 12)),
            Icon(exists ? Icons.check_box : Icons.cancel, color: exists ? Colors.green : Colors.red, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryView(FileExplorerService service) {
    if (service.currentDirectory == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_off, size: 64, color: VoxProTheme.textSecondary),
            const SizedBox(height: 16),
            const Text(
              'No Directory Selected',
              style: TextStyle(color: VoxProTheme.textSecondary, fontSize: 18),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => service.pickDirectory(),
              icon: const Icon(Icons.drive_folder_upload),
              label: const Text('Select OneDrive Folder'),
              style: ElevatedButton.styleFrom(
                backgroundColor: VoxProTheme.accent,
                foregroundColor: VoxProTheme.background,
              ),
            )
          ],
        ),
      );
    }

    if (service.isLoading) {
      return const Center(child: CircularProgressIndicator(color: VoxProTheme.accent));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Song Library', style: Theme.of(context).textTheme.headlineMedium),
              Row(
                children: [
                  Text(
                    service.currentDirectory!,
                    style: const TextStyle(color: VoxProTheme.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(_isListView ? Icons.grid_view : Icons.view_list),
                    onPressed: () {
                      setState(() {
                        _isListView = !_isListView;
                      });
                    },
                    tooltip: 'Toggle View',
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => service.scanDirectory(),
                    tooltip: 'Refresh Library',
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder_open),
                    onPressed: () => service.pickDirectory(),
                    tooltip: 'Change Directory',
                  ),
                ],
              )
            ],
          ),
        ),
        Expanded(
          child: _isListView
              ? ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  itemCount: service.songs.length,
                  itemBuilder: (context, index) {
                    final song = service.songs[index];
                    return Card(
                      color: VoxProTheme.cardBg,
                      margin: const EdgeInsets.only(bottom: 8.0),
                      child: ListTile(
                        title: Text(song.title, style: const TextStyle(fontWeight: FontWeight.bold, color: VoxProTheme.textPrimary)),
                        subtitle: Wrap(
                          spacing: 4.0,
                          children: [
                            _buildComponentChip(context, song.id, 'Inst', 'instrumental', song.hasInstrumental),
                            const Text('|', style: const TextStyle(color: VoxProTheme.textSecondary, fontSize: 12)),
                            _buildComponentChip(context, song.id, 'Vocals', 'vocals', song.hasVocals),
                            const Text('|', style: const TextStyle(color: VoxProTheme.textSecondary, fontSize: 12)),
                            _buildComponentChip(context, song.id, 'Pitch', 'pitch', song.hasPitchProfile),
                            const Text('|', style: const TextStyle(color: VoxProTheme.textSecondary, fontSize: 12)),
                            _buildComponentChip(context, song.id, 'Map', 'map', song.hasVocalMap),
                            const Text('|', style: const TextStyle(color: VoxProTheme.textSecondary, fontSize: 12)),
                            _buildComponentChip(context, song.id, 'Lyrics', 'lyrics', song.hasNativeLyrics || song.hasEnglishLyrics),
                          ],
                        ),
                        trailing: const Icon(Icons.play_circle_fill, color: VoxProTheme.accent),
                        onTap: () {
                          setState(() {
                            _selectedSong = song;
                            _selectedIndex = 1;
                          });
                        },
                      ),
                    );
                  },
                )
              : GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.8,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: service.songs.length,
                  itemBuilder: (context, index) {
                    final song = service.songs[index];
                    return SongCard(
                      song: song,
                      onTap: () {
                        setState(() {
                          _selectedSong = song;
                          _selectedIndex = 1;
                        });
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<FileExplorerService>();
    
    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(),
          const VerticalDivider(width: 1, color: VoxProTheme.border),
          Expanded(
            child: _selectedIndex == 1 
                ? ActiveSessionScreen(selectedSong: _selectedSong)
                : _buildLibraryView(service),
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 0 ? FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateSongScreen()),
          );
        },
        backgroundColor: VoxProTheme.vocalAccent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Create Song", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ) : null,
    );
  }
}
