import 'package:sqlite3/sqlite3.dart';

void main() {
  final dbPath = r'G:\My Drive\MyMusic\Music_AI_Vault\vox_ai_metadata.db';
  final db = sqlite3.open(dbPath);
  final rows = db.select('SELECT mm_id, title FROM ai_artifacts LIMIT 50');
  for (var r in rows) {
    print(r);
  }
  db.dispose();
}
