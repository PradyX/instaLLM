import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Whether the operating system's recognizer can be used right now.
enum PlatformSpeechStatus {
  /// The system has already allowed it; the recognizer can run.
  ready,

  /// The platform has a recognizer, but this app is not allowed to use it
  /// yet. The user grants it in the system's privacy settings.
  notAuthorized,

  /// No recognizer to call at all (Linux and Windows today, where the plugin
  /// is not registered).
  unsupported,
}

/// The operating system's speech recognizer, behind an interface so the
/// composer dictation flow can be tested without a device.
///
/// This is the lightweight alternative to the local GGUF speech model: the
/// platform does the hearing, so nothing is downloaded and short phrases
/// come back fast. The trade-off is privacy — depending on the device and
/// locale the OS may process audio on the vendor's servers, which is why
/// the local model stays the default and this engine says so where it is
/// chosen.
///
/// Reading the state ([status]) asks for nothing. Asking is a separate,
/// explicit step ([requestAuthorization]) and is only ever taken where
/// [canOwnSystemPermissionPrompt] says the system credits this app for the
/// request: a first-time request from an app another program started is read
/// against *that program's* usage description, and without one macOS aborts
/// the app instead of prompting, which takes the whole chat down. Device
/// recognition is otherwise used only where the system has already allowed it,
/// and the local engines remain the ones that always work.
/// Text heard so far, keeping the newest partial in case the recognizer never
/// marks a result final.
///
/// This is not belt-and-braces: with partial results off, the native side
/// drops every non-final result, and a final one only ever arrives when the
/// session is ended for us — so a session macOS ends by itself (its pause
/// timer) can otherwise hand back nothing at all and be reported as silence.
class RecognizedSpeech {
  String? _finalWords;
  String _partialWords = '';

  /// Records one result from the recognizer.
  void record(String words, {required bool isFinal}) {
    if (isFinal) {
      _finalWords = words;
      return;
    }
    _partialWords = words;
  }

  /// What to insert: the final transcript when the recognizer produced one,
  /// otherwise the newest words it heard.
  String get best => (_finalWords ?? _partialWords).trim();

  bool get hasWords => best.isNotEmpty;

  void clear() {
    _finalWords = null;
    _partialWords = '';
  }
}

abstract class PlatformSpeechListener {
  /// Whether device recognition can run, without asking for anything.
  Future<PlatformSpeechStatus> status();

  /// The reason the recognizer last stopped, when it reported one. Surfaced
  /// so an empty transcript can say why instead of always claiming silence.
  String? get lastError;

  /// Asks the system for permission, from an explicit user action only: this
  /// is the call that shows the system prompt, and the one macOS aborts the
  /// app for where the launch cannot own it. Returns
  /// [PlatformSpeechStatus.notAuthorized] without asking in that case — see
  /// [canOwnSystemPermissionPrompt] for the reason.
  Future<PlatformSpeechStatus> requestAuthorization();

  /// Starts listening. Returns [PlatformSpeechStatus.ready] when the
  /// recognizer is open, otherwise why it could not be.
  Future<PlatformSpeechStatus> listen();

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
  /// [permissionCheck], [prepare] and [canAsk] exist because the plugin's own
  /// class has a factory constructor and cannot be faked; they let the rules
  /// this class enforces — check permission, never ask on its own, and never
  /// ask where the system would blame the app's launcher — be tested without a
  /// device.
  PlatformSpeechService({
    stt.SpeechToText? speech,
    Future<bool> Function()? permissionCheck,
    Future<bool> Function()? prepare,
    bool Function()? canAsk,
  }) : _speech = speech ?? stt.SpeechToText(),
       _permissionCheck = permissionCheck,
       _prepare = prepare,
       _canAsk = canAsk ?? canOwnSystemPermissionPrompt;

  final stt.SpeechToText _speech;
  final Future<bool> Function()? _permissionCheck;
  final Future<bool> Function()? _prepare;
  final bool Function() _canAsk;

  bool _ready = false;
  bool _listening = false;
  String? _lastError;
  Completer<String>? _result;
  final RecognizedSpeech _capture = RecognizedSpeech();

  @override
  bool get isListening => _listening;

  @override
  String? get lastError => _lastError;

  @override
  Future<PlatformSpeechStatus> status() async {
    if (_ready) return PlatformSpeechStatus.ready;
    final bool permitted;
    try {
      // A check, not a request: see the note on [PlatformSpeechListener].
      permitted = await (_permissionCheck ?? () => _speech.hasPermission)();
    } catch (_) {
      // No recognizer on this platform, so the call cannot even be made.
      return PlatformSpeechStatus.unsupported;
    }
    if (!permitted) return PlatformSpeechStatus.notAuthorized;
    try {
      _ready = await _initializeRecognition();
    } catch (_) {
      _ready = false;
    }
    return _ready
        ? PlatformSpeechStatus.ready
        : PlatformSpeechStatus.notAuthorized;
  }

  @override
  Future<PlatformSpeechStatus> requestAuthorization() async {
    if (_ready) return PlatformSpeechStatus.ready;
    // Asking where the system does not credit this launch is what ends the
    // app, so it is refused here rather than attempted — the caller has the
    // same answer and can explain it instead of prompting. See
    // [canOwnSystemPermissionPrompt].
    if (!_canAsk()) return PlatformSpeechStatus.notAuthorized;
    try {
      // This is the request: the plugin prompts when the system has not
      // decided yet, and answers from the stored decision otherwise.
      _ready = await _initializeRecognition();
    } on MissingPluginException {
      return PlatformSpeechStatus.unsupported;
    } catch (_) {
      _ready = false;
    }
    if (_ready) return PlatformSpeechStatus.ready;
    // A refusal is stored by the system, so asking again cannot help.
    return await status() == PlatformSpeechStatus.unsupported
        ? PlatformSpeechStatus.unsupported
        : PlatformSpeechStatus.notAuthorized;
  }

  /// Prepares the recognizer, prompting for permission when the system has
  /// not decided yet.
  ///
  /// The plugin reports recognition failures through the listener it is given
  /// here, which is why the reason is kept: a session that ends in silence
  /// otherwise cannot be told apart from one that failed.
  Future<bool> _initializeRecognition() async {
    final prepare = _prepare;
    return prepare != null
        ? await prepare()
        : await _speech.initialize(
            onError: (error) => _lastError = error.errorMsg,
            debugLogging: false,
          );
  }

  @override
  Future<PlatformSpeechStatus> listen() async {
    if (_listening) return PlatformSpeechStatus.ready;
    final status = await this.status();
    if (status != PlatformSpeechStatus.ready) return status;
    _result = Completer<String>();
    _lastError = null;
    _capture.clear();
    try {
      await _speech.listen(
        onResult: (result) {
          _capture.record(result.recognizedWords, isFinal: result.finalResult);
          if (result.finalResult && !(_result?.isCompleted ?? true)) {
            _result?.complete(result.recognizedWords);
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenFor: const Duration(minutes: 2),
          pauseFor: const Duration(seconds: 5),
          // Partial results are kept, not just the final one: macOS ends a
          // session on its own pause timer, and the words heard before that
          // are the whole transcript.
          partialResults: true,
          cancelOnError: true,
        ),
      );
    } catch (_) {
      _result?.complete('');
      return PlatformSpeechStatus.notAuthorized;
    }
    _listening = _speech.isListening;
    if (!_listening) {
      _result?.complete('');
      return PlatformSpeechStatus.notAuthorized;
    }
    return PlatformSpeechStatus.ready;
  }

  @override
  Future<String> stop() async {
    final wasListening = _listening;
    if (wasListening) {
      try {
        await _speech.stop();
      } catch (_) {}
      _listening = false;
    }
    final result = _result;
    _result = null;
    // A session the plugin already ended delivers its final result through
    // the plugin's own short final timer; asking ourselves to stop is the case
    // that needs the longer wait for the recognizer to answer.
    final waitFor = wasListening
        ? const Duration(seconds: 10)
        : const Duration(seconds: 2);
    if (result != null && !result.isCompleted) {
      try {
        await result.future.timeout(waitFor);
      } catch (_) {
        // Nothing final arrived; whatever was heard is still worth keeping.
      }
    }
    final transcript = _capture.best;
    _capture.clear();
    return transcript;
  }

  @override
  Future<void> cancel() async {
    try {
      await _speech.cancel();
    } catch (_) {}
    _listening = false;
    _capture.clear();
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

/// Whether device recognition can be used here, and why not when it cannot.
final platformSttStatusProvider = FutureProvider<PlatformSpeechStatus>((ref) {
  return ref.watch(platformSpeechProvider).status();
});

/// Whether macOS would show this app a first-time privacy prompt, or end it
/// for asking where the request cannot be granted.
///
/// macOS credits a permission request to the *responsible* process — the
/// program that started the app — and reads the usage description it insists
/// on out of that program's `Info.plist`, not the app's own. Started from
/// Finder, the Dock or `open`, the app is its own responsible process and the
/// prompt appears the way it does for any app; started by `flutter run`, a
/// terminal or an IDE, the launcher is what macOS holds responsible, and a
/// launcher with no speech-recognition description makes macOS abort the app
/// instead of prompting (`__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__` in the
/// crash report — how Freebuff, which declares a microphone description and no
/// speech-recognition one, takes InstaLLM down on the first request).
///
/// A LaunchServices launch is started by `launchd`, so its parent is pid 1;
/// anything else has the launching program as its parent, which is the case
/// this refuses. Every platform other than macOS answers true: no other
/// platform reads the launcher's `Info.plist`.
bool canOwnSystemPermissionPrompt({int Function()? parentProcessId}) {
  if (!Platform.isMacOS) return true;
  return (parentProcessId ?? systemParentProcessId)() == 1;
}

/// `pid_t getppid(void)` as libc declares it, and as Dart calls it.
typedef _GetPpidNative = Int32 Function();
typedef _GetPpid = int Function();

/// The process that started this app, or 0 when it cannot be read — an
/// unreadable launch is not a known-safe one, so it is not asked either.
int systemParentProcessId() {
  try {
    final getppid = _systemLibrary.lookupFunction<_GetPpidNative, _GetPpid>(
      'getppid',
    );
    return getppid();
  } catch (_) {
    return 0;
  }
}

/// libc, opened by path rather than through `DynamicLibrary.process()` so the
/// symbol is looked up the same way on every macOS build.
DynamicLibrary? _libc;

DynamicLibrary get _systemLibrary =>
    _libc ??= DynamicLibrary.open('/usr/lib/libSystem.B.dylib');

/// Whether the settings may offer to ask for device recognition here, or have
/// to explain why they cannot. See [canOwnSystemPermissionPrompt].
final systemPermissionPromptOwnershipProvider = Provider<bool>(
  (ref) => canOwnSystemPermissionPrompt(),
);
