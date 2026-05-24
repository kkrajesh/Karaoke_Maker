import sqlite3
import os
import re
import shutil

def sanitize_title(title):
    # Matches dart sanitizeTitle: title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').replaceAll(' ', '_')
    clean = re.sub(r'[\\/:*?"<>|]', '', title)
    clean = clean.replace(' ', '_')
    return clean

def main():
    print("===========================================")
    print("     Orphaned AI Vault Migration Tool      ")
    print("===========================================")

    # Hardcoded paths based on settings
    ai_metadata_db_path = r"E:\Data\Rajesh\MyMusic\Music_AI_Vault\vox_ai_metadata.db"
    mm_db_path = r"C:\Data\Rajesh\PortableApps\MediaMonkey\MediaMonkey4\Portable\MM.DB"
    ai_vault_path = r"E:\Data\Rajesh\MyMusic\Music_AI_Vault"

    if not os.path.exists(ai_metadata_db_path):
        print(f"[ERROR] Cannot find AI Metadata DB at {ai_metadata_db_path}")
        return
    
    if not os.path.exists(mm_db_path):
        print(f"[ERROR] Cannot find MediaMonkey DB at {mm_db_path}")
        return

    # Connect to databases
    ai_conn = sqlite3.connect(ai_metadata_db_path)
    mm_conn = sqlite3.connect(mm_db_path)

    ai_cursor = ai_conn.cursor()
    mm_cursor = mm_conn.cursor()

    # Find all artifacts where mm_id is not just a number
    ai_cursor.execute("SELECT mm_id, title FROM ai_artifacts")
    artifacts = ai_cursor.fetchall()

    orphans = []
    for mm_id, title in artifacts:
        # Check if mm_id is entirely numeric
        if not str(mm_id).isdigit():
            orphans.append((mm_id, title))

    if not orphans:
        print("[INFO] No orphaned artifacts found. Everything looks correct!")
        return

    print(f"[INFO] Found {len(orphans)} orphaned artifacts to migrate.\n")

    migrated_count = 0

    for old_mm_id, title in orphans:
        print(f"Processing '{old_mm_id}'...")
        
        # 1. Try to find the song in MediaMonkey DB
        search_title = old_mm_id.replace("_", " ")
        if len(search_title) > 20:
            search_title = search_title[:20]  # Just use first 20 chars for wider match
            
        search_pattern = f"%{search_title}%"
        
        # Exclude items that are already in the AI Vault or have vocals/instrumental in title
        mm_cursor.execute("SELECT ID, SongTitle FROM Songs WHERE SongTitle LIKE ? AND SongPath NOT LIKE '%AI_Vault%' AND SongTitle NOT LIKE '%vocals%' AND SongTitle NOT LIKE '%instrumental%'", (search_pattern,))
        matches = mm_cursor.fetchall()

        # If multiple, try to find exact match
        if len(matches) > 1:
            exact = [m for m in matches if m[1].lower() == search_title.lower()]
            if len(exact) == 1:
                matches = exact

        if len(matches) == 0:
            print(f"  -> [WARN] No match found in MediaMonkey for '{search_title}'. Skipping.")
            continue
        elif len(matches) > 1:
            print(f"  -> [WARN] Multiple matches found in MediaMonkey for '{search_title}'. Skipping to avoid wrong link.")
            for m in matches:
                print(f"     Option: ID={m[0]}, Title={m[1]}")
            continue

        # Exactly 1 match!
        new_id = str(matches[0][0])
        mm_title = matches[0][1]
        
        print(f"  -> [MATCH] Found MediaMonkey ID: {new_id} ({mm_title})")

        # 2. Calculate paths
        clean_title = sanitize_title(mm_title)
        
        # In dart: if mmId == cleanTitle -> just mmId, else mmId_cleanTitle
        if new_id == clean_title:
            new_prefix = new_id
        else:
            new_prefix = f"{new_id}_{clean_title}"
            
        old_dir = os.path.join(ai_vault_path, old_mm_id)
        new_dir = os.path.join(ai_vault_path, new_prefix)

        # 3. Rename Directory
        if not os.path.exists(old_dir):
            print(f"  -> [WARN] Directory {old_dir} does not exist. Updating DB only.")
        else:
            if os.path.exists(new_dir) and old_dir != new_dir:
                print(f"  -> [WARN] Target directory {new_dir} already exists! Skipping folder rename.")
            else:
                try:
                    os.rename(old_dir, new_dir)
                    print(f"  -> [OK] Renamed folder to {new_prefix}")
                except Exception as e:
                    print(f"  -> [ERROR] Failed to rename folder: {e}")
                    continue

        # 4. Rename Files inside Directory
        if os.path.exists(new_dir):
            for filename in os.listdir(new_dir):
                if filename.startswith(old_mm_id):
                    # Replace the prefix
                    new_filename = filename.replace(old_mm_id, new_prefix, 1)
                    old_filepath = os.path.join(new_dir, filename)
                    new_filepath = os.path.join(new_dir, new_filename)
                    try:
                        os.rename(old_filepath, new_filepath)
                        print(f"  -> [OK] Renamed file to {new_filename}")
                    except Exception as e:
                        print(f"  -> [ERROR] Failed to rename file {filename}: {e}")

        # 5. Update Database
        try:
            # We also update the title to match MediaMonkey perfectly
            ai_cursor.execute("UPDATE ai_artifacts SET mm_id = ?, title = ? WHERE mm_id = ?", (new_id, mm_title, old_mm_id))
            ai_conn.commit()
            print(f"  -> [OK] Updated Database record.")
            migrated_count += 1
        except Exception as e:
            print(f"  -> [ERROR] Failed to update Database: {e}")

    print(f"\n[DONE] Successfully migrated {migrated_count} out of {len(orphans)} orphans.")
    
    ai_conn.close()
    mm_conn.close()

if __name__ == "__main__":
    main()
