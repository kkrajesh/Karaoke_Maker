import os
import sqlite3
import shutil
from datetime import datetime

hotzone_dir = r"C:\Data\Rajesh\Karaoke_HotZone"
vault_dir = r"E:\Data\Rajesh\MyMusic\Music_AI_Vault"
db_path = os.path.join(vault_dir, "vox_ai_metadata.db")

songs_to_recover = [
    {
        "old_folder": "Malare_Ninne_Kanathirunnal_Nenjiley",
        "clean_id": "Malare Ninne Kanathirunnal Nenjiley",
        "clean_title": "Malare Ninne Kanathirunnal Nenjiley"
    },
    {
        "old_folder": "Koi_Kahe_Kehta_Rahe_Dil_Chahta_Hai",
        "clean_id": "Dil Chahta Hai",
        "clean_title": "Dil Chahta Hai"
    },
    {
        "old_folder": "Minnalvala_Narivetta_Minnalvala",
        "clean_id": "Minnalvala Narivetta Minnalvala",
        "clean_title": "Minnalvala Narivetta Minnalvala"
    }
]

def recover_songs():
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    for song in songs_to_recover:
        source = os.path.join(hotzone_dir, song["old_folder"])
        if not os.path.exists(source):
            print(f"Skipping {song['old_folder']} - Not found in HotZone")
            continue

        dest_folder = song["clean_id"]
        dest = os.path.join(vault_dir, dest_folder)
        os.makedirs(dest, exist_ok=True)

        has_vocals = 0
        has_instrumental = 0
        has_pitch = 0
        has_map = 0
        has_lyrics = 0

        print(f"Copying files for {song['clean_title']}...")
        for file in os.listdir(source):
            src_file = os.path.join(source, file)
            if not os.path.isfile(src_file):
                continue
            
            # Use cleansed prefix
            prefix = f"{song['clean_id']}_"
            new_file_name = file if file.startswith(prefix) else f"{prefix}{file}"
            dest_file = os.path.join(dest, new_file_name)
            
            shutil.copy2(src_file, dest_file)

            if "vocals.wav" in file: has_vocals = 1
            if "instrumental.wav" in file: has_instrumental = 1
            if "pitch_profile.json" in file: has_pitch = 1
            if "vocal_map.json" in file: has_map = 1
            if "lyrics" in file: has_lyrics = 1

        # Insert into DB
        cursor.execute('''
            INSERT OR REPLACE INTO ai_artifacts 
            (mm_id, title, has_vocals, has_instrumental, has_pitch_data, has_vocal_map, has_lyrics, last_processed)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (song["clean_id"], song["clean_title"], has_vocals, has_instrumental, has_pitch, has_map, has_lyrics, datetime.now().isoformat()))
        
        conn.commit()
        print(f"Successfully ingested {song['clean_title']} into AI Vault!")
        
        # Cleanup HotZone
        shutil.rmtree(source)

    conn.close()

if __name__ == "__main__":
    recover_songs()
