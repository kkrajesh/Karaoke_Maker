import os
import sqlite3

AI_VAULT = r"G:\My Drive\MyMusic\Music_AI_Vault"
DB_PATH = os.path.join(AI_VAULT, "vox_ai_metadata.db")

def resync():
    if not os.path.exists(DB_PATH):
        print(f"Database not found at {DB_PATH}")
        return

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    c.execute("SELECT mm_id FROM ai_artifacts")
    rows = c.fetchall()
    
    updated = 0
    for row in rows:
        mm_id = str(row[0])
        folder_name = None
        for d in os.listdir(AI_VAULT):
            if os.path.isdir(os.path.join(AI_VAULT, d)) and (d == mm_id or d.startswith(f"{mm_id}_")):
                folder_name = d
                break
                
        if folder_name:
            vault_dir = os.path.join(AI_VAULT, folder_name)
            has_inst = has_voc = has_pitch = has_map = has_lyr = 0
            for filename in os.listdir(vault_dir):
                if "instrumental." in filename: has_inst = 1
                if "vocals." in filename: has_voc = 1
                if "pitch_profile.json" in filename: has_pitch = 1
                if "vocal_map.json" in filename: has_map = 1
                if "lyrics_native" in filename or "lyrics_english" in filename: has_lyr = 1
                
            c.execute('''
                UPDATE ai_artifacts 
                SET has_vocals=?, has_instrumental=?, has_pitch_data=?, has_vocal_map=?, has_lyrics=?
                WHERE mm_id=?
            ''', (has_voc, has_inst, has_pitch, has_map, has_lyr, mm_id))
            updated += 1

    conn.commit()
    conn.close()
    print(f"Resync complete. Updated {updated} rows based on actual files in {AI_VAULT}.")

if __name__ == "__main__":
    resync()
