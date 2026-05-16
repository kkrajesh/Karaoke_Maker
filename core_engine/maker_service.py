import os
import shutil
import subprocess
import urllib.parse
import re
from pathlib import Path
from bs4 import BeautifulSoup
import yt_dlp
import concurrent.futures
import threading
from .config import get_preferred_domains
from .pitch_analyzer import PitchAnalyzer
from .agents.audio_agent import AudioAgent
from .agents.lyric_agent import LyricAgent

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
                results = soup.find_all('div', class_='result')
                for res in results:
                    a_tag = res.find('a', class_='result__url')
                    title_tag = res.find('h2', class_='result__title')
                    if a_tag and title_tag:
                        href = a_tag.get('href', '').strip()
                        if domain in href:
                            if not href.startswith("http"):
                                href = "https://" + href
                            return {"title": title_tag.text.strip(), "url": href}
        except Exception as e:
            print(f"[ERROR] Failed to search {domain}: {e}")
        return None

    def search_and_download_audio(self, song_query, target_dir):
        """Searches for the song, uses AudioAgent to pick the best, and downloads it."""
        song_id = os.path.basename(target_dir)
        
        target_mp3 = os.path.join(target_dir, "original.wav")
        
        # If input is already a direct URL
        if song_query.startswith("http://") or song_query.startswith("https://"):
            download_url = song_query
            self.log(song_id, f"[INFO] Using direct URL: {download_url}")
        else:
            search_results = []
            
            # 1. Search preferred domains
            for domain in self.domains:
                self.log(song_id, f"[WAIT] Searching '{song_query}' on {domain}...")
                res = self.search_duckduckgo(song_query, domain)
                if res:
                    search_results.append(res)
            
            # 2. Search YouTube (Top 3)
            self.log(song_id, f"[WAIT] Fetching top YouTube results...")
            ydl_opts_search = {'quiet': True, 'extract_flat': True}
            try:
                with yt_dlp.YoutubeDL(ydl_opts_search) as ydl:
                    info = ydl.extract_info(f"ytsearch3:{song_query}", download=False)
                    if 'entries' in info:
                        for entry in info['entries']:
                            search_results.append({
                                "title": entry.get('title', 'Unknown YouTube Video'),
                                "url": entry.get('url', entry.get('webpage_url', ''))
                            })
            except Exception as e:
                self.log(song_id, f"[WARN] YouTube search failed: {e}")
                
            # 3. Agentic Vetting
            self.log(song_id, f"[WAIT] AudioAgent is vetting {len(search_results)} results...")
            audio_agent = AudioAgent()
            best_url, reason = audio_agent.pick_best_source(song_query, search_results)
            
            if not best_url:
                self.log(song_id, "[ERROR] AudioAgent failed to find a valid source.")
                return None, None
                
            self.log(song_id, f"[OK] AudioAgent chose: {best_url}")
            self.log(song_id, f"     Reason: {reason}")
            download_url = best_url
        
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
        """Uses Demucs to split the downloaded original.wav into vocals and instrumental, then runs Pitch Analysis."""
        target_dir = os.path.join(self.hot_zone, song_id)
        original_mp3 = os.path.join(target_dir, "original.wav")
        final_vocals = os.path.join(target_dir, "vocals.wav")
        final_instrumental = os.path.join(target_dir, "instrumental.wav")
        pitch_json_path = os.path.join(target_dir, "pitch_profile.json")
        
        # --- 1. Demucs Separation ---
        if not (os.path.exists(final_vocals) and os.path.exists(final_instrumental)):
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
                    
            except subprocess.CalledProcessError as e:
                self.log(song_id, f"[ERROR] Demucs subprocess failed: {e}")
                return False
            except Exception as e:
                self.log(song_id, f"[ERROR] Separation failed: {e}")
                return False
        else:
            self.log(song_id, f"[INFO] vocals.wav and instrumental.wav already exist. Skipping Demucs separation.")
            
        # --- 2. Pitch Analysis (Phase 2) ---
        if os.path.exists(final_vocals) and not os.path.exists(pitch_json_path):
            self.log(song_id, f"[WAIT] Starting Pitch Analysis on vocals.wav...")
            try:
                analyzer = PitchAnalyzer(fps=50)
                analyzer.analyze(final_vocals, pitch_json_path)
            except Exception as e:
                self.log(song_id, f"[ERROR] PitchAnalyzer failed: {e}")
                return False
        elif os.path.exists(pitch_json_path):
            self.log(song_id, f"[INFO] pitch_profile.json already exists. Skipping Pitch Analysis.")
            
        return True

    def process_song(self, song_query, force_reprocess=False):
        """Main workflow: Search -> Download -> Separate."""
        print("=" * 40)
        print(f" Starting Processing: {song_query} ")
        print("=" * 40)
        
        # Check if already processed
        song_id_check = sanitize_filename(song_query).replace(" ", "_")
        target_dir = os.path.join(self.hot_zone, song_id_check)
        os.makedirs(target_dir, exist_ok=True)
        
        if not force_reprocess and os.path.exists(target_dir):
            if (os.path.exists(os.path.join(target_dir, "vocals.wav")) and 
                os.path.exists(os.path.join(target_dir, "instrumental.wav")) and
                os.path.exists(os.path.join(target_dir, "pitch_profile.json"))):
                self.log(song_id_check, f"[INFO] '{song_query}' is already fully processed. Skipping.")
                return True
        elif force_reprocess:
            self.log(song_id_check, f"[INFO] Force re-processing enabled for '{song_query}'.")
        
        # We can fire the LyricAgent in a separate thread for concurrency within the song processing
        lyric_thread = threading.Thread(target=self._fetch_lyrics, args=(song_id_check, song_query, target_dir))
        lyric_thread.start()
        
        song_id, actual_url = self.search_and_download_audio(song_query, target_dir)
        if not song_id:
            print("[ERROR] Processing aborted. Audio download failed.")
            lyric_thread.join()
            return False
            
        success = self.separate_audio(song_id, actual_url)
        lyric_thread.join() # Ensure lyrics are done before we declare total success
        
        if success:
            self.log(song_id, f"\n[DONE] Successfully processed '{song_query}'.")
            self.log(song_id, f"       Files saved to: {target_dir}")
            return True
        else:
            self.log(song_id, "[ERROR] Processing failed during separation.")
            return False

    def _fetch_lyrics(self, song_id, song_query, target_dir):
        """Helper to run LyricAgent."""
        def lyric_logger(msg):
            self.log(song_id, msg)
            
        try:
            agent = LyricAgent()
            agent.fetch_and_save(song_query, target_dir, log_callback=lyric_logger)
        except Exception as e:
            self.log(song_id, f"[WARN] Lyric thread failed: {e}")

    def process_batch(self, song_queries, max_workers=2, force_reprocess=False):
        """Processes a list of songs concurrently using a ThreadPoolExecutor."""
        self.log(None, f"\n=== Starting Batch Processing for {len(song_queries)} songs ===")
        
        # We use max_workers=2 by default so one thread can download while the other is running Demucs
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = {executor.submit(self.process_song, q, force_reprocess): q for q in song_queries}
            
            for future in concurrent.futures.as_completed(futures):
                query = futures[future]
                try:
                    success = future.result()
                    if success:
                        self.log(None, f"[BATCH OK] Finished: {query}")
                    else:
                        self.log(None, f"[BATCH ERROR] Failed: {query}")
                except Exception as e:
                    self.log(None, f"[BATCH EXCEPTION] Error processing '{query}': {e}")
        
        self.log(None, f"=== Batch Processing Complete ===\n")
