import sqlite3
import os
import re

DB_PATH = r'E:\Data\Rajesh\MyMusic\Music_AI_Vault\vox_ai_metadata.db'
conn = sqlite3.connect(DB_PATH)
c = conn.cursor()

c.execute("SELECT mm_id, title FROM ai_artifacts WHERE mm_id LIKE 'Kannadi_Koodum_Kootti%'")
row = c.fetchone()
if row:
    mm_id, title = row
    clean_title = 'Kannadi Koodum Kootti'
    
    # Update DB
    c.execute("UPDATE ai_artifacts SET title = ? WHERE mm_id = ?", (clean_title, mm_id))
    conn.commit()
    print('Updated DB title to:', clean_title)

    # Rename the folder and files
    vault = r'E:\Data\Rajesh\MyMusic\Music_AI_Vault'
    
    # Find existing folder
    old_folder = None
    for d in os.listdir(vault):
        if d.startswith(mm_id):
            old_folder = os.path.join(vault, d)
            break
            
    if old_folder and os.path.isdir(old_folder):
        def sanitize_title(t): return re.sub(r'[\\/:*?"<>|]', '', t)
        clean_title_str = sanitize_title(clean_title)
        
        # New folder path
        new_folder_name = mm_id if mm_id == clean_title_str else f'{mm_id}_{clean_title_str}'
        new_folder = os.path.join(vault, new_folder_name)
        
        # Rename files inside first
        prefix = new_folder_name
        for f in os.listdir(old_folder):
            if f.endswith('.wav') or f.endswith('.json') or f.endswith('.txt') or f.endswith('.log'):
                parts = f.rsplit('_', 1)
                # Try to extract the true suffix (e.g., 'pitch_profile.json', 'vocal_map.json', etc)
                if f.endswith('pitch_profile.json'): suffix = 'pitch_profile.json'
                elif f.endswith('vocal_map.json'): suffix = 'vocal_map.json'
                elif f.endswith('lyrics_english.txt'): suffix = 'lyrics_english.txt'
                elif f.endswith('lyrics_native.txt'): suffix = 'lyrics_native.txt'
                elif f.endswith('lyrics_meaning.txt'): suffix = 'lyrics_meaning.txt'
                else: suffix = parts[-1]
                
                new_f = f'{prefix}_{suffix}'
                os.rename(os.path.join(old_folder, f), os.path.join(old_folder, new_f))
                    
        os.rename(old_folder, new_folder)
        print('Renamed folder and files to match clean title!')

conn.close()
