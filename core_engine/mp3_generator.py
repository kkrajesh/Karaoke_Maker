import os
import re
import json
import subprocess
from mutagen.mp3 import MP3
from mutagen.id3 import ID3, TIT2, TPE1, USLT, SYLT, Encoding, TXXX
from mutagen.id3 import ID3NoHeaderError

class PracticeMp3Generator:
    def __init__(self, target_dir, ffmpeg_path="ffmpeg"):
        self.target_dir = target_dir
        self.ffmpeg_path = ffmpeg_path
        
        basename = os.path.basename(self.target_dir)
        self.instrumental_wav = os.path.join(self.target_dir, f"{basename}_instrumental.wav")
        self.vocals_wav = os.path.join(self.target_dir, f"{basename}_vocals.wav")
        
        # Determine the best lrc file to use (English preferred over native for tags usually, or whichever exists)
        self.lrc_file = None
        for name in [f"{basename}_lyrics_english.lrc", f"{basename}_lyrics_native.lrc"]:
            path = os.path.join(self.target_dir, name)
            if os.path.exists(path):
                self.lrc_file = path
                break

    def generate_all(self, pitch_shift=0.0, tempo_shift=1.0):
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

        # Scale timestamps if tempo changed
        scaled_parsed_data = []
        for seg in parsed_data:
            new_seg = dict(seg)
            t_new = seg['start'] / tempo_shift
            millis_new = int(seg['millis'] / tempo_shift)
            total_seconds = millis_new / 1000.0
            mins = int(total_seconds // 60)
            secs = int(total_seconds % 60)
            hunds = int((total_seconds - mins * 60 - secs) * 100)
            new_seg['start'] = t_new
            new_seg['end'] = seg['end'] / tempo_shift
            new_seg['millis'] = millis_new
            new_seg['time_str'] = f"[{mins:02d}:{secs:02d}.{hunds:02d}]"
            scaled_parsed_data.append(new_seg)

        # Ensure song title and artist are extracted from folder name or metadata
        basename = os.path.basename(self.target_dir)
        song_title = basename.replace("_", " ")
        
        # Build postfix
        postfix = ""
        if pitch_shift != 0.0 or tempo_shift != 1.0:
            pitch_str = f"+{pitch_shift}" if pitch_shift > 0 else str(pitch_shift)
            tempo_str = f"{int(tempo_shift * 100)}%"
            postfix = f"_Pitch{pitch_str}_Tempo{tempo_str}"

        generated_files = []

        # Generate Full version (Instrumental only, no vocals)
        out_full = os.path.join(self.target_dir, f"{basename}_practice_full{postfix}.mp3")
        if self._generate_mixed_track(out_full, mute_intervals=[(0.0, 999999.0)], pitch_shift=pitch_shift, tempo_shift=tempo_shift):
            self._embed_lyrics(out_full, song_title + postfix.replace("_", " "), scaled_parsed_data, pitch_shift, tempo_shift)
            generated_files.append(out_full)

        # Generate practice track for each singer
        for singer in singers:
            mute_intervals = []
            lower_intervals = []
            
            for seg in parsed_data:
                if seg['tag'] == singer:
                    mute_intervals.append((seg['start'], seg['end']))
                elif seg['tag'] == 'B':
                    lower_intervals.append((seg['start'], seg['end']))

            out_file = os.path.join(self.target_dir, f"{basename}_practice_singer_{singer}{postfix}.mp3")
            if self._generate_mixed_track(out_file, mute_intervals, lower_intervals, pitch_shift=pitch_shift, tempo_shift=tempo_shift):
                self._embed_lyrics(out_file, f"{song_title} (Singer {singer} Practice){postfix.replace('_', ' ')}", scaled_parsed_data, pitch_shift, tempo_shift)
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
                    'millis': mins * 60000 + secs * 1000 + millis,
                    'time_str': time_match.group(0)
                })
                current_tag = tag

        return segments

    def _generate_mixed_track(self, out_path, mute_intervals, lower_intervals=[], pitch_shift=0.0, tempo_shift=1.0):
        # Build volume filter for vocals
        v_filters = []
        
        if mute_intervals:
            mute_cond = "+".join([f"between(t,{start},{end})" for start, end in mute_intervals])
            v_filters.append(f"volume=0:enable='{mute_cond}'")
            
        if lower_intervals:
            lower_cond = "+".join([f"between(t,{start},{end})" for start, end in lower_intervals])
            v_filters.append(f"volume=0.3:enable='{lower_cond}'")
            
        vocals_filter_str = ",".join(v_filters) if v_filters else "volume=1"

        def run_ffmpeg(shift_filter):
            filter_complex = f"[1:a]{vocals_filter_str}[v_filtered];[0:a][v_filtered]amix=inputs=2:duration=longest[mixed]"
            if shift_filter:
                filter_complex += f";[mixed]{shift_filter}[aout]"
            else:
                filter_complex += ";[mixed]anull[aout]"
                
            cmd = [
                self.ffmpeg_path,
                "-y",
                "-i", self.instrumental_wav,
                "-i", self.vocals_wav,
                "-filter_complex", filter_complex,
                "-map", "[aout]",
                "-c:a", "libmp3lame",
                "-q:a", "2",
                out_path
            ]
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        if pitch_shift == 0.0 and tempo_shift == 1.0:
            try:
                run_ffmpeg(None)
                return True
            except subprocess.CalledProcessError as e:
                print(f"[ERROR] FFmpeg failed: {e}")
                return False
        
        # We need to shift pitch/tempo
        rubberband_filter = f"rubberband=pitch={pitch_shift}:tempo={tempo_shift}"
        
        # Build fallback
        import math
        rate_multiplier = math.pow(2.0, pitch_shift / 12.0)
        new_rate = 44100 * rate_multiplier
        target_tempo = tempo_shift / rate_multiplier
        
        atempo_filters = []
        t = target_tempo
        while t > 2.0:
            atempo_filters.append("atempo=2.0")
            t /= 2.0
        while t < 0.5:
            atempo_filters.append("atempo=0.5")
            t /= 0.5
        if t != 1.0:
            atempo_filters.append(f"atempo={t}")
            
        fallback_filter = f"asetrate={new_rate}"
        if atempo_filters:
            fallback_filter += "," + ",".join(atempo_filters)

        try:
            run_ffmpeg(rubberband_filter)
            return True
        except subprocess.CalledProcessError:
            print("[WARN] Rubberband filter failed (likely not installed). Falling back to asetrate/atempo...")
            try:
                run_ffmpeg(fallback_filter)
                return True
            except subprocess.CalledProcessError as e:
                print(f"[ERROR] FFmpeg fallback failed: {e}")
                return False

    def _embed_lyrics(self, mp3_path, title, parsed_data, pitch_shift=0.0, tempo_shift=1.0):
        try:
            audio = ID3(mp3_path)
        except ID3NoHeaderError:
            audio = ID3()

        # Set Title
        audio.add(TIT2(encoding=Encoding.UTF8, text=[title]))
        
        # Add custom TXXX tags
        audio.add(TXXX(encoding=Encoding.UTF8, desc="PitchShift", text=[str(pitch_shift)]))
        audio.add(TXXX(encoding=Encoding.UTF8, desc="TempoShift", text=[str(tempo_shift)]))
        
        # Build USLT text and SYLT items
        uslt_text = ""
        sylt_lyrics = []
        
        for seg in parsed_data:
            line_text = seg['text']
            prefix = seg['time_str']
            sylt_text = f"[{seg['tag']}] {line_text}" if seg['tag'] else line_text
            
            if seg['tag']:
                prefix += f"[{seg['tag']}]"
            uslt_text += f"{prefix} {line_text}\n"
            
            sylt_lyrics.append((sylt_text, seg['millis']))

        # Add USLT
        audio.add(USLT(encoding=Encoding.UTF8, lang='eng', desc='', text=uslt_text))
        
        # Add SYLT (type 1 is lyrics)
        audio.add(SYLT(encoding=Encoding.UTF8, lang='eng', format=2, type=1, desc='', text=sylt_lyrics))

        audio.save(mp3_path, v2_version=3)
