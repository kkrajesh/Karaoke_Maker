import os
import shutil
import subprocess
import urllib.parse
import re
from pathlib import Path
from bs4 import BeautifulSoup
import requests
import yt_dlp
from .config import get_preferred_domains

def sanitize_filename(name):
    # Remove characters not allowed in Windows filenames
    return re.sub(r'[\\/*?:"<>|]', "", name).strip()

class MakerService:
    def __init__(self):
        self.domains = get_preferred_domains()
        self.hot_zone = os.getenv("ONEDRIVE_HOT_ZONE")
        self.ffmpeg_path = os.getenv("FFMPEG_PATH")
        
        if not self.hot_zone:
            raise ValueError("ONEDRIVE_HOT_ZONE is not configured.")

    def log(self, song_id, message):
        """Prints a message and logs it to a local debug.log file in the song's directory."""
        print(message)
        if song_id:
            target_dir = os.path.join(self.hot_zone, song_id)
            if os.path.exists(target_dir):
                log_file = os.path.join(target_dir, "debug.log")
                with open(log_file, "a", encoding="utf-8") as f:
                    # adding a simple timestamp or just appending
                    import datetime
                    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    f.write(f"[{timestamp}] {message}\n")

    def embed_metadata(self, filepath, source_url):
        """Uses FFmpeg to embed the source URL into the audio file's metadata."""
        if not os.path.exists(filepath) or not source_url:
            return
            
        temp_file = filepath + ".temp.wav"
        shutil.move(filepath, temp_file)
        
        cmd = [
            self.ffmpeg_path,
            "-y",
            "-i", temp_file,
            "-metadata", f"comment=Source URL: {source_url}",
            "-codec", "copy",
            filepath
        ]
        try:
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            os.remove(temp_file)
        except Exception as e:
            # Revert if failed
            if os.path.exists(temp_file):
                shutil.move(temp_file, filepath)
            print(f"[ERROR] Failed to embed metadata in {filepath}: {e}")

    def search_duckduckgo(self, query, domain):
        """Perform a DuckDuckGo HTML search restricted to a specific domain."""
        url = f"https://html.duckduckgo.com/html/?q=site:{domain}+{urllib.parse.quote(query)}"
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        }
        try:
            response = requests.get(url, headers=headers, timeout=10)
            if response.status_code == 200:
                soup = BeautifulSoup(response.text, 'html.parser')
                # Find the first real result link
                for a in soup.find_all('a', class_='result__url'):
                    href = a.get('href')
                    if href and domain in href:
                        return href.strip()
        except Exception as e:
            print(f"[ERROR] Failed to search {domain}: {e}")
        return None

    def search_and_download_audio(self, song_query):
        """Searches for the song on preferred domains, falls back to YouTube, and downloads it."""
        # Clean up song_id to be a valid folder name
        song_id = sanitize_filename(song_query).replace(" ", "_")
        target_dir = os.path.join(self.hot_zone, song_id)
        os.makedirs(target_dir, exist_ok=True)
        
        target_mp3 = os.path.join(target_dir, "original.wav")
        
        # If input is already a direct URL
        if song_query.startswith("http://") or song_query.startswith("https://"):
            download_url = song_query
            self.log(song_id, f"[INFO] Using direct URL: {download_url}")
        else:
            download_url = None
            # Search the configurable preferred domains first
            for domain in self.domains:
                self.log(song_id, f"[WAIT] Searching '{song_query}' on {domain}...")
                found_url = self.search_duckduckgo(song_query, domain)
                if found_url:
                    if not found_url.startswith("http"):
                        found_url = "https://" + found_url
                    self.log(song_id, f"[OK] Found match on {domain}: {found_url}")
                    download_url = found_url
                    break
            
            # Fallback to YouTube if nothing was found
            if not download_url:
                self.log(song_id, f"[INFO] No results found on preferred domains. Falling back to YouTube search...")
                download_url = f"ytsearch1:{song_query}"
        
        # yt-dlp Configuration
        ydl_opts = {
            'format': 'bestaudio/best',
            'outtmpl': os.path.join(target_dir, 'original.%(ext)s'),
            'postprocessors': [{
                'key': 'FFmpegExtractAudio',
                'preferredcodec': 'wav',
            }],
            'ffmpeg_location': self.ffmpeg_path,
            'quiet': False,
            'no_warnings': True
        }
        
        self.log(song_id, f"[WAIT] Downloading audio from: {download_url}...")
        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info_dict = ydl.extract_info(download_url, download=True)
                
                # Extract the actual webpage URL from yt-dlp info (useful if it was a ytsearch)
                actual_url = download_url
                if 'entries' in info_dict and len(info_dict['entries']) > 0:
                    actual_url = info_dict['entries'][0].get('webpage_url', download_url)
                elif 'webpage_url' in info_dict:
                    actual_url = info_dict.get('webpage_url', download_url)
            
            if os.path.exists(target_mp3):
                self.log(song_id, f"[OK] Successfully downloaded original audio to {target_mp3}")
                self.log(song_id, f"[INFO] Embedding metadata for original.wav (Source: {actual_url})")
                self.embed_metadata(target_mp3, actual_url)
                return song_id, actual_url
            else:
                self.log(song_id, f"[ERROR] Download failed, original.wav not found.")
                return None, None
        except Exception as e:
            self.log(song_id, f"[ERROR] yt-dlp extraction failed: {e}")
            return None, None

    def separate_audio(self, song_id, actual_url):
        """Uses Demucs to split the downloaded original.wav into vocals and instrumental."""
        target_dir = os.path.join(self.hot_zone, song_id)
        original_mp3 = os.path.join(target_dir, "original.wav")
        
        if not os.path.exists(original_mp3):
            self.log(song_id, f"[ERROR] original.wav not found for SongID: {song_id}")
            return False
            
        self.log(song_id, f"[WAIT] Starting Demucs separation for {song_id} (This may take a while)...")
        
        # Command to run our custom demucs wrapper that bypasses torchcodec
        run_demucs_script = os.path.join(os.path.dirname(__file__), "run_demucs.py")
        cmd = [
            "py",
            run_demucs_script,
            "--two-stems=vocals",
            "-o", target_dir,
            original_mp3
        ]
        
        try:
            subprocess.run(cmd, check=True)
            self.log(song_id, "[OK] Demucs separation completed.")
            
            # Demucs places outputs in target_dir/htdemucs/original/...
            demucs_out_dir = os.path.join(target_dir, "htdemucs", "original")
            vocals_wav = os.path.join(demucs_out_dir, "vocals.wav")
            instrumental_wav = os.path.join(demucs_out_dir, "no_vocals.wav")
            
            final_vocals = os.path.join(target_dir, "vocals.wav")
            final_instrumental = os.path.join(target_dir, "instrumental.wav")
            
            # Move the files to the root of the song's directory and embed metadata
            if os.path.exists(vocals_wav):
                shutil.move(vocals_wav, final_vocals)
                self.log(song_id, f"[OK] Created vocals.wav")
                self.embed_metadata(final_vocals, actual_url)
                
            if os.path.exists(instrumental_wav):
                shutil.move(instrumental_wav, final_instrumental)
                self.log(song_id, f"[OK] Created instrumental.wav")
                self.embed_metadata(final_instrumental, actual_url)
                
            # Cleanup the temporary htdemucs folder
            htdemucs_dir = os.path.join(target_dir, "htdemucs")
            if os.path.exists(htdemucs_dir):
                shutil.rmtree(htdemucs_dir, ignore_errors=True)
            
            return True
            
        except subprocess.CalledProcessError as e:
            self.log(song_id, f"[ERROR] Demucs subprocess failed: {e}")
            return False
        except Exception as e:
            self.log(song_id, f"[ERROR] Separation failed: {e}")
            return False

    def process_song(self, song_query, force_reprocess=False):
        """Main workflow: Search -> Download -> Separate."""
        print("=" * 40)
        print(f" Starting Processing: {song_query} ")
        print("=" * 40)
        
        # Check if already processed
        song_id_check = sanitize_filename(song_query).replace(" ", "_")
        target_dir = os.path.join(self.hot_zone, song_id_check)
        if not force_reprocess and os.path.exists(target_dir):
            if os.path.exists(os.path.join(target_dir, "vocals.wav")) and os.path.exists(os.path.join(target_dir, "instrumental.wav")):
                self.log(song_id_check, f"[INFO] '{song_query}' is already fully processed. Skipping.")
                return True
        elif force_reprocess:
            self.log(song_id_check, f"[INFO] Force re-processing enabled for '{song_query}'.")
        
        song_id, actual_url = self.search_and_download_audio(song_query)
        if not song_id:
            print("[ERROR] Processing aborted. Audio download failed.")
            return False
            
        success = self.separate_audio(song_id, actual_url)
        if success:
            self.log(song_id, f"\n[DONE] Successfully processed '{song_query}'.")
            self.log(song_id, f"       Files saved to: {os.path.join(self.hot_zone, song_id)}")
            return True
        else:
            self.log(song_id, "[ERROR] Processing failed during separation.")
            return False
