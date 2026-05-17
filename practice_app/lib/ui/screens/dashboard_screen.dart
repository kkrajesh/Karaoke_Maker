import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  Widget _buildLibraryView(FileExplorerService service) {
    if (service.currentDirectory == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_open, size: 64, color: VoxProTheme.textSecondary),
            const SizedBox(height: 16),
            const Text('No Output Directory Selected'),
            const SizedBox(height: 16),
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
          child: GridView.builder(
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
