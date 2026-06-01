import os
import requests
import urllib.parse
from bs4 import BeautifulSoup
import json
from openai import OpenAI
import lyricsgenius

class LyricAgent:
    def __init__(self):
        self.genius_token = os.getenv("GENIUS_TOKEN")
        self.genius = lyricsgenius.Genius(self.genius_token) if self.genius_token else None
        
        base_url = os.getenv("LLM_BASE_URL", "http://localhost:1234/v1")
        api_key = os.getenv("LLM_API_KEY", "not-needed")
        self.llm_client = OpenAI(base_url=base_url, api_key=api_key)
        self.model = os.getenv("LLM_MODEL", "local-model")
        self.log = print

    def search_lrclib(self, query):
        """Search LRCLib for synchronized lyrics (.lrc)."""
        # LRCLib expects track_name and artist_name, but we only have a raw query.
        # We will use the 'search' endpoint which takes a 'q' parameter.
        url = "https://lrclib.net/api/search"
        params = {"q": query}
        headers = {"User-Agent": "KaraokeMaker/1.0 (https://github.com/KaraokeMaker)"}
        try:
            response = requests.get(url, params=params, headers=headers, timeout=10)
            if response.status_code == 200:
                data = response.json()
                if data and len(data) > 0:
                    # Pick the first one that has synced lyrics
                    for track in data:
                        if track.get("syncedLyrics"):
                            return track["syncedLyrics"], True # is_synced
                    # If no synced, return plain text
                    if data[0].get("plainLyrics"):
                        return data[0]["plainLyrics"], False
        except Exception as e:
            self.log(f"[WARN] LRCLib search failed: {e}")
        return None, False

    def search_genius(self, query):
        """Search Genius for raw lyrics (.txt) if API key is provided."""
        if not self.genius:
            return None
        try:
            song = self.genius.search_song(query)
            if song:
                # Clean up the Genius lyrics (they often have [Intro], etc.)
                return song.lyrics, False
        except Exception as e:
            self.log(f"[WARN] Genius search failed: {e}")
        return None

    def clean_song_query(self, raw_query):
        """Uses the LLM to extract a clean 'Song Name Movie Name' query."""
        prompt = f"""
You are an AI assistant that cleans up dirty song search queries.
Your ONLY job is to extract the core 'Song Title' and optionally the 'Movie/Album Name'.
You MUST aggressively REMOVE:
- Extra junk words like 'Video Song', 'Full Video', '4K', 'Lyrical Video', 'Official Video', 'HD'
- Names of actors or cast (e.g., Salman, Aishwarya Rai)
- Names of singers (e.g., Udit N, Alka Y)
- Punctuation like '|' or '-'

Return ONLY the clean query (e.g., "Chand Chhupa Badal Mein Hum Dil De Chuke Sanam"), nothing else.

Raw Query: {raw_query}
"""
        try:
            response = self.llm_client.chat.completions.create(
                model=self.model,
                messages=[{"role": "user", "content": prompt}],
                temperature=0.1
            )
            return response.choices[0].message.content.strip()
        except Exception as e:
            self.log(f"[WARN] LLM Query clean failed: {e}")
            return raw_query

    def search_duckduckgo_lyrics(self, query):
        """Perform a DuckDuckGo HTML search for lyrics, prioritizing known sites."""
        import requests
        from bs4 import BeautifulSoup
        
        search_terms = [
            f"{query} lyrics site:m3db.com",
            f"{query} lyrics site:msidb.org",
            f"{query} lyrics site:hindilyrics4u.com",
            f"{query} lyrics"
        ]
        
        results = []
        urls_seen = set()
        
        try:
            for search_term in search_terms:
                response = requests.post(
                    'https://lite.duckduckgo.com/lite/', 
                    data={'q': search_term}, 
                    headers={'User-Agent': 'Mozilla/5.0'},
                    timeout=5
                )
                if response.status_code == 200:
                    soup = BeautifulSoup(response.text, 'html.parser')
                    for a in soup.find_all('a'):
                        href = a.get('href', '')
                        if href.startswith('http') and 'duckduckgo.com' not in href:
                            if href not in urls_seen:
                                urls_seen.add(href)
                                results.append({"title": a.text.strip(), "url": href})
                        # Limit to a few results per search term to keep the list reasonable
                        if len(results) >= 15:
                            break
        except Exception as e:
            self.log(f"[WARN] DuckDuckGo Lite search failed: {e}")
            
        return results

    def pick_best_lyric_source(self, query, search_results):
        """Asks the LLM to pick the best lyric website."""
        if not search_results:
            return None
        if len(search_results) == 1:
            return search_results[0]["url"]

        results_text = ""
        for i, res in enumerate(search_results):
            results_text += f"[{i}] Title: {res['title']}\n    URL: {res['url']}\n"

        prompt = f"""
I am searching for the lyrics to the song: "{query}"
Here are the search results:
{results_text}

Identify the best result that is a dedicated lyrics website.
CRITICALLY IMPORTANT: If any of the results are from msidb.org, m3db.com, hindilyrics4u.com, or smule.com, you MUST prioritize picking them over other websites (like Genius or Musixmatch).
Output ONLY valid JSON with the key "index" (integer) of the best result. No markdown formatting.
"""
        try:
            response = self.llm_client.chat.completions.create(
                model=self.model,
                messages=[{"role": "user", "content": prompt}],
                temperature=0.1,
                max_tokens=100
            )
            content = response.choices[0].message.content.strip()
            if content.startswith("```json"): content = content[7:]
            if content.startswith("```"): content = content[3:]
            if content.endswith("```"): content = content[:-3]
                
            data = json.loads(content.strip())
            best_idx = data.get("index", 0)
            if not isinstance(best_idx, int) or best_idx < 0 or best_idx >= len(search_results):
                best_idx = 0
            return search_results[best_idx]["url"]
        except Exception as e:
            self.log(f"[WARN] LLM lyric source selection failed: {e}. Defaulting to first.")
            return search_results[0]["url"]

    def extract_lyrics(self, raw_text):
        """Uses the LLM to extract lyrics from scraped text without translating them."""
        prompt = f"""
You are an expert data extractor.
I have scraped the raw text from a webpage that contains the lyrics to a song.
However, there is a lot of website junk (menus, ads, footers) mixed in.

Your tasks:
1. Extract ONLY the pure song lyrics exactly as they are written in the text.
2. Output ONLY the final lyrics text. Do NOT include any intro text, conversational text, or the website junk.

Webpage Text:
{raw_text[:8000]} # Limit to avoid context window explosion
"""
        try:
            response = self.llm_client.chat.completions.create(
                model=self.model,
                messages=[{"role": "user", "content": prompt}],
                temperature=0.1
            )
            return response.choices[0].message.content.strip()
        except Exception as e:
            self.log(f"[WARN] LLM Lyrics extraction failed: {e}")
            return None

    def detect_language(self, lyrics):
        prompt = f"""
        Identify the language of the following song lyrics. Reply ONLY with the name of the language (e.g., Hindi, Malayalam, Tamil, English, Telugu, Spanish). Do not explain or add extra text.
        Lyrics:
        {lyrics[:1000]}
        """
        try:
            response = self.llm_client.chat.completions.create(
                model=self.model,
                messages=[{"role": "user", "content": prompt}],
                temperature=0.1
            )
            return response.choices[0].message.content.strip()
        except Exception as e:
            self.log(f"[WARN] LLM Language detection failed: {e}")
            return "English"

    def generate_native_script(self, lyrics, language):
        prompt = f"""
        You are an expert linguist. The following lyrics are for a {language} song.
        Rewrite these lyrics entirely in the native script of {language} (e.g. Devanagari for Hindi).
        If they are already in the native script, just output them exactly as is.
        You MUST preserve any timestamps (e.g., [00:15.34]) exactly as they appear.
        Do not translate the meaning, just write the lyrics in the correct native script.
        Output ONLY the lyrics, no other text.
        Lyrics:
        {lyrics[:8000]}
        """
        try:
            response = self.llm_client.chat.completions.create(
                model=self.model,
                messages=[{"role": "user", "content": prompt}],
                temperature=0.1
            )
            return response.choices[0].message.content.strip()
        except Exception as e:
            self.log(f"[WARN] LLM Native script generation failed: {e}")
            return lyrics

    def generate_latin_script(self, lyrics, language):
        prompt = f"""
        You are an expert linguist. The following lyrics are for a {language} song.
        Transliterate these lyrics strictly into the Latin alphabet (English characters A-Z) so a non-native speaker can pronounce them.
        If they are already in the Latin alphabet (e.g. Hinglish, Manglish), just output them exactly as is.
        You MUST preserve any timestamps (e.g., [00:15.34]) exactly as they appear.
        Output ONLY the lyrics, no other text.
        Lyrics:
        {lyrics[:8000]}
        """
        try:
            response = self.llm_client.chat.completions.create(
                model=self.model,
                messages=[{"role": "user", "content": prompt}],
                temperature=0.1
            )
            return response.choices[0].message.content.strip()
        except Exception as e:
            self.log(f"[WARN] LLM Latin script generation failed: {e}")
            return lyrics

    def extract_poetic_meaning(self, lyrics):
        """Uses the LLM to generate a poetic meaning/translation of the lyrics."""
        prompt = f"""
You are a poetic translator. Your task is to provide a beautiful, poetic English translation and meaning of the following song lyrics.
Focus on the emotion, the feel, and the artistic intent of the song.
You do NOT need to preserve timestamps. Just provide the meaning paragraph by paragraph.

Lyrics:
{lyrics[:8000]}
"""
        try:
            response = self.llm_client.chat.completions.create(
                model=self.model,
                messages=[{"role": "user", "content": prompt}],
                temperature=0.7
            )
            return response.choices[0].message.content.strip()
        except Exception as e:
            self.log(f"[WARN] LLM Poetic translation failed: {e}")
            return None

    def search_youtube_lyrics(self, query):
        """Search YouTube for lyric videos and extract their descriptions."""
        import yt_dlp
        
        class QuietLogger:
            def debug(self, msg): pass
            def warning(self, msg): pass
            def error(self, msg): pass
            
        search_term = f"ytsearch3:{query} full lyrics"
        ydl_opts = {
            'quiet': True, 
            'extract_flat': False,
            'logger': QuietLogger()
        }
        
        ffmpeg_path = os.getenv("FFMPEG_PATH")
        if ffmpeg_path:
            ydl_opts['ffmpeg_location'] = ffmpeg_path
            
        descriptions = ""
        try:
            self.log(f"[DEBUG] Searching YouTube with term: {search_term}")
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(search_term, download=False)
                if 'entries' in info:
                    self.log(f"[DEBUG] Found {len(info['entries'])} YouTube results.")
                    for entry in info['entries']:
                        desc = entry.get('description', '')
                        if desc and len(desc) > 100:
                            descriptions += f"\n--- VIDEO DESCRIPTION ---\n{desc}\n"
            self.log(f"[DEBUG] Combined YouTube descriptions length: {len(descriptions)}")
        except Exception as e:
            self.log(f"[WARN] YouTube search failed: {e}")
        return descriptions

    def fetch_lyrics(self, query):
        """Fetches lyrics without saving, returning the best available lyrics text and type."""
        self.log(f"[WAIT] LyricAgent: Cleaning up query '{query}'...")
        clean_query = self.clean_song_query(query)
        self.log(f"[INFO] LyricAgent: Cleaned query -> '{clean_query}'")
        
        lyrics, is_synced = self.search_lrclib(clean_query)
        if lyrics:
            return {"text": lyrics, "type": "lrc" if is_synced else "txt", "source": "LRCLib"}
            
        lyrics = self.search_genius(clean_query)
        if lyrics:
            return {"text": lyrics, "type": "txt", "source": "Genius API"}
            
        # Fallback to Web Search and LLM extraction
        search_results = self.search_duckduckgo_lyrics(clean_query)
        best_url = self.pick_best_lyric_source(clean_query, search_results)
        
        raw_text = ""
        if best_url:
            try:
                headers = {"User-Agent": "Mozilla/5.0"}
                resp = requests.get(best_url, headers=headers, timeout=10)
                if resp.status_code == 200:
                    soup = BeautifulSoup(resp.text, 'html.parser')
                    raw_text = soup.get_text(separator="\n", strip=True)
            except Exception:
                pass
                
        if not raw_text or len(raw_text) < 100:
            self.log("[DEBUG] Web search yielded no valid text, falling back to YouTube...")
            raw_text = self.search_youtube_lyrics(clean_query)
            
        if raw_text and len(raw_text) > 100:
            self.log("[DEBUG] Sending raw text to LLM for lyric extraction...")
            eng_lyrics = self.extract_lyrics(raw_text)
            if eng_lyrics and len(eng_lyrics) > 20:
                self.log("[DEBUG] Returning successfully extracted lyrics.")
                return {"text": eng_lyrics, "type": "txt", "source": "LLM Extracted"}
            else:
                self.log(f"[WARN] Extracted lyrics were too short or empty: {len(eng_lyrics) if eng_lyrics else 0} chars.")
        else:
            self.log("[WARN] Raw text was still empty or too short after all fallbacks.")

        return {"text": "", "type": "txt", "source": "None"}

    def process_lyrics(self, target_dir, query=None, manual_lyrics=None, lyrics_type="txt", log_callback=None):
        """Fetches (if needed) and processes lyrics, generating English transliterations and meanings."""
        if log_callback:
            self.log = log_callback
            
        native_lyrics = manual_lyrics
        is_synced = lyrics_type == "lrc"
        source = "Manual Override"

        # --- EXISTING FILE CHECK ---
        if not native_lyrics:
            import glob
            fallback_files = glob.glob(os.path.join(target_dir, "*lyrics_native.*"))
            if not fallback_files:
                all_files = glob.glob(os.path.join(target_dir, "*.lrc")) + glob.glob(os.path.join(target_dir, "*.txt"))
                fallback_files = [f for f in all_files if "english" not in f and "meaning" not in f]
                
            if fallback_files:
                fallback_path = fallback_files[0]
                with open(fallback_path, "r", encoding="utf-8") as f:
                    native_lyrics = f.read()
                is_synced = fallback_path.endswith(".lrc")
                source = "Existing File Fallback"
                self.log(f"[INFO] LyricAgent: Found existing {os.path.basename(fallback_path)}. Skipping web search.")

        # --- WEB SEARCH ---
        if not native_lyrics and query:
            self.log(f"[WAIT] LyricAgent: Searching lyrics for '{query}'...")
            fetched = self.fetch_lyrics(query)
            if fetched["text"]:
                native_lyrics = fetched["text"]
                is_synced = fetched["type"] == "lrc"
                source = fetched["source"]

        if not native_lyrics:
            self.log(f"[INFO] LyricAgent: No lyrics found for '{query}'. Skipping lyrics.")
            return False

        # 1. Detect Language
        self.log("[WAIT] LyricAgent: Detecting song language...")
        detected_lang = self.detect_language(native_lyrics)
        self.log(f"[INFO] LyricAgent: Detected language -> {detected_lang}")

        ext = ".lrc" if is_synced else ".txt"
        
        # 2. Generate Native Script
        self.log(f"[WAIT] LyricAgent: Generating Native {detected_lang} script...")
        native_script = self.generate_native_script(native_lyrics, detected_lang)
        if native_script:
            native_path = os.path.join(target_dir, f"lyrics_native{ext}")
            with open(native_path, "w", encoding="utf-8") as f:
                f.write(native_script)
            self.log("[OK] LyricAgent: Saved native script lyrics.")

        # 3. Generate Latin Script (Transliteration)
        self.log(f"[WAIT] LyricAgent: Generating Latin transliteration...")
        latin_script = self.generate_latin_script(native_lyrics, detected_lang)
        if latin_script:
            eng_path = os.path.join(target_dir, f"lyrics_english{ext}")
            with open(eng_path, "w", encoding="utf-8") as f:
                f.write(latin_script)
            self.log("[OK] LyricAgent: Saved English (Latin) lyrics.")
            
            # 4. Poetic Meaning
            self.log(f"[WAIT] LyricAgent: Generating poetic meaning using LLM...")
            meaning = self.extract_poetic_meaning(latin_script)
            if meaning:
                meaning_path = os.path.join(target_dir, "lyrics_meaning.txt")
                with open(meaning_path, "w", encoding="utf-8") as f:
                    f.write(meaning)
                self.log(f"[OK] LyricAgent: Saved poetic meaning.")
        return True
