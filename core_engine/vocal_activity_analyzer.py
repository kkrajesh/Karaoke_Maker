import os
import json
import warnings
import librosa
import numpy as np

# Suppress warnings
warnings.filterwarnings('ignore')
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'

class VocalActivityAnalyzer:
    def __init__(self, fps=50):
        self.fps = fps
        self.sr = 22050
        self.hop_length = self.sr // self.fps
        
        # Threshold for RMS energy to be considered "active vocal"
        # Since vocals.wav is isolated, silence is truly silent or very low energy.
        self.rms_threshold_ratio = 0.05 # 5% of max RMS

    def analyze(self, audio_path, output_json_path):
        if not os.path.exists(audio_path):
            print(f"[ERROR] File not found {audio_path}")
            return False

        print(f"[WAIT] Loading audio {os.path.basename(audio_path)}...")
        try:
            y, sr = librosa.load(audio_path, sr=self.sr)
        except Exception as e:
            print(f"[ERROR] Failed to load audio: {e}")
            return False

        print("[WAIT] Computing RMS energy to detect vocal activity...")
        # Compute RMS energy
        rms = librosa.feature.rms(y=y, hop_length=self.hop_length)[0]
        times = librosa.times_like(rms, sr=sr, hop_length=self.hop_length)

        # Thresholding
        max_rms = np.max(rms)
        threshold = max_rms * self.rms_threshold_ratio
        
        active_frames = rms > threshold

        # Group continuous active frames into segments
        segments = []
        in_segment = False
        start_t = 0.0
        
        # We allow a small gap of silence (e.g., 0.5 seconds) to be merged
        min_gap = 0.5 
        last_active_t = 0.0

        for t, is_active in zip(times, active_frames):
            if is_active:
                if not in_segment:
                    in_segment = True
                    start_t = float(t)
                last_active_t = float(t)
            else:
                if in_segment and (float(t) - last_active_t > min_gap):
                    segments.append({
                        "start": round(start_t, 2),
                        "end": round(last_active_t, 2)
                    })
                    in_segment = False
        
        if in_segment:
            segments.append({
                "start": round(start_t, 2),
                "end": round(last_active_t, 2)
            })

        output_data = {
            "vocal_segments": segments
        }

        with open(output_json_path, "w", encoding="utf-8") as f:
            json.dump(output_data, f, separators=(',', ':'))

        print(f"[OK] Saved {len(segments)} vocal activity segments to {os.path.basename(output_json_path)}")
        return True

if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        audio_file = sys.argv[1]
        out_file = os.path.join(os.path.dirname(audio_file), "vocal_map.json")
        analyzer = VocalActivityAnalyzer()
        analyzer.analyze(audio_file, out_file)
