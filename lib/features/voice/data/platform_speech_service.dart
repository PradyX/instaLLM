import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// The operating system's speech recognizer, behind an interface so the
/// composer dictation flow can be tested without a device.
///
/// This is the lightweight alternative to the local GGUF speech model: the
/// platform does the hearing, so nothing is downloaded and short phrases
/// come back fast. The trade-off is privacy — depending on the device and
/// locale the OS may process audio on the vendor's servers, which is why
/// the local model stays the default and this engine says so where it is
/// chosen. Unsupported platforms (Linux today) simply report unavailable.
abstract class PlatformSpeechListener {
  /// Prepares the recognizer; false when this device has no usable speech
  /// service. Never throws.
  Future<bool> initialize();

  /// Starts listening. Returns false (and does nothing) when the recognizer
  /// is unavailable or already listening.
  Future<bool> listen();

  /// Stops listening and returns the final transcript, or '' when nothing
  /// recognizable was heard.
  Future<String> stop();

  /// Stops listening and drops whatever was heard.
  Future<void> cancel();

  /// True while the microphone is open for platform recognition.
  bool get isListening;
}

/// Recognizes through the `speech_to_text` plugin.
class PlatformSpeechService implements PlatformSpeechListener {
  PlatformSpeechService({stt.SpeechToText? speech})
    : _speech = speech ?? stt.SpeechToText();

  final stt.SpeechToText _speech;

  bool _available = false;
  bool _listening = false;
  Completer<String>? _result;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> initialize() async {
    if (_available) return true;
    try {
      _available = await _speech.initialize(
        onError: (_) {},
        debugLogging: false,
      );
    } catch (_) {
      _available = false;
    }
    return _available;
  }

  @override
  Future<bool> listen() async {
    if (_listening) return true;
    final available = await initialize();
    if (!available) return false;
    _result = Completer<String>();
    try {
      await _speech.listen(
        onResult: (result) {
          if (result.finalResult && !(_result?.isCompleted ?? true)) {
            _result?.complete(result.recognizedWords);
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenFor: const Duration(minutes: 2),
          pauseFor: const Duration(seconds: 5),
          partialResults: false,
          cancelOnError: true,
        ),
      );
    } catch (_) {
      _result?.complete('');
      return false;
    }
    _listening = _speech.isListening;
    if (!_listening) _result?.complete('');
    return _listening;
  }

  @override
  Future<String> stop() async {
    if (!_listening) return '';
    try {
      await _speech.stop();
    } catch (_) {}
    _listening = false;
    final result = _result;
    _result = null;
    if (result == null) return '';
    try {
      return await result.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      return '';
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _speech.cancel();
    } catch (_) {}
    _listening = false;
    _result?.complete('');
    _result = null;
  }
}

/// The shared platform recognizer.
final platformSpeechProvider = Provider<PlatformSpeechListener>((ref) {
  final service = PlatformSpeechService();
  ref.onDispose(service.cancel);
  return service;
});

/// Whether device recognition can run here. False on platforms without a
/// speech service (Linux today); the settings hide the engine there.
final platformSttAvailableProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.watch(platformSpeechProvider).initialize();
  } catch (_) {
    return false;
  }
});
