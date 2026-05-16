import os
import json
import warnings
import numpy as np

# Suppress librosa/numba warnings about deprecations to keep logs clean
warnings.filterwarnings('ignore')
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'

import librosa

class PitchAnalyzer:
    def __init__(self, fps=50):
        self.fps = fps
        self.sr = 22050
        self.hop_length = self.sr // self.fps  # 441 for 50fps
        
        # Frequencies for human vocal range roughly C2 to C7
        self.fmin = librosa.note_to_hz('C2')
        self.fmax = librosa.note_to_hz('C7')

    def estimate_tonic(self, y, sr):
        """
        Estimates the root note (Tonic/Shruti) of the song using a simple 
        chromagram heuristic. This assumes the most dominant pitch class 
        over the song is the tonic (Sa).
        """
        try:
            # Constant-Q chromagram is more accurate for musical pitch classes
            chroma = librosa.feature.chroma_cqt(y=y, sr=sr, hop_length=self.hop_length)
            
            # Sum the chroma energy across time for each of the 12 pitch classes
            chroma_sum = np.sum(chroma, axis=1)
            
            # The pitch class with the most energy
            tonic_idx = np.argmax(chroma_sum)
            
            # Map index (0-11) to Hz (where 0 is C. Let's use C4 as reference octave)
            notes = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
            tonic_note = f"{notes[tonic_idx]}3"
            tonic_hz = librosa.note_to_hz(tonic_note)
            
            return float(tonic_hz), tonic_note
        except Exception as e:
            print(f"[WARN] Failed to estimate tonic: {e}")
            return 220.0, "A3" # Default fallback

    def analyze(self, audio_path, output_json_path):
        """
        Extracts fundamental frequencies from the audio file using pyin
        and saves them to a compact JSON file.
        """
        if not os.path.exists(audio_path):
            print(f"[ERROR] PitchAnalyzer: File not found {audio_path}")
            return False

        print(f"[WAIT] PitchAnalyzer: Loading audio {os.path.basename(audio_path)} at {self.sr}Hz...")
        try:
            y, sr = librosa.load(audio_path, sr=self.sr)
        except Exception as e:
            print(f"[ERROR] PitchAnalyzer: Failed to load audio: {e}")
            return False

        print(f"[WAIT] PitchAnalyzer: Estimating tonic (Shruti)...")
        tonic_hz, tonic_note = self.estimate_tonic(y, sr)
        print(f"[INFO] PitchAnalyzer: Estimated Tonic is {tonic_note} ({tonic_hz:.2f} Hz)")

        print(f"[WAIT] PitchAnalyzer: Running pyin extraction at {self.fps} FPS (This is computationally heavy)...")
        
        # We wrap in warnings.catch_warnings to suppress pyin's verbose output if any
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            # f0 is an array of frequencies. NaNs indicate unvoiced frames.
            f0, voiced_flag, voiced_probs = librosa.pyin(
                y, 
                fmin=self.fmin, 
                fmax=self.fmax, 
                sr=sr, 
                hop_length=self.hop_length,
                fill_na=None # leaves unvoiced as NaN
            )

        print("[WAIT] PitchAnalyzer: Compressing and serializing data...")
        
        # Calculate time for each frame
        times = librosa.times_like(f0, sr=sr, hop_length=self.hop_length)
        
        # Build compact dictionary, ignoring NaNs
        pitch_data = []
        for t, p in zip(times, f0):
            if not np.isnan(p):
                # Round to 2 decimal places to save JSON size
                pitch_data.append({
                    "t": round(float(t), 2),
                    "p": round(float(p), 2)
                })

        output_data = {
            "metadata": {
                "estimated_sa_hz": round(tonic_hz, 2),
                "estimated_sa_note": tonic_note,
                "fps": self.fps
            },
            "pitch_data": pitch_data
        }

        with open(output_json_path, "w", encoding="utf-8") as f:
            json.dump(output_data, f, separators=(',', ':')) # compact json

        print(f"[OK] PitchAnalyzer: Saved {len(pitch_data)} voiced frames to {os.path.basename(output_json_path)}")
        return True

if __name__ == "__main__":
    # Simple CLI test
    import sys
    if len(sys.argv) > 1:
        audio_file = sys.argv[1]
        out_file = audio_file.replace(".wav", "_pitch.json")
        analyzer = PitchAnalyzer()
        analyzer.analyze(audio_file, out_file)
