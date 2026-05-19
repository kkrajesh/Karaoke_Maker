import 'package:record/record.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';

void main() async {
  final record = AudioRecorder();
  if (await record.hasPermission()) {
    final stream = await record.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 44100,
      numChannels: 1,
    ));
    
    final pitchDetectorDart = PitchDetector(44100, 2000);
    
    stream.listen((data) {
      // Convert Uint8List to List<double>
      // Call pitch detector
    });
  }
}
