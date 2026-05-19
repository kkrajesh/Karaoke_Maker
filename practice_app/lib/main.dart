import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/file_explorer_service.dart';
import 'ui/theme/voxpro_theme.dart';
import 'ui/screens/dashboard_screen.dart';

import 'services/settings_service.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FileExplorerService()),
        ChangeNotifierProvider(create: (_) => SettingsService()..loadSettings()),
      ],
      child: const KaraokePracticeApp(),
    ),
  );
}

class KaraokePracticeApp extends StatelessWidget {
  const KaraokePracticeApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Karaoke Practice Dashboard',
      theme: VoxProTheme.themeData,
      debugShowCheckedModeBanner: false,
      home: const DashboardScreen(),
    );
  }
}
