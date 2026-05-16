import sys
import soundfile
import torch
import torchaudio

# Monkeypatch torchaudio.load to use soundfile directly
# This bypasses the torchcodec dependency issue on Windows where libtorchcodec_core4.dll is missing.
def custom_load(filepath, **kwargs):
    # Demucs passes strings or Path objects
    data, samplerate = soundfile.read(str(filepath), dtype='float32')
    tensor = torch.from_numpy(data)
    
    # torchaudio expects (channels, frames)
    if tensor.ndim == 1:
        tensor = tensor.unsqueeze(0)
    else:
        tensor = tensor.T
        
    return tensor, samplerate

def custom_save(filepath, src, sample_rate, **kwargs):
    # torchaudio outputs (channels, frames), soundfile expects (frames, channels)
    if src.ndim == 2:
        src = src.T
    soundfile.write(str(filepath), src.numpy(), sample_rate)

# Apply the patches
torchaudio.load = custom_load
torchaudio.save = custom_save

# Now launch demucs
from demucs.separate import main

if __name__ == "__main__":
    # The arguments are passed via sys.argv
    main()
