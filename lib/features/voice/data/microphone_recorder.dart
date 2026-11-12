import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Longest clip one recording may capture.
///
/// A speech model spends a lot of context per second of audio, so this bound
/// keeps a single recording from costing more than a phone-class model can
/// afford. It is a capture limit, not a target: the user stops whenever the
/// thought is finished.
const Duration maximumRecordingLength = Duration(minutes: 2);

/// Sample rate captured audio is written with.
///
/// Speech models take 16 kHz mono, which also keeps the file small enough to
/// read in one go instead of streaming a large buffer around.
const int recordingSampleRate = 16000;

/// The quietest reading a level meter still shows, in dBFS.
///
/// `record` reports decibels relative to full scale, so a quiet room sits far
/// below zero. Everything under this floor reads as silence, which keeps an
/// idle meter at zero instead of a bar that twitches at nothing.
const double microphoneSilenceDb = -55;

/// A dBFS reading as a 0..1 meter value.
double microphoneLevelFromDb(double decibels) =>
    ((decibels - microphoneSilenceDb) / -microphoneSilenceDb).clamp(0.0, 1.0);

/// The microphone, behind an interface so the recording flow can be tested
/// without a device.
abstract class MicrophoneRecorder {
  /// Asks for the microphone, returning false when the user refuses.
  ///
  /// Granting is a platform concern: Android, iOS and macOS prompt here, and
  /// desktop platforms answer without a prompt.
  Future<bool> requestPermission();

  /// Starts capturing to a new file and returns its path.
  Future<String> start();

  /// Stops capturing and returns the clip, or null when none was captured.
  Future<String?> stop();

  /// Stops capturing and removes the clip (used when the user discards it).
  Future<void> cancel();

  /// Removes a clip that is no longer needed.
  Future<void> deleteRecording(String path);

  /// Live input levels, 0..1, while a capture is running.
  ///
  /// [interval] is how often a reading arrives; the stream goes quiet when the
  /// capture ends.
  Stream<double> amplitudes({Duration interval});

  /// Releases the platform recorder.
  void dispose();
}

/// Records from the device microphone through the `record` plugin.
///
/// Audio is written as wav inside the app's own support directory, in the
/// format local speech models read, and nothing is uploaded: the file is handed
/// to the bundled runtime and removed once it has been transcribed.
///
/// Recording needs the platform's own encoder and permission. On Linux the
/// plugin shells out to PulseAudio tools and ffmpeg, so a machine without them
/// reports that instead of staying silent.
class RecordMicrophoneRecorder implements MicrophoneRecorder {
  RecordMicrophoneRecorder({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> requestPermission() => _recorder.hasPermission();

  @override
  Future<String> start() async {
    final directory = Directory(
      p.join(await _supportDirectoryPath(), 'voice_recordings'),
    );
    await directory.create(recursive: true);
    final path = p.join(
      directory.path,
      'clip-${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: recordingSampleRate,
        numChannels: 1,
      ),
      path: path,
    );
    return path;
  }

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> deleteRecording(String path) async {
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }

  /// The recorder's own dBFS meter as a 0..1 level, sampled at [interval].
  ///
  /// The stream only ticks while a capture is running, so the page never has to
  /// poll the device.
  @override
  Stream<double> amplitudes({
    Duration interval = const Duration(milliseconds: 60),
  }) => _recorder
      .onAmplitudeChanged(interval)
      .map((amplitude) => microphoneLevelFromDb(amplitude.current));

  @override
  void dispose() => _recorder.dispose();

  Future<String> _supportDirectoryPath() async {
    final directory = await getApplicationSupportDirectory();
    return directory.path;
  }
}
