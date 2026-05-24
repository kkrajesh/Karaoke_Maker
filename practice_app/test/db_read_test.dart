import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart'; // Ensure it's imported just in case

void main() {
  test('Read Database', () async {
    sqfliteFfiInit();
    var databaseFactory = databaseFactoryFfi;
    final dbPath = r'E:\Data\Rajesh\MyMusic\Music_AI_Vault\vox_ai_metadata.db';
    print("Opening DB natively: $dbPath");
    
    final db = await databaseFactory.openDatabase(dbPath);
    final result = await db.query('ai_artifacts');
    print("Rows natively: ${result.length}");
    for (final row in result) {
      print(row);
    }
    await db.close();
  });
}
