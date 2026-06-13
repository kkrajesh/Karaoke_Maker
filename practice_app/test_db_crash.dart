import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:vox_player_core/vox_player_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Test DB', (WidgetTester tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});

    try {
      await VoxSettingsService.instance.reload();
      final results = await VoxAiTrackingService.instance.getAllArtifacts();
      print("Success. Found ${results.length} artifacts.");
    } catch (e, st) {
      print("ERROR: $e\n$st");
    }
  });
}
