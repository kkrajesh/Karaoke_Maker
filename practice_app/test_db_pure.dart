import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  try {
    sqfliteFfiInit();
    var databaseFactory = databaseFactoryFfi;
    final dbPath = r'E:\Data\Rajesh\MyMusic\Music_AI_Vault\vox_ai_metadata.db';
    print("Opening DB at: $dbPath");
    
    if (!File(dbPath).existsSync()) {
      print("FILE NOT FOUND!");
      return;
    }
    
    print("File size: ${File(dbPath).lengthSync()}");
    
    final db = await databaseFactory.openDatabase(
      dbPath, 
      options: OpenDatabaseOptions(
        readOnly: true,
      )
    );
    
    final rows = await db.query('ai_artifacts');
    print("Found ${rows.length} rows.");
    for (var r in rows) {
      print(r);
    }
    await db.close();
  } catch (e, st) {
    print("ERROR: $e");
    print(st);
  }
}
