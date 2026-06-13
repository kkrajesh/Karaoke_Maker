import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vox_player_core/vox_player_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('Test scanDirectory logic', (WidgetTester tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    await VoxSettingsService.instance.reload();

    try {
      final rows = await VoxAiTrackingService.instance.getAllArtifacts();
      print("Got ${rows.length} artifacts");
      final vaultPath = VoxSettingsService.instance.aiVaultPath;
      
      for (final row in rows) {
        final String mmId = row['mm_id']?.toString() ?? '';
        final String title = row['title']?.toString() ?? '';
        print("Parsing $mmId - $title");
        final actualDirPath = VoxAiTrackingService.instance.getArtifactDirectory(mmId, title);
        print("Dir path: $actualDirPath");
        
        // This is what Song.fromAiArtifact does
        // Just testing if PerformanceProfileService.hasProfileSync throws
        final hasProfile = PerformanceProfileService.hasProfileSync(actualDirPath);
        print("Has profile: $hasProfile");
      }
    } catch (e, st) {
      print("CRASHED: $e\n$st");
    }
  });
}
