import sqlite3
import os
import shutil

def main():
    print("===========================================")
    print("     AI Vault Database Rebuild Tool        ")
    print("===========================================")

    ai_vault_path = r"G:\My Drive\MyMusic\Music_AI_Vault"
    db_path = os.path.join(ai_vault_path, "vox_ai_metadata.db")

    if os.path.exists(db_path):
        try:
            conn = sqlite3.connect(db_path)
            conn.execute("SELECT 1 FROM ai_artifacts LIMIT 1")
            conn.close()
            print("[INFO] Existing DB seems ok, but we will rebuild it anyway.")
            # Backup old db just in case
            shutil.move(db_path, db_path + ".bak")
        except sqlite3.DatabaseError:
            print("[WARN] Existing DB is corrupted! Moving it to .corrupt")
            shutil.move(db_path, db_path + ".corrupt")

    # Create new DB
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute('''
        CREATE TABLE IF NOT EXISTS ai_artifacts (
            mm_id TEXT PRIMARY KEY,
            title TEXT,
            has_vocals INTEGER DEFAULT 0,
            has_instrumental INTEGER DEFAULT 0,
            has_pitch_data INTEGER DEFAULT 0,
            has_vocal_map INTEGER DEFAULT 0,
            has_lyrics INTEGER DEFAULT 0,
            last_processed TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Scan directories
    rebuilt_count = 0
    for item in os.listdir(ai_vault_path):
        dir_path = os.path.join(ai_vault_path, item)
        if os.path.isdir(dir_path) and not item.startswith('.'):
            # Parse mm_id and title from folder name
            # Format: mmId_CleanTitle or just mmId
            parts = item.split('_', 1)
            mm_id = parts[0]
            title = parts[1].replace('_', ' ') if len(parts) > 1 else mm_id

            has_inst, has_voc, has_pitch, has_map, has_lyr = 0, 0, 0, 0, 0

            for f in os.listdir(dir_path):
                f_lower = f.lower()
                if 'instrumental' in f_lower: has_inst = 1
                if 'vocals' in f_lower: has_voc = 1
                if 'pitch_profile' in f_lower: has_pitch = 1
                if 'vocal_map' in f_lower: has_map = 1
                if 'lyrics' in f_lower: has_lyr = 1

            c.execute('''
                INSERT INTO ai_artifacts (mm_id, title, has_vocals, has_instrumental, has_pitch_data, has_vocal_map, has_lyrics)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ''', (mm_id, title, has_voc, has_inst, has_pitch, has_map, has_lyr))
            
            print(f"[OK] Rebuilt record for: {title} (ID: {mm_id})")
            rebuilt_count += 1

    conn.commit()
    conn.close()
    
    print(f"\n[DONE] Successfully rebuilt database with {rebuilt_count} songs.")

if __name__ == "__main__":
    main()
