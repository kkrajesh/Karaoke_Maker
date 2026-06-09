import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/file_explorer_service.dart';
import '../theme/voxpro_theme.dart';
import '../../models/song.dart';
import 'active_session_screen.dart';
import 'settings_screen.dart';
import '../widgets/song_card.dart';
import '../widgets/song_list_tile.dart';
import 'package:vox_player_core/vox_player_core.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  Song? _selectedSong;
  bool _isListView = true;
  String _searchQuery = '';
  
  bool _isSidebarOpen = false;
  bool _priorWideState = true;
  bool? _wasWide;
  bool? _filterVocals;
  bool? _filterInst;
  bool? _filterPitch;
  bool? _filterMap;
  bool? _filterLyrics;
  bool? _filterProfile;

  @override
  void initState() {
    super.initState();
    _requestAndroidPermissions();
  }

  Future<void> _requestAndroidPermissions() async {
    if (Platform.isAndroid) {
      if (!await Permission.manageExternalStorage.isGranted) {
        await Permission.manageExternalStorage.request();
      }
      if (!await Permission.storage.isGranted) {
        await Permission.storage.request();
      }
      if (!await Permission.microphone.isGranted) {
        await Permission.microphone.request();
      }
      
      // Attempt a rescan now that we have permissions
      if (mounted) {
        final service = Provider.of<FileExplorerService>(context, listen: false);
        service.scanDirectory();
      }
    }
  }

  bool? _nextFilterState(bool? current) {
    if (current == null) return true;
    if (current == true) return false;
    return null;
  }

  Widget _buildTriStateChip(String label, bool? state, ValueChanged<bool?> onChanged, Color accentColor) {
    final isSelected = state != null;
    final isExclude = state == false;
    final activeColor = isExclude ? Colors.redAccent : accentColor;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onChanged(_nextFilterState(state)),
      selectedColor: activeColor.withValues(alpha: 0.3),
      checkmarkColor: activeColor,
      showCheckmark: false,
      avatar: isSelected ? Icon(isExclude ? Icons.block : Icons.check, color: activeColor, size: 18) : null,
      side: BorderSide(color: isSelected ? activeColor : VoxProTheme.border),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 250,
      color: VoxProTheme.sidebar,
      child: Column(
        children: [
          const SizedBox(height: 16),
          _buildSidebarItem(Icons.library_music, 'Library', 0),
          _buildSidebarItem(Icons.mic, 'Active Session', 1),
          const Spacer(),
          _buildSidebarItem(Icons.settings, 'Settings', 2, isDialog: true),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(IconData icon, String title, int index, {bool isDialog = false}) {
    final isActive = !isDialog && _selectedIndex == index;
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
        if (isDialog && index == 2) {
          showDialog(
            context: context,
            builder: (context) => const SettingsScreen(),
          );
          return;
        }
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
        return LayoutBuilder(
          builder: (context, constraints) {
            return AlertDialog(
              backgroundColor: VoxProTheme.cardBg,
              title: Text('Reprocess $label?', style: const TextStyle(color: VoxProTheme.accent)),
              content: component == 'lyrics'
                  ? Container(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'This will regenerate the English translation using your existing native lyrics. To completely replace them, you can paste new lyrics below or upload a local file. If no existing lyrics are found, it will scrape the web.',
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
                      final songTitle = service.songs.firstWhere((s) => s.id == songId).title;
                      final taskId = await VoxApiService.reprocessComponent(
                        songId: songId,
                        title: songTitle,
                        component: component,
                        lyricsText: component == 'lyrics' && lyricsController.text.isNotEmpty ? lyricsController.text : null,
                      );
                      if (context.mounted) {
                        service.trackTask(taskId, songId, songTitle, ScaffoldMessenger.of(context));
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
          }
        );
      },
    );
  }

  void _showUnifiedSearch() {
    final service = Provider.of<FileExplorerService>(context, listen: false);
    final localPath = service.currentDirectory ?? 'C:\\'; // default if none selected

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: VoxProTheme.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 800,
            height: 600,
            padding: const EdgeInsets.all(16),
            child: UnifiedSearchUI(
              providers: [
                DartYouTubeSearchProvider(),
                MediaMonkeySearchProvider(prioritizeLocal: true),
              ],
              actionBuilder: (context, result) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AiQueueButton(result: result, isVisible: true),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: VoxProTheme.vocalAccent),
                      onPressed: () {
                        Navigator.pop(context); // close dialog
                        if (result.sourceType != 'youtube') {
                          final foundSong = service.songs.firstWhere(
                            (s) => result.url != null && result.url!.startsWith(s.directoryPath),
                            orElse: () => Song(title: result.title, directoryPath: result.url ?? ''),
                          );
                          setState(() {
                            _selectedSong = foundSong;
                            _selectedIndex = 1;
                          });
                        } else {
                           setState(() {
                             final url = result.url ?? '';
                             final ytId = RegExp(r'(?:v=|/)([0-9A-Za-z_-]{11}).*').firstMatch(url)?.group(1) ?? '';
                             _selectedSong = Song(title: result.title, directoryPath: url, mmId: ytId.isNotEmpty ? 'YT_$ytId' : null);
                             _selectedIndex = 1;
                           });
                        }
                      },
                      child: const Text('Play', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
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
          child: Column(
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Song Library', style: Theme.of(context).textTheme.headlineMedium),
                    ],
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Text(
                        service.currentDirectory!,
                        style: const TextStyle(color: VoxProTheme.textSecondary, fontSize: 12),
                      ),
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
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                style: const TextStyle(color: VoxProTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Quick search songs...',
                  hintStyle: TextStyle(color: VoxProTheme.textSecondary),
                  prefixIcon: Icon(Icons.search, color: VoxProTheme.textSecondary),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: VoxProTheme.border)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: VoxProTheme.accent)),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8.0,
                runSpacing: 4.0,
                children: [
                  _buildTriStateChip('Vocals', _filterVocals, (v) => setState(() => _filterVocals = v), VoxProTheme.vocalAccent),
                  _buildTriStateChip('Instrumental', _filterInst, (v) => setState(() => _filterInst = v), VoxProTheme.instAccent),
                  _buildTriStateChip('Pitch', _filterPitch, (v) => setState(() => _filterPitch = v), VoxProTheme.pitchAccent),
                  _buildTriStateChip('Map', _filterMap, (v) => setState(() => _filterMap = v), VoxProTheme.mapAccent),
                  _buildTriStateChip('Lyrics', _filterLyrics, (v) => setState(() => _filterLyrics = v), VoxProTheme.lyricsAccent),
                  _buildTriStateChip('Profile', _filterProfile, (v) => setState(() => _filterProfile = v), VoxProTheme.accent),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Builder(builder: (context) {
            var filteredSongs = _searchQuery.isEmpty 
                ? service.songs 
                : service.songs.where((s) => s.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
            
            if (_filterVocals == true) filteredSongs = filteredSongs.where((s) => s.hasVocals).toList();
            if (_filterVocals == false) filteredSongs = filteredSongs.where((s) => !s.hasVocals).toList();
            
            if (_filterInst == true) filteredSongs = filteredSongs.where((s) => s.hasInstrumental).toList();
            if (_filterInst == false) filteredSongs = filteredSongs.where((s) => !s.hasInstrumental).toList();
            
            if (_filterPitch == true) filteredSongs = filteredSongs.where((s) => s.hasPitchProfile).toList();
            if (_filterPitch == false) filteredSongs = filteredSongs.where((s) => !s.hasPitchProfile).toList();
            
            if (_filterMap == true) filteredSongs = filteredSongs.where((s) => s.hasVocalMap).toList();
            if (_filterMap == false) filteredSongs = filteredSongs.where((s) => !s.hasVocalMap).toList();
            
            if (_filterLyrics == true) filteredSongs = filteredSongs.where((s) => s.hasEnglishLyrics || s.hasNativeLyrics).toList();
            if (_filterLyrics == false) filteredSongs = filteredSongs.where((s) => !(s.hasEnglishLyrics || s.hasNativeLyrics)).toList();
            
            if (_filterProfile == true) filteredSongs = filteredSongs.where((s) => s.hasPerformanceProfile).toList();
            if (_filterProfile == false) filteredSongs = filteredSongs.where((s) => !s.hasPerformanceProfile).toList();
                
            if (filteredSongs.isEmpty) {
              return const Center(child: Text('No songs found', style: TextStyle(color: VoxProTheme.textSecondary)));
            }
            
            Widget listWidget = _isListView
                ? ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    itemCount: filteredSongs.length,
                    itemBuilder: (context, index) {
                      final song = filteredSongs[index];
                      return SongListTile(
                        song: song,
                        onTap: () {
                          setState(() {
                            _selectedSong = song;
                            _selectedIndex = 1;
                          });
                        },
                        onReprocess: _showReprocessDialog,
                        onRemove: () => service.removeFromLibrary(song.id),
                      );
                    },
                  )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        int crossAxisCount = 3;
                        if (constraints.maxWidth < 600) crossAxisCount = 1;
                        else if (constraints.maxWidth < 1000) crossAxisCount = 2;
                        else if (constraints.maxWidth > 1400) crossAxisCount = 4;
                        
                        return GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            childAspectRatio: 0.8,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                          itemCount: filteredSongs.length,
                          itemBuilder: (context, index) {
                            final song = filteredSongs[index];
                            return SongCard(
                              song: song,
                              onTap: () {
                                setState(() {
                                  _selectedSong = song;
                                  _selectedIndex = 1;
                                });
                              },
                              onRemove: () => service.removeFromLibrary(song.id),
                              onReprocess: _showReprocessDialog,
                            );
                          },
                        );
                      },
                    );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 24.0, right: 24.0, bottom: 8.0),
                  child: Text(
                    '${filteredSongs.length} songs found',
                    style: const TextStyle(color: VoxProTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(child: listWidget),
              ],
            );
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<FileExplorerService>();
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;
    
    if (_wasWide == null) {
      _isSidebarOpen = isWide;
    } else {
      if (_wasWide! && !isWide) {
        _isSidebarOpen = false;
      } else if (!_wasWide! && isWide) {
        _isSidebarOpen = _priorWideState;
      }
    }
    _wasWide = isWide;
    
    return AiQueueNotificationListener(
      child: Scaffold(
        appBar: AppBar(
        backgroundColor: VoxProTheme.sidebar,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          color: VoxProTheme.textPrimary,
          onPressed: () {
            setState(() {
              _isSidebarOpen = !_isSidebarOpen;
              if (isWide) {
                _priorWideState = _isSidebarOpen;
              }
            });
          },
          tooltip: 'Toggle Sidebar',
        ),
        title: const Text(
          'KARAOKE MAKER',
          style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold, color: VoxProTheme.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showUnifiedSearch,
            tooltip: 'Global Search',
          ),
          const AiQueueStatusIcon(),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        child: Row(
          children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _isSidebarOpen ? _buildSidebar() : const SizedBox.shrink(),
          ),
          if (_isSidebarOpen) const VerticalDivider(width: 1, color: VoxProTheme.border),
          Expanded(
            child: _selectedIndex == 1 
                ? ActiveSessionScreen(
                    selectedSong: _selectedSong,
                    onSongSwitched: (newSong) {
                      setState(() {
                        _selectedSong = newSong;
                      });
                    },
                  )
                : _buildLibraryView(service),
          ),
        ],
      )),
      floatingActionButton: _selectedIndex == 0 ? (screenWidth < 600 ? FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateSongScreen()),
          );
        },
        backgroundColor: VoxProTheme.vocalAccent,
        child: const Icon(Icons.add, color: Colors.white),
      ) : FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateSongScreen()),
          );
        },
        backgroundColor: VoxProTheme.vocalAccent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Create Song", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      )) : null,
    ));
  }
}
