import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vox_player_core/vox_player_core.dart';

void main() async {
  try {
    sqfliteFfiInit();
    var databaseFactory = databaseFactoryFfi;
    final dbPath = r'E:\Data\Rajesh\MyMusic\Music_AI_Vault\vox_ai_metadata.db';
    print("Opening DB at: $dbPath");
    final db = await databaseFactory.openDatabase(dbPath, options: OpenDatabaseOptions(readOnly: true));
    final rows = await db.query('ai_artifacts');
    print("Found ${rows.length} rows.");
  } catch (e, st) {
    print("ERROR: $e");
    print(st);
  }
}
