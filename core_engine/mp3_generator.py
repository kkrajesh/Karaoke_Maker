import os
import re
import json
import subprocess
from mutagen.mp3 import MP3
from mutagen.id3 import ID3, TIT2, TPE1, USLT, SYLT, Encoding
from mutagen.id3 import ID3NoHeaderError

class PracticeMp3Generator:
    def __init__(self, target_dir, ffmpeg_path="ffmpeg"):
        self.target_dir = target_dir
        self.ffmpeg_path = ffmpeg_path
        
        self.instrumental_wav = os.path.join(self.target_dir, "instrumental.wav")
        self.vocals_wav = os.path.join(self.target_dir, "vocals.wav")
        
        # Determine the best lrc file to use (English preferred over native for tags usually, or whichever exists)
        self.lrc_file = None
        for name in ["lyrics_english.lrc", "lyrics_native.lrc"]:
            path = os.path.join(self.target_dir, name)
            if os.path.exists(path):
                self.lrc_file = path
                break

    def generate_all(self):
        if not os.path.exists(self.instrumental_wav) or not os.path.exists(self.vocals_wav):
            return False, "Missing audio files."
            
        if not self.lrc_file:
            return False, "No .lrc file found for lyrics/tags."

        parsed_data = self._parse_lrc(self.lrc_file)
        if not parsed_data:
            return False, "Failed to parse .lrc file or no tags found."

        # Find all unique singers (excluding 'B' which means both)
        singers = set()
        for segment in parsed_data:
            if segment['tag'] and segment['tag'] != 'B':
                singers.add(segment['tag'])

        if not singers:
            return False, "No singer tags (e.g. [1], [2]) found in the .lrc file."

        # Ensure song title and artist are extracted from folder name or metadata
        basename = os.path.basename(self.target_dir)
        song_title = basename.replace("_", " ")

        generated_files = []

        # Generate Full version (Instrumental only, no vocals)
        out_full = os.path.join(self.target_dir, f"{basename}_practice_full.mp3")
        if self._generate_mixed_track(out_full, mute_intervals=[(0.0, 999999.0)]):
            self._embed_lyrics(out_full, song_title, parsed_data)
            generated_files.append(out_full)

        # Generate practice track for each singer
        for singer in singers:
            # We want to mute the current singer, and lower the volume for 'B' (Both)
            # Find intervals where tag == singer
            mute_intervals = []
            lower_intervals = []
            
            for seg in parsed_data:
                if seg['tag'] == singer:
                    mute_intervals.append((seg['start'], seg['end']))
                elif seg['tag'] == 'B':
                    lower_intervals.append((seg['start'], seg['end']))

            out_file = os.path.join(self.target_dir, f"{basename}_practice_singer_{singer}.mp3")
            if self._generate_mixed_track(out_file, mute_intervals, lower_intervals):
                self._embed_lyrics(out_file, song_title + f" (Singer {singer} Practice)", parsed_data)
                generated_files.append(out_file)

        return True, f"Generated {len(generated_files)} MP3s."

    def _parse_lrc(self, file_path):
        segments = []
        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()

        time_pattern = re.compile(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]')
        tag_pattern = re.compile(r'^\s*\[([a-zA-Z0-9])\]')

        current_tag = None
        current_time = 0.0

        for line in lines:
            time_match = time_pattern.search(line)
            if time_match:
                mins = int(time_match.group(1))
                secs = int(time_match.group(2))
                millis = int(time_match.group(3))
                if len(time_match.group(3)) == 2:
                    millis *= 10
                
                t = mins * 60 + secs + millis / 1000.0
                
                text_part = line[time_match.end():]
                tag_match = tag_pattern.search(text_part)
                
                tag = current_tag
                clean_text = text_part.strip()
                if tag_match:
                    tag = tag_match.group(1)
                    clean_text = text_part[tag_match.end():].strip()
                
                if current_tag is not None:
                    # Update previous segment end time
                    segments[-1]['end'] = t

                segments.append({
                    'start': t,
                    'end': t + 10.0, # Default to +10s if it's the last segment
                    'tag': tag,
                    'text': clean_text,
                    'millis': mins * 60000 + secs * 1000 + millis
                })
                current_tag = tag

        return segments

    def _generate_mixed_track(self, out_path, mute_intervals, lower_intervals=[]):
        # Build volume filter for vocals
        v_filters = []
        
        if mute_intervals:
            mute_cond = "+".join([f"between(t,{start},{end})" for start, end in mute_intervals])
            v_filters.append(f"volume=0:enable='{mute_cond}'")
            
        if lower_intervals:
            lower_cond = "+".join([f"between(t,{start},{end})" for start, end in lower_intervals])
            v_filters.append(f"volume=0.3:enable='{lower_cond}'")
            
        vocals_filter_str = ",".join(v_filters) if v_filters else "volume=1"

        # FFmpeg command
        # [0:a] is instrumental, [1:a] is vocals. 
        # Apply filter to [1:a] -> [v_filtered]
        # amix [0:a][v_filtered] -> out
        
        cmd = [
            self.ffmpeg_path,
            "-y",
            "-i", self.instrumental_wav,
            "-i", self.vocals_wav,
            "-filter_complex",
            f"[1:a]{vocals_filter_str}[v_filtered];[0:a][v_filtered]amix=inputs=2:duration=longest[aout]",
            "-map", "[aout]",
            "-c:a", "libmp3lame",
            "-q:a", "2",
            out_path
        ]
        
        try:
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True
        except subprocess.CalledProcessError as e:
            print(f"[ERROR] FFmpeg failed: {e}")
            return False

    def _embed_lyrics(self, mp3_path, title, parsed_data):
        try:
            audio = ID3(mp3_path)
        except ID3NoHeaderError:
            audio = ID3()

        # Set Title
        audio.add(TIT2(encoding=Encoding.UTF8, text=[title]))
        
        # Build USLT text and SYLT items
        uslt_text = ""
        sylt_lyrics = []
        
        for seg in parsed_data:
            line_text = seg['text']
            if seg['tag']:
                line_text = f"[{seg['tag']}] {line_text}"
            uslt_text += line_text + "\n"
            sylt_lyrics.append((line_text, seg['millis']))

        # Add USLT
        audio.add(USLT(encoding=Encoding.UTF8, lang='eng', desc='', text=uslt_text))
        
        # Add SYLT (type 1 is lyrics)
        audio.add(SYLT(encoding=Encoding.UTF8, lang='eng', format=2, type=1, desc='', text=sylt_lyrics))

        audio.save(mp3_path, v2_version=3)
