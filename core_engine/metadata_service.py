import re
import json
import requests
import urllib.parse
from typing import Optional, Dict

class SongMetadata:
    def __init__(self, title: str, album: str, year: str, artist: str):
        self.title = title
        self.album = album
        self.year = year
        self.artist = artist

    def to_dict(self):
        return {
            "title": self.title,
            "album": self.album,
            "year": self.year,
            "artist": self.artist
        }

class MetadataService:
    
    @staticmethod
    def search_metadata(raw_title: str) -> Optional[SongMetadata]:
        clean_title = MetadataService._clean_title_for_search(raw_title)
        
        # 1. Try iTunes Search API
        itunes_data = MetadataService._search_itunes(clean_title)
        if itunes_data:
            return itunes_data
            
        # 2. Try JioSaavn Search API as fallback
        jiosaavn_data = MetadataService._search_jiosaavn(clean_title)
        if jiosaavn_data:
            return jiosaavn_data
            
        return None

    @staticmethod
    def _clean_title_for_search(raw: str) -> str:
        clean = raw.replace('_', ' ')
        # Remove complex junk
        clean = re.sub(r'(?i)Full.*?Audio', ' ', clean)
        clean = re.sub(r'(?i)High\s*def.*', ' ', clean)
        clean = re.sub(r'(?i)with.*?Audio', ' ', clean)
        clean = re.sub(r'(?i)\b(HD|4K|1080p|720p|Official Video|Lyrical Video|Karaoke|गाने के बोल|Lyrical|Lyrics|Audio Song|Video Song|Music Video)\b', ' ', clean)
        clean = re.sub(r'(?i)\bSong\b', ' ', clean)
        clean = re.sub(r'(?i)\b(Malayalam|Tamil|Hindi|Telugu|Kannada|Film|Movie|Actor|Actress|Unknown)\b', ' ', clean)
        clean = re.sub(r'(?i)\b(Sony Music|T-Series|TSeries|Zee Music|Saregama|Aditya Music|Mango Music|Lahari Music|Bhavani|Tips|Venus|Speed Audio|Music|Video)\b', ' ', clean)
        clean = re.sub(r'\b\d{10,}\b', ' ', clean) # Remove long timestamp numbers

        parts = [p.strip() for p in clean.split('|') if p.strip()]
        if len(parts) > 1:
            # Just take the first part (English title) and maybe the album if present
            query = re.sub(r'\s+', ' ', parts[0]).strip()
            indian_script_reg = re.compile(r'[\u0900-\u0D7F]')
            # If part 1 is native script, skip it
            next_idx = 1
            if len(parts) > 2 and indian_script_reg.search(parts[1]) and not indian_script_reg.search(parts[0]):
                next_idx = 2
            else:
                dash_parts = query.split('-')
                if len(dash_parts) > 1 and indian_script_reg.search(dash_parts[1]):
                    query = dash_parts[0].strip()
            
            # If we have album or artist, append it to narrow down search
            if len(parts) > next_idx:
                query += ' ' + parts[next_idx]
            return query
        else:
            dash_parts = clean.split('-')
            if len(dash_parts) > 1:
                return dash_parts[1].strip() + ' ' + dash_parts[0].strip()
            return re.sub(r'\[.*?\]', ' ', re.sub(r'\(.*?\)', ' ', clean)).strip()

    @staticmethod
    def _search_itunes(query: str) -> Optional[SongMetadata]:
        try:
            url = f"https://itunes.apple.com/search?term={urllib.parse.quote(query)}&entity=song&limit=5"
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                data = response.json()
                if data.get('resultCount', 0) > 0:
                    
                    # Try to find a track that isn't a compilation/mix/hits album
                    best_track = data['results'][0]
                    for track in data['results']:
                        temp_album = str(track.get('collectionName', '')).lower()
                        if not any(x in temp_album for x in ['mix', 'best of', 'hits', 'essential']):
                            best_track = track
                            break
                    
                    track = best_track
                    title = track.get('trackName', '')
                    album = track.get('collectionName', '')
                    artist = track.get('artistName', '')
                    year = ''
                    if track.get('releaseDate'):
                        year = str(track['releaseDate'])[:4]
                        
                    title = MetadataService._clean_api_result(title)
                    album = MetadataService._clean_api_result(album)
                    
                    # If album is exactly the title + " - Single", clear it out so heuristics can try to find it, or just use it.
                    # Extract album from '(From "Movie")'
                    if '(From' in title or '( From' in title:
                        match = re.search(r'\(\s*[Ff]rom\s*["\']?(.*?)["\']?\s*\)', title)
                        if match and match.group(1):
                            album = match.group(1)
                        title = re.split(r'\(\s*[Ff]rom', title)[0].strip()
                        
                    title = re.sub(r'\([^)]*\)', '', title)
                    title = re.sub(r'\[[^\]]*\]', '', title).strip()
                    title = re.sub(r'\s+', ' ', title)
                    
                    if not MetadataService._is_valid_match(query, title):
                        return None
                        
                    return SongMetadata(title=title, album=album, year=year, artist=artist)
        except Exception:
            pass
        return None

    @staticmethod
    def _search_jiosaavn(query: str) -> Optional[SongMetadata]:
        try:
            url = f"https://www.jiosaavn.com/api.php?__call=autocomplete.get&query={urllib.parse.quote(query)}&_format=json&_marker=0&ctx=android"
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                data = response.json()
                if data.get('songs') and data['songs'].get('data'):
                    songs = data['songs']['data']
                    if len(songs) > 0:
                        best_track = songs[0]
                        for track in songs:
                            temp_album = str(track.get('album', '')).lower()
                            if not any(x in temp_album for x in ['mix', 'best of', 'hits', 'essential']):
                                best_track = track
                                break
                        
                        track = best_track
                        title = track.get('title', '')
                        album = track.get('album', '')
                        artist = ''
                        
                        if track.get('more_info') and track['more_info'].get('primary_artists'):
                            artist = track['more_info']['primary_artists']
                        elif track.get('description'):
                            artist = str(track['description']).split('·')[-1].strip()
                            
                        # Clean up html entities
                        title = title.replace('&quot;', '"')
                        album = album.replace('&quot;', '"')
                        artist = artist.replace('&quot;', '"')
                        
                        title = MetadataService._clean_api_result(title)
                        album = MetadataService._clean_api_result(album)
                        
                        if '(From' in title or '( From' in title:
                            match = re.search(r'\(\s*[Ff]rom\s*["\']?(.*?)["\']?\s*\)', title)
                            if match and match.group(1):
                                album = match.group(1)
                            title = re.split(r'\(\s*[Ff]rom', title)[0].strip()
                            
                        title = re.sub(r'\([^)]*\)', '', title)
                        title = re.sub(r'\[[^\]]*\]', '', title).strip()
                        title = re.sub(r'\s+', ' ', title)
                        
                        if not MetadataService._is_valid_match(query, title):
                            return None
                            
                        return SongMetadata(title=title, album=album, year='', artist=artist)
        except Exception:
            pass
        return None

    @staticmethod
    def _clean_api_result(text: str) -> str:
        clean = text
        clean = re.sub(r'(?i)\s*-\s*Single', '', clean)
        clean = re.sub(r'(?i)\s*-\s*EP', '', clean)
        clean = re.sub(r'(?i)\s*-\s*TELUGU', '', clean)
        clean = re.sub(r'(?i)\s*-\s*TAMIL', '', clean)
        clean = re.sub(r'(?i)\s*-\s*HINDI', '', clean)
        clean = re.sub(r'(?i)\s*-\s*MALAYALAM', '', clean)
        clean = re.sub(r'(?i)\(\s*Original Motion Picture Soundtrack\s*\)', '', clean)
        clean = re.sub(r'(?i)Original Motion Picture Soundtrack', '', clean)
        return clean.strip()

    @staticmethod
    def _is_valid_match(query: str, result_title: str) -> bool:
        q_clean = re.sub(r'[^a-z0-9\s]', '', query.lower())
        r_clean = re.sub(r'[^a-z0-9\s]', '', result_title.lower())
        
        q_words = [w for w in q_clean.split() if len(w) > 2]
        r_words = [w for w in r_clean.split() if len(w) > 2]
        
        if not q_words or not r_words:
            return True
            
        # Check for partial word matches (e.g. anuraaga vs anuraga)
        matches = 0
        for qw in q_words:
            if any(qw in rw or rw in qw for rw in r_words):
                matches += 1
                
        if len(q_words) <= 2:
            return matches >= 1 # Just 1 word matching partially is enough for short titles
        else:
            return (matches / len(q_words)) >= 0.5
