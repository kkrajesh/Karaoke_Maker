import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';

class MicPitchService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _micStreamSub;
  
  // Expose a stream of detected frequencies (Hz)
  final StreamController<double> _pitchStreamController = StreamController<double>.broadcast();
  Stream<double> get pitchStream => _pitchStreamController.stream;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  final int sampleRate = 44100;
  final int bufferSize = 2048; // Accumulate samples before detection

  late PitchDetector _pitchDetector;
  List<Uint8List> _byteBuffer = [];
  int _accumulatedBytes = 0;

  MicPitchService() {
    _pitchDetector = PitchDetector(
      audioSampleRate: sampleRate.toDouble(), 
      bufferSize: bufferSize
    );
  }

  Future<bool> start() async {
    if (_isRecording) return true;

    if (await _audioRecorder.hasPermission()) {
      try {
        final stream = await _audioRecorder.startStream(
          RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: sampleRate,
            numChannels: 1,
          ),
        );

        _isRecording = true;
        _byteBuffer.clear();
        _accumulatedBytes = 0;

        _micStreamSub = stream.listen((Uint8List data) {
          _processAudioData(data);
        });

        return true;
      } catch (e) {
        debugPrint('Error starting mic stream: $e');
        return false;
      }
    }
    return false;
  }

  Future<void> _processAudioData(Uint8List data) async {
    _byteBuffer.add(data);
    _accumulatedBytes += data.length;

    // bufferSize is number of samples. For 16-bit PCM, 1 sample = 2 bytes.
    final targetBytes = bufferSize * 2;

    while (_accumulatedBytes >= targetBytes) {
      // Create a contiguous buffer of exactly targetBytes
      final chunkBytes = Uint8List(targetBytes);
      int written = 0;
      
      while (written < targetBytes) {
        final first = _byteBuffer.first;
        final needed = targetBytes - written;
        
        if (first.length <= needed) {
          chunkBytes.setRange(written, written + first.length, first);
          written += first.length;
          _byteBuffer.removeAt(0);
        } else {
          chunkBytes.setRange(written, written + needed, first.sublist(0, needed));
          _byteBuffer[0] = first.sublist(needed);
          written += needed;
        }
      }
      
      _accumulatedBytes -= targetBytes;

      final result = await _pitchDetector.getPitchFromIntBuffer(chunkBytes);
      
      if (result.probability > 0.8 && result.pitch > 0) {
        _pitchStreamController.add(result.pitch);
      }
    }
  }

  Future<void> stop() async {
    if (!_isRecording) return;
    
    await _micStreamSub?.cancel();
    await _audioRecorder.stop();
    
    _isRecording = false;
    _byteBuffer.clear();
    _accumulatedBytes = 0;
  }

  void dispose() {
    stop();
    _pitchStreamController.close();
    _audioRecorder.dispose();
  }
}
