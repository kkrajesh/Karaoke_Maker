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

    def search_duckduckgo_lyrics(self, query):
        """Perform a DuckDuckGo HTML search for lyrics."""
        from duckduckgo_search import DDGS
        search_term = f"{query} lyrics"
        results = []
        try:
            with DDGS() as ddgs:
                for r in ddgs.text(search_term, max_results=5):
                    results.append({"title": r.get("title", ""), "url": r.get("href", "")})
        except Exception as e:
            self.log(f"[WARN] DuckDuckGo search failed: {e}")
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

Identify the best result that is a dedicated lyrics website (e.g. Genius, Musixmatch, LyricsTranslate).
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

    def extract_and_transliterate_lyrics(self, raw_text):
        """Uses the LLM to extract lyrics from scraped text and transliterate them."""
        prompt = f"""
You are an expert linguist and data extractor.
I have scraped the raw text from a webpage that contains the lyrics to a song.
However, there is a lot of website junk (menus, ads, footers) mixed in.

Your tasks:
1. Extract ONLY the pure song lyrics.
2. If the lyrics are in a native Indian script (e.g., Telugu, Tamil, Hindi, Malayalam), TRANSLITERATE them into the English alphabet (do NOT translate the meaning, just the pronunciation).
3. If they are already in the English alphabet, leave them as is.
4. Output ONLY the final lyrics text. Do NOT include any intro text, conversational text, or the website junk.

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

    def search_youtube_lyrics(self, query):
        """Search YouTube for lyric videos and extract their descriptions."""
        import yt_dlp
        search_term = f"ytsearch3:{query} full lyrics"
        ydl_opts = {'quiet': True, 'extract_flat': False} # Extract full info to get description
        descriptions = ""
        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(search_term, download=False)
                if 'entries' in info:
                    for entry in info['entries']:
                        desc = entry.get('description', '')
                        if desc and len(desc) > 100:
                            descriptions += f"\n--- VIDEO DESCRIPTION ---\n{desc}\n"
        except Exception as e:
            self.log(f"[WARN] YouTube search failed: {e}")
        return descriptions

    def fetch_and_save(self, query, target_dir, log_callback=None):
        """Fetches lyrics and saves both native and transliterated versions."""
        if log_callback:
            self.log = log_callback
            
        self.log(f"[WAIT] LyricAgent: Searching lyrics for '{query}'...")
        
        lyrics, is_synced = self.search_lrclib(query)
        source = "LRCLib"
        
        if not lyrics:
            lyrics = self.search_genius(query)
            is_synced = False
            source = "Genius API"
            
        # --- NEW: Web Search Fallback ---
        if not lyrics:
            self.log(f"[WAIT] LyricAgent: Falling back to Web Search Scraper...")
            search_results = self.search_duckduckgo_lyrics(query)
            best_url = self.pick_best_lyric_source(query, search_results)
            
            raw_text = ""
            if best_url:
                self.log(f"[INFO] LyricAgent: Scraping {best_url}...")
                try:
                    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
                    resp = requests.get(best_url, headers=headers, timeout=10)
                    if resp.status_code == 200:
                        soup = BeautifulSoup(resp.text, 'html.parser')
                        raw_text = soup.get_text(separator="\n", strip=True)
                except Exception as e:
                    self.log(f"[WARN] Web Search scraping failed: {e}")
            
            # If Web Search completely failed (e.g., blocked by IP rate limit), try YouTube
            if not raw_text or len(raw_text) < 100:
                self.log(f"[WAIT] LyricAgent: Web Search failed. Falling back to YouTube Descriptions...")
                raw_text = self.search_youtube_lyrics(query)
                best_url = "YouTube Descriptions"
                
            if raw_text and len(raw_text) > 100:
                self.log(f"[WAIT] LyricAgent: Extracting and transliterating with LLM...")
                eng_lyrics = self.extract_and_transliterate_lyrics(raw_text)
                
                if eng_lyrics and len(eng_lyrics) > 20: # Sanity check
                    # We don't have the native lyrics, just the english ones from the LLM
                    eng_path = os.path.join(target_dir, "lyrics_english.txt")
                    with open(eng_path, "w", encoding="utf-8") as f:
                        f.write(eng_lyrics)
                    self.log(f"[OK] LyricAgent: Saved scraped English lyrics from {best_url}.")
                    return True
            
        if not lyrics:
            self.log(f"[INFO] LyricAgent: No lyrics found for '{query}'. Skipping lyrics.")
            return False
            
        ext = ".lrc" if is_synced else ".txt"
        native_path = os.path.join(target_dir, f"lyrics_native{ext}")
        eng_path = os.path.join(target_dir, f"lyrics_english{ext}")
        
        # Save original (Native)
        with open(native_path, "w", encoding="utf-8") as f:
            f.write(lyrics)
            
        self.log(f"[OK] LyricAgent: Saved native lyrics from {source}.")
        
        # Transliterate to English
        self.log(f"[WAIT] LyricAgent: Transliterating to English using LLM...")
        eng_lyrics = self.transliterate_to_english(lyrics)
        if eng_lyrics:
            with open(eng_path, "w", encoding="utf-8") as f:
                f.write(eng_lyrics)
            self.log(f"[OK] LyricAgent: Saved english transliterated lyrics.")
            
        return True
