import os
import sqlite3

vault_dir = r"E:\Data\Rajesh\MyMusic\Music_AI_Vault"
db_path = os.path.join(vault_dir, "vox_ai_metadata.db")

def migrate():
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    rows = cursor.execute('SELECT mm_id, title FROM ai_artifacts').fetchall()
    
    for mm_id, title in rows:
        # Reconstruct how the old Dart code generated the name
        clean_title_old = title.replace(' ', '_')
        if mm_id == clean_title_old or mm_id == title:
            old_prefix = mm_id
        else:
            old_prefix = f"{mm_id}_{clean_title_old}"
            
        # Reconstruct how the NEW Dart code generates the name
        clean_title_new = title
        if mm_id == clean_title_new or mm_id == title:
            new_prefix = mm_id
        else:
            new_prefix = f"{mm_id}_{clean_title_new}"
            
        if old_prefix != new_prefix:
            old_dir = os.path.join(vault_dir, old_prefix)
            new_dir = os.path.join(vault_dir, new_prefix)
            
            # If the old directory exists, rename it
            if os.path.exists(old_dir):
                print(f"Renaming folder: {old_prefix} -> {new_prefix}")
                os.rename(old_dir, new_dir)
                
            # Now, inside the NEW directory, rename the files to match the new prefix
            if os.path.exists(new_dir):
                for f in os.listdir(new_dir):
                    if f.startswith(old_prefix + "_") or f.startswith(old_prefix + "."):
                        old_file = os.path.join(new_dir, f)
                        # Replace the prefix at the start of the string
                        new_f = f.replace(old_prefix, new_prefix, 1)
                        new_file = os.path.join(new_dir, new_f)
                        if old_file != new_file:
                            print(f"  Renaming file: {f} -> {new_f}")
                            os.rename(old_file, new_file)

    conn.close()
    print("Migration complete!")

if __name__ == "__main__":
    migrate()
