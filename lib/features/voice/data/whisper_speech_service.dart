import 'dart:isolate';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/utils/logger.dart';
import 'package:installm/features/voice/data/audio_clip_reader.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Runs one audio file through a Whisper model.
///
/// An interface so the transcription flow can be tested without the native
/// library, which only exists inside a built app.
abstract class WhisperRunner {
  /// Transcribes [audioPath] with the model made of [encoderPath],
  /// [decoderPath] and [tokensPath].
  ///
  /// [language] is what to expect in the clip; `auto` lets the model decide.
  Future<String> transcribe({
    required String encoderPath,
    required String decoderPath,
    required String tokensPath,
    required String audioPath,
    String language = autoLanguage,
  });

  /// Tells a run that its result is no longer wanted.
  ///
  /// An offline Whisper decode is a single native pass with no abort hook:
  /// once it starts, it runs to the end. The screen still reports the stop,
  /// and the words the pass finished with are kept — throwing away a decode
  /// the user waited for would only lose work.
  Future<void> cancel();
}

/// Language value meaning "let the model decide".
const String autoLanguage = 'auto';

/// Whisper through sherpa-onnx.
class SherpaWhisperRunner implements WhisperRunner {
  SherpaWhisperRunner();

  @override
  Future<String> transcribe({
    required String encoderPath,
    required String decoderPath,
    required String tokensPath,
    required String audioPath,
    String language = autoLanguage,
  }) async {
    // Decoding a clip is one blocking native call, so it runs on a worker
    // isolate: the interface stays responsive while a long clip is decoded,
    // and the recognizer (with its model in memory) is released as soon as
    // the isolate ends instead of being held for the life of the app.
    final text = await Isolate.run(
      () => _decodeClip(
        encoderPath: encoderPath,
        decoderPath: decoderPath,
        tokensPath: tokensPath,
        audioPath: audioPath,
        language: language,
        threads: _threadsForThisDevice,
      ),
    );
    AppLogger.debug('Whisper decoded ${text.length} characters');
    return text;
  }

  @override
  Future<void> cancel() async {
    // See the note on [WhisperRunner.cancel]: there is nothing to interrupt,
    // so this deliberately does not pretend otherwise.
  }

  /// Threads to decode with.
  ///
  /// Deliberately leaves a core free: a chat model may be loaded in the same
  /// process, and taking every core makes the whole app feel stuck while a
  /// clip is transcribed.
  static int get _threadsForThisDevice {
    final processors = Platform.numberOfProcessors;
    if (processors <= 2) return 1;
    return (processors - 1).clamp(2, 4).toInt();
  }
}

/// Decodes [audioPath] and returns what was heard.
///
/// Runs on a worker isolate, so it initializes the native binding for that
/// isolate and frees its recognizer before returning.
String _decodeClip({
  required String encoderPath,
  required String decoderPath,
  required String tokensPath,
  required String audioPath,
  required String language,
  required int threads,
}) {
  sherpa.initBindings();
  // Read in Dart rather than with `sherpa.readWave`: the native reader rejects
  // the extensible WAV header macOS writes for this app's own recordings and
  // returns an empty wave instead of an error — see [readAudioClip].
  final clip = readAudioClip(audioPath);
  if (clip.isEmpty) {
    throw StateError('The clip could not be read as audio: $audioPath');
  }

  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: encoderPath,
          decoder: decoderPath,
          // An empty language is how the model is asked to detect it.
          language: language == autoLanguage ? '' : language,
        ),
        tokens: tokensPath,
        numThreads: threads,
        // CPU decoding runs everywhere, which is what the app can verify on
        // every platform; the debug flag would log the model's own chatter.
        provider: 'cpu',
        debug: false,
      ),
    ),
  );

  try {
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: clip.samples, sampleRate: clip.sampleRate);
      recognizer.decode(stream);
      return recognizer.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  } finally {
    recognizer.free();
  }
}

/// The Whisper runner this app transcribes clips with.
///
/// One instance: a decode is one native pass at a time, so a second run would
/// only queue behind the first. Tests override this with a fake.
final whisperRunnerProvider = Provider<WhisperRunner>((ref) {
  final runner = SherpaWhisperRunner();
  ref.onDispose(runner.cancel);
  return runner;
});
