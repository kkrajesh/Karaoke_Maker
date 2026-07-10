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
import requests
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
        self.hot_zone = os.getenv("AI_HOTZONE")
        self.ffmpeg_path = os.getenv("FFMPEG_PATH")
        
        if not self.hot_zone:
            raise ValueError("AI_HOTZONE is not configured.")

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

    def get_search_results(self, song_query):
        """Returns a list of search results, with the AudioAgent's top pick indicated."""
        search_results = []
        
        # 1. Search preferred domains
        for domain in self.domains:
            res = self.search_duckduckgo(song_query, domain)
            if res:
                search_results.append(res)
        
        # 2. Search YouTube (Top 3)
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
            print(f"[WARN] YouTube search failed: {e}")
            
        # 3. Agentic Vetting
        audio_agent = AudioAgent()
        best_url, reason = audio_agent.pick_best_source(song_query, search_results)
        
        # Mark the recommended one
        for res in search_results:
            if res['url'] == best_url:
                res['recommended'] = True
                res['reason'] = reason
            else:
                res['recommended'] = False
                
        return search_results

    def download_audio(self, download_url, target_dir, song_id, progress_callback=None):
        """Downloads audio from a specific URL."""
        if progress_callback: progress_callback("Downloading Audio...")
        target_mp3 = os.path.join(target_dir, "original.wav")
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
                actual_url = download_url
                if 'entries' in info_dict and len(info_dict['entries']) > 0:
                    actual_url = info_dict['entries'][0].get('webpage_url', download_url)
                elif 'webpage_url' in info_dict:
                    actual_url = info_dict.get('webpage_url', download_url)
            
            if os.path.exists(target_mp3):
                self.log(song_id, f"[OK] Successfully downloaded original audio to {target_mp3}")
                self.log(song_id, f"[INFO] Embedding metadata for original.wav (Source: {actual_url})")
                self.embed_metadata(target_mp3, actual_url)
                return True, actual_url
            else:
                self.log(song_id, f"[ERROR] Download failed, original.wav not found.")
                return False, None
        except Exception as e:
            self.log(song_id, f"[ERROR] yt-dlp extraction failed: {e}")
            return False, None

    def search_and_download_audio(self, song_query, target_dir, progress_callback=None):
        """Legacy automated workflow: Searches for the song, uses AudioAgent to pick the best, and downloads it."""
        song_id = os.path.basename(target_dir)
        
        # If input is already a direct URL
        if song_query.startswith("http://") or song_query.startswith("https://"):
            download_url = song_query
            self.log(song_id, f"[INFO] Using direct URL: {download_url}")
        else:
            if progress_callback: progress_callback("Searching for Audio...")
            self.log(song_id, f"[WAIT] Searching and vetting results for '{song_query}'...")
            results = self.get_search_results(song_query)
            
            best = next((r for r in results if r.get('recommended')), None)
            if not best:
                self.log(song_id, "[ERROR] AudioAgent failed to find a valid source.")
                return None, None
                
            self.log(song_id, f"[OK] AudioAgent chose: {best['url']}")
            self.log(song_id, f"     Reason: {best.get('reason')}")
            download_url = best['url']
        
        success, actual_url = self.download_audio(download_url, target_dir, song_id, progress_callback)
        if success:
            return song_id, actual_url
        return None, None

    def separate_audio(self, song_id, actual_url, progress_callback=None):
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
                
            if progress_callback: progress_callback("Separating Stems (Demucs)...")
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
            if progress_callback: progress_callback("Analyzing Pitch...")
            self.log(song_id, f"[WAIT] Starting Pitch Analysis on vocals.wav...")
            try:
                analyzer = PitchAnalyzer(fps=50)
                analyzer.analyze(final_vocals, pitch_json_path)
            except Exception as e:
                self.log(song_id, f"[ERROR] PitchAnalyzer failed: {e}")
                return False
        elif os.path.exists(pitch_json_path):
            self.log(song_id, f"[INFO] pitch_profile.json already exists. Skipping Pitch Analysis.")

        # --- 3. Vocal Activity Map ---
        vocal_map_path = os.path.join(target_dir, "vocal_map.json")
        if os.path.exists(final_vocals) and not os.path.exists(vocal_map_path):
            if progress_callback: progress_callback("Analyzing Vocal Activity...")
            self.log(song_id, f"[WAIT] Generating Vocal Activity Map...")
            try:
                from .vocal_activity_analyzer import VocalActivityAnalyzer
                vmap = VocalActivityAnalyzer()
                vmap.analyze(final_vocals, vocal_map_path)
            except Exception as e:
                self.log(song_id, f"[ERROR] VocalActivityAnalyzer failed: {e}")
                
        return True

    def process_specific_song(self, song_id, url=None, local_audio_path=None, lyrics_text=None, lyrics_type="txt", target_dir_override=None, skip_audio=False, progress_callback=None, force_reprocess_audio=False, force_reprocess_lyrics=False, force_redownload_audio=False, search_query=None):
        """API workflow: Takes a specific source and lyrics, and processes them."""
        import concurrent.futures
        target_dir = target_dir_override if target_dir_override else os.path.join(self.hot_zone, song_id)
        os.makedirs(target_dir, exist_ok=True)
        
        self.log(song_id, f"[INFO] Starting specific processing for {song_id}")
        
        # Optional: Delete files if forced
        if force_reprocess_lyrics:
            self.log(song_id, "[INFO] Force Reprocess Lyrics is ON. Deleting existing lyric files...")
            for f in ["lyrics.txt", "lyrics.lrc", "transliteration.json", "meaning.json", "meta.json"]:
                p = os.path.join(target_dir, f)
                if os.path.exists(p): os.remove(p)
                
        if force_reprocess_audio:
            self.log(song_id, "[INFO] Force Reprocess Audio is ON. Deleting generated stems...")
            for f in ["final_vocals.wav", "instrumental.wav", "vocal_map.json", "pitch_analysis.json", "vocals.wav"]:
                p = os.path.join(target_dir, f)
                if os.path.exists(p): os.remove(p)
                
        if force_redownload_audio:
            self.log(song_id, "[INFO] Force Redownload Audio is ON. Deleting original.wav...")
            p = os.path.join(target_dir, "original.wav")
            if os.path.exists(p): os.remove(p)

        # 1. Start Lyrics Processing in Background Thread
        def run_lyrics():
            if progress_callback: progress_callback("Fetching Lyrics...")
            try:
                from core_engine.agents.lyric_agent import LyricAgent
                agent = LyricAgent()
                
                def lyric_logger(msg):
                    self.log(song_id, msg)
                    if progress_callback:
                        if msg.startswith("[WAIT] LyricAgent: "):
                            progress_callback(msg.replace("[WAIT] LyricAgent: ", ""))
                        elif msg.startswith("[INFO] LyricAgent: Detected language"):
                            progress_callback(msg.replace("[INFO] LyricAgent: ", ""))
                    
                query = search_query if search_query else song_id.replace("_", " ")
                agent.process_lyrics(
                    target_dir=target_dir,
                    query=query,
                    manual_lyrics=lyrics_text,
                    lyrics_type=lyrics_type,
                    log_callback=lyric_logger
                )
            except Exception as e:
                self.log(song_id, f"[WARN] Failed to process lyrics: {e}")
                
        executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)
        lyrics_future = executor.submit(run_lyrics)

        audio_success = True
        if skip_audio:
            self.log(song_id, "[INFO] Audio processing skipped (partial reprocess).")
        else:
            # 2. Acquire Audio
            target_mp3 = os.path.join(target_dir, "original.wav")
            actual_url = "Local File"
            
            if local_audio_path and os.path.exists(local_audio_path):
                if os.path.abspath(local_audio_path) != os.path.abspath(target_mp3):
                    self.log(song_id, f"[INFO] Copying local audio file from {local_audio_path}")
                    shutil.copy2(local_audio_path, target_mp3)
                else:
                    self.log(song_id, f"[INFO] Using existing local audio file {target_mp3}")
                if not local_audio_path.lower().endswith('.wav'):
                    temp_file = target_mp3 + ".temp"
                    shutil.move(target_mp3, temp_file)
                    cmd = [self.ffmpeg_path, "-y", "-i", temp_file, target_mp3]
                    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    os.remove(temp_file)
            elif url:
                if force_reprocess_audio or not os.path.exists(target_mp3):
                    audio_success, actual_url = self.download_audio(url, target_dir, song_id, progress_callback)
                else:
                    self.log(song_id, f"[INFO] Audio {target_mp3} exists, skipping download.")
                    audio_success = True
            else:
                self.log(song_id, "[ERROR] Neither URL nor local_audio_path provided.")
                audio_success = False
                
            # 3. Separate Audio & Analyze
            if audio_success:
                audio_success = self.separate_audio(song_id, actual_url, progress_callback)

        # 4. Wait for lyrics processing to finish
        if progress_callback: progress_callback("Waiting for lyrics processing to finalize...")
        lyrics_future.result()
        executor.shutdown()
        
        return audio_success

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
            from core_engine.agents.lyric_agent import LyricAgent
            agent = LyricAgent()
            agent.process_lyrics(target_dir=target_dir, query=song_query, log_callback=lyric_logger)
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
    def generate_medley(self, medley_def: dict, progress_callback=None):
        import datetime
        import subprocess
        import re
        
        def log(msg):
            if progress_callback: progress_callback(msg)
            print(f"[MEDLEY] {msg}")

        title = medley_def.get("title", "Unknown Medley")
        segments = medley_def.get("segments", [])
        
        if not segments:
            log("No segments provided for medley.")
            return False

        # Generate a unique ID and setup directory
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        safe_title = sanitize_filename(title)
        medley_id = f"MDLY_{safe_title}_{timestamp}"
        target_dir = os.path.join(self.hot_zone, medley_id)
        os.makedirs(target_dir, exist_ok=True)
        
        log(f"Generating medley '{title}' with {len(segments)} segments...")

        inputs = []
        filter_complex_inst = []
        filter_complex_vocal = []
        concat_inst = ""
        concat_vocal = ""
        
        combined_lyrics = []
        current_medley_ms = 0
        
        # Parse segments and prepare ffmpeg inputs
        for i, seg in enumerate(segments):
            src_mm_id = seg.get("source_mm_id")
            start_ms = seg.get("start_ms", 0)
            end_ms = seg.get("end_ms", 0)
            crossfade_ms = seg.get("crossfade_ms", 0)
            
            src_dir = os.path.join(self.hot_zone, src_mm_id)
            inst_path = os.path.join(src_dir, f"{src_mm_id}_instrumental.wav")
            vocal_path = os.path.join(src_dir, f"{src_mm_id}_vocals.wav")
            lyrics_path = os.path.join(src_dir, f"{src_mm_id}_lyrics_native.lrc")
            
            # Use original if split tracks don't exist yet (for unprocessed yt)
            # Wait! Unprocessed youtube might not have inst/vocals. If missing, we fail or use original.
            # For simplicity, if instrumental is missing, we use the original audio for both.
            if not os.path.exists(inst_path):
                orig_audio = next((f for f in os.listdir(src_dir) if f.endswith('.wav') or f.endswith('.mp4') or f.endswith('.webm')), None)
                if orig_audio:
                    inst_path = os.path.join(src_dir, orig_audio)
                    vocal_path = inst_path
                else:
                    log(f"Source audio not found for {src_mm_id}")
                    return False
                    
            # Add to ffmpeg inputs (2 inputs per segment: inst and vocal)
            input_idx_inst = i * 2
            input_idx_vocal = i * 2 + 1
            inputs.extend(['-i', inst_path, '-i', vocal_path])
            
            # Format time
            start_s = start_ms / 1000.0
            end_s = end_ms / 1000.0
            
            # Add trim filters
            filter_complex_inst.append(f"[{input_idx_inst}:a]atrim=start={start_s}:end={end_s},asetpts=PTS-STARTPTS[i{i}];")
            filter_complex_vocal.append(f"[{input_idx_vocal}:a]atrim=start={start_s}:end={end_s},asetpts=PTS-STARTPTS[v{i}];")
            
            # Handle Lyrics
            if os.path.exists(lyrics_path):
                try:
                    with open(lyrics_path, 'r', encoding='utf-8') as lf:
                        for line in lf:
                            line = line.strip()
                            if not line: continue
                            match = re.match(r'\[(\d+):(\d+\.\d+)\](.*)', line)
                            if match:
                                m, s, text = match.groups()
                                line_ms = int(m) * 60000 + float(s) * 1000
                                if start_ms <= line_ms <= end_ms:
                                    # Shift timestamp
                                    new_ms = (line_ms - start_ms) + current_medley_ms
                                    new_m = int(new_ms // 60000)
                                    new_s = (new_ms % 60000) / 1000.0
                                    combined_lyrics.append(f"[{new_m:02d}:{new_s:05.2f}]{text}")
                except Exception as e:
                    log(f"Error parsing lyrics for {src_mm_id}: {e}")
            
            # Duration added to medley timeline
            seg_dur = end_ms - start_ms
            current_medley_ms += seg_dur
            if i < len(segments) - 1:
                current_medley_ms -= crossfade_ms
        
        # Build concat filter
        # If no crossfade, just use concat filter
        # Crossfade in ffmpeg audio is complex for N segments. Let's start with hard concat for v1, or basic concat
        has_crossfades = any(seg.get("crossfade_ms", 0) > 0 for seg in segments)
        if has_crossfades:
            # Complex acrossfade logic...
            # For simplicity in this implementation, we will use acrossfade
            prev_i = "i0"
            prev_v = "v0"
            for i in range(1, len(segments)):
                cf_s = segments[i-1].get("crossfade_ms", 0) / 1000.0
                if cf_s > 0:
                    filter_complex_inst.append(f"[{prev_i}][i{i}]acrossfade=d={cf_s}[i_out{i}];")
                    filter_complex_vocal.append(f"[{prev_v}][v{i}]acrossfade=d={cf_s}[v_out{i}];")
                else:
                    filter_complex_inst.append(f"[{prev_i}][i{i}]concat=n=2:v=0:a=1[i_out{i}];")
                    filter_complex_vocal.append(f"[{prev_v}][v{i}]concat=n=2:v=0:a=1[v_out{i}];")
                prev_i = f"i_out{i}"
                prev_v = f"v_out{i}"
            concat_inst = f"[{prev_i}]"
            concat_vocal = f"[{prev_v}]"
        else:
            for i in range(len(segments)):
                concat_inst += f"[i{i}]"
                concat_vocal += f"[v{i}]"
            filter_complex_inst.append(f"{concat_inst}concat=n={len(segments)}:v=0:a=1[out_i];")
            filter_complex_vocal.append(f"{concat_vocal}concat=n={len(segments)}:v=0:a=1[out_v];")
            concat_inst = "[out_i]"
            concat_vocal = "[out_v]"

        out_inst_path = os.path.join(target_dir, f"{medley_id}_instrumental.wav")
        out_vocal_path = os.path.join(target_dir, f"{medley_id}_vocals.wav")

        filter_string = " ".join(filter_complex_inst + filter_complex_vocal)
        
        ffmpeg_cmd = [self.ffmpeg_path, "-y"] + inputs + [
            "-filter_complex", filter_string,
            "-map", concat_inst, out_inst_path,
            "-map", concat_vocal, out_vocal_path
        ]
        
        log("Executing FFmpeg rendering...")
        try:
            subprocess.run(ffmpeg_cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
        except subprocess.CalledProcessError as e:
            log(f"FFmpeg failed: {e}")
            return False

        # Write lyrics
        lyrics_out = os.path.join(target_dir, f"{medley_id}_lyrics_native.lrc")
        with open(lyrics_out, 'w', encoding='utf-8') as f:
            f.write("\n".join(combined_lyrics))
            
        # Write performance profile (a single sequence spanning the whole medley)
        profile = {
            "sequences": [{
                "name": "Medley",
                "segments": [{
                    "start_ms": 0,
                    "end_ms": current_medley_ms,
                    "playback_mode": "both"
                }]
            }]
        }
        profile_path = os.path.join(target_dir, f"{medley_id}_performance_profiles.json")
        with open(profile_path, 'w') as f:
            json.dump(profile, f)
            
        # Update SQLite AI Tracking
        from core_engine.karaoke_orchestrator import init_db
        import sqlite3
        db_path = os.path.join(self.hot_zone, "vox_ai_metadata.db")
        conn = sqlite3.connect(db_path)
        c = conn.cursor()
        c.execute('''INSERT OR REPLACE INTO ai_artifacts 
                     (mm_id, title, has_vocals, has_instrumental, has_lyrics, last_processed) 
                     VALUES (?, ?, 1, 1, 1, CURRENT_TIMESTAMP)''', (medley_id, title))
        conn.commit()
        conn.close()

        log("Medley Generation Complete!")
        return True
