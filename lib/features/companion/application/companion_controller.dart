import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/companion/application/companion_settings_controller.dart';
import 'package:installm/features/companion/application/companion_transcriber.dart';
import 'package:installm/features/companion/application/companion_turn_runner.dart';
import 'package:installm/features/voice/application/recording_controller.dart';
import 'package:installm/features/voice/application/tts_controller.dart';
import 'package:installm/features/voice/data/microphone_recorder.dart';

/// What the Companion is doing.
enum CompanionPhase {
  /// Waiting for the user to speak.
  idle,

  /// The microphone is open.
  listening,

  /// The clip is being turned into words.
  transcribing,

  /// The model is writing an answer.
  thinking,

  /// The answer is being read aloud.
  speaking,
}

/// One spoken exchange, held only in this page's memory.
class CompanionExchange {
  const CompanionExchange({required this.heard, required this.said});

  /// What the speech model heard.
  final String heard;

  /// What the Companion said back.
  final String said;
}

/// The Companion page's own state: what it is doing, its meter, and the turns
/// of this visit.
///
/// Nothing here is a chat. The Companion keeps no conversation, writes no
/// message, and stores no audio: an exchange lives in this list until the page
/// goes away, which is what "ephemeral" means for this surface.
class CompanionState {
  const CompanionState({
    this.phase = CompanionPhase.idle,
    this.levels = const <double>[0, 0, 0, 0, 0, 0, 0],
    this.listeningElapsed = Duration.zero,
    this.exchanges = const <CompanionExchange>[],
    this.errorMessage,
    this.noticeMessage,
  });

  final CompanionPhase phase;

  /// The most recent input levels, oldest first: one bar per entry.
  final List<double> levels;

  /// How long the microphone has been open in this capture, for the pill's
  /// readout. It is derived from the endpoint checks, not from the wall clock.
  final Duration listeningElapsed;

  /// This visit's spoken turns, oldest first.
  final List<CompanionExchange> exchanges;

  /// Something the user has to fix, such as a refused microphone.
  final String? errorMessage;

  /// A lasting note about the last turn.
  final String? noticeMessage;

  bool get isListening => phase == CompanionPhase.listening;

  /// True while a captured turn is being processed or read aloud.
  bool get isBusy =>
      phase == CompanionPhase.transcribing ||
      phase == CompanionPhase.thinking ||
      phase == CompanionPhase.speaking;

  /// The word the pill shows for this phase.
  String get phaseLabel => companionPhaseLabel(phase);

  CompanionState copyWith({
    CompanionPhase? phase,
    List<double>? levels,
    Duration? listeningElapsed,
    List<CompanionExchange>? exchanges,
    String? errorMessage,
    String? noticeMessage,
    bool clearError = false,
    bool clearNotice = false,
  }) {
    return CompanionState(
      phase: phase ?? this.phase,
      levels: levels ?? this.levels,
      listeningElapsed: listeningElapsed ?? this.listeningElapsed,
      exchanges: exchanges ?? this.exchanges,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      noticeMessage: clearNotice ? null : noticeMessage ?? this.noticeMessage,
    );
  }
}

/// The one place the page's words for each phase are written.
String companionPhaseLabel(CompanionPhase phase) => switch (phase) {
  CompanionPhase.idle => 'Ready',
  CompanionPhase.listening => 'Listening…',
  CompanionPhase.transcribing => 'Transcribing…',
  CompanionPhase.thinking => 'Thinking…',
  CompanionPhase.speaking => 'Speaking…',
};

final companionControllerProvider =
    NotifierProvider<CompanionController, CompanionState>(
      CompanionController.new,
    );

/// Runs one spoken turn: listen, transcribe, answer, speak.
///
/// The microphone runs only while the page is visible, and the clip is deleted
/// as soon as its words are taken. The words are not saved: the answer comes
/// from a one-off prompt on the selected model, so no chat grows out of this
/// and nothing survives leaving the page.
class CompanionController extends Notifier<CompanionState> {
  /// How many bars the meter holds; the page draws one per entry.
  static const int barCount = 7;

  /// Turns kept on the page. The oldest fades out rather than scrolling.
  static const int historyLimit = 4;

  static const Duration _levelInterval = Duration(milliseconds: 60);

  static const List<double> _silentLevels = <double>[0, 0, 0, 0, 0, 0, 0];

  /// The lowest a reading can be and still count as speech.
  ///
  /// A fixed floor is not enough on real hardware: this Mac's quiet room reads
  /// about 0.25 on the meter, so a fixed 0.12 would call the room noise a
  /// sentence and the pause would never arrive. The threshold is therefore
  /// relative to the last quiet reading, with this as the floor for a truly
  /// silent input.
  static const double speechFloor = 0.12;

  /// How far above the background a reading must sit to be speech.
  static const double speechMargin = 0.10;

  /// How often the pause is checked while listening.
  static const Duration _endpointCheck = Duration(milliseconds: 200);

  /// How long a hands-free follow-up waits for the user to start speaking.
  ///
  /// After an answer the microphone reopens on its own; if nothing is said in
  /// this window it closes again, so an idle room is never recorded for long.
  static const Duration followUpWindow = Duration(seconds: 12);

  StreamSubscription<double>? _levels;
  MicrophoneRecorder? _capturing;

  /// Ends the turn when the user pauses, and closes a follow-up nobody used.
  Timer? _endpoint;

  /// The last reading that was not speech: this machine's own background.
  ///
  /// Kept across captures, so a follow-up does not have to relearn the room
  /// and mistake its noise for the start of a sentence.
  double _ambientLevel = 0;

  /// Consecutive speech readings, so one door click is not a sentence.
  int _speechRun = 0;

  /// How many readings in a row count as speech (about 180 ms at the meter's
  /// 60 ms interval).
  static const int speechRunToCount = 3;

  /// Elapsed time while listening, counted in endpoint checks rather than
  /// wall-clock time: the check is what the pause is measured against, and a
  /// timer makes that the same on a device and under a test's clock.
  int _quietChecks = 0;
  int _openChecks = 0;
  bool _heardSpeech = false;

  /// Whether a spoken answer should reopen the microphone, so a conversation
  /// does not need a tap per turn.
  bool _resumeAfterTurn = false;

  /// True for a capture the Companion opened itself after an answer, which is
  /// the only kind that closes after [followUpWindow] with nothing said.
  bool _autoStarted = false;

  /// Numbers the current turn of work, so work from an older one (a page that
  /// went away, a stopped reply) can tell it was superseded and stay quiet.
  int _turn = 0;

  @override
  CompanionState build() {
    ref.onDispose(_release);
    return const CompanionState();
  }

  /// Asks for the microphone and starts metering the input.
  Future<void> start({bool automatic = false}) async {
    if (state.isListening || state.isBusy) return;

    // The Companion is off until the user turns it on, and the page is not the
    // only way in: a stored switch has to be able to refuse the microphone.
    if (!ref.read(companionSettingsProvider).settings.enabled) {
      state = state.copyWith(
        errorMessage:
            'The Companion is off. Turn it on in Settings › Companion, then '
            'try again.',
      );
      return;
    }

    // One capture at a time: dictation and the voice loop use the same device.
    if (ref.read(recordingControllerProvider).isRecording) {
      state = state.copyWith(
        errorMessage:
            'Another recording is using the microphone. Stop it, then open '
            'the Companion microphone again.',
      );
      return;
    }

    final recorder = ref.read(microphoneRecorderProvider);
    try {
      if (!await recorder.requestPermission()) {
        if (!ref.mounted) return;
        state = state.copyWith(
          errorMessage:
              'InstaLLM needs microphone access for the Companion. Grant it '
              'for this app in the system settings, then try again.',
        );
        return;
      }

      await recorder.start();
      if (!ref.mounted) {
        await recorder.cancel();
        return;
      }

      _capturing = recorder;
      _heardSpeech = false;
      _speechRun = 0;
      _quietChecks = 0;
      _openChecks = 0;
      _resumeAfterTurn = false;
      _autoStarted = automatic;
      state = state.copyWith(
        phase: CompanionPhase.listening,
        levels: _silentLevels,
        clearError: true,
        clearNotice: true,
      );
      _endpoint?.cancel();
      _endpoint = Timer.periodic(_endpointCheck, (_) => _checkEndpoint());
      _levels = recorder
          .amplitudes(interval: _levelInterval)
          .listen(
            _onLevel,
            onError: (Object error) {
              if (ref.mounted) {
                state = state.copyWith(errorMessage: _failureMessage(error));
              }
            },
          );
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(errorMessage: _failureMessage(error));
    }
  }

  /// Ends the capture and runs the turn: words, answer, then the answer aloud.
  Future<void> stop() async {
    if (!state.isListening) return;

    final turn = ++_turn;
    final recorder = _capturing;
    _capturing = null;

    // The device is stopped first: a stop must never wait on the meter's
    // subscription going away.
    final subscription = _levels;
    _levels = null;
    if (subscription != null) unawaited(subscription.cancel());
    _endpoint?.cancel();
    _endpoint = null;

    String? clipPath;
    try {
      clipPath = await recorder?.stop();
    } catch (error) {
      if (!ref.mounted || turn != _turn) return;
      state = state.copyWith(
        phase: CompanionPhase.idle,
        levels: _silentLevels,
        errorMessage: _failureMessage(error),
      );
      return;
    }

    if (!ref.mounted || turn != _turn) {
      if (clipPath != null) unawaited(recorder?.deleteRecording(clipPath));
      return;
    }
    if (clipPath == null) {
      state = state.copyWith(
        phase: CompanionPhase.idle,
        levels: _silentLevels,
        noticeMessage: 'Nothing was captured.',
      );
      return;
    }

    // Nothing above the background was ever heard, so there is no sentence to
    // transcribe. A speech model handed a silent clip invents words, and a
    // follow-up that invents words makes the Companion answer itself.
    if (!_heardSpeech) {
      unawaited(recorder?.deleteRecording(clipPath));
      state = state.copyWith(
        phase: CompanionPhase.idle,
        levels: _silentLevels,
        noticeMessage: 'Nothing was heard. Tap the pill and speak.',
      );
      return;
    }

    state = state.copyWith(
      phase: CompanionPhase.transcribing,
      levels: _silentLevels,
      clearError: true,
      clearNotice: true,
    );

    // The clip exists only for as long as its words take to extract.
    final String transcript;
    try {
      transcript = await ref
          .read(companionTranscriberProvider)
          .transcribe(clipPath);
    } catch (error) {
      unawaited(recorder?.deleteRecording(clipPath));
      if (!ref.mounted || turn != _turn) return;
      state = state.copyWith(
        phase: CompanionPhase.idle,
        errorMessage: _messageOf(error),
      );
      return;
    }
    unawaited(recorder?.deleteRecording(clipPath));

    if (!ref.mounted || turn != _turn) return;
    if (transcript.trim().isEmpty) {
      state = state.copyWith(
        phase: CompanionPhase.idle,
        noticeMessage:
            'No words were audible in that. Speak a little closer to the '
            'microphone and try again.',
      );
      return;
    }

    state = state.copyWith(phase: CompanionPhase.thinking);

    final String? reply;
    try {
      reply = await ref.read(companionTurnRunnerProvider).answer(transcript);
    } catch (error) {
      if (!ref.mounted || turn != _turn) return;
      state = state.copyWith(
        phase: CompanionPhase.idle,
        errorMessage: _messageOf(error),
      );
      return;
    }

    if (!ref.mounted || turn != _turn) return;
    if (reply == null || reply.trim().isEmpty) {
      state = state.copyWith(
        phase: CompanionPhase.idle,
        exchanges: _withExchange(
          CompanionExchange(heard: transcript, said: ''),
        ),
        noticeMessage: 'The model had nothing to say to that.',
      );
      return;
    }

    // From here the answer reopens the microphone on its own, which is the
    // hands-free half of the loop.
    _resumeAfterTurn = true;
    state = state.copyWith(
      phase: CompanionPhase.speaking,
      exchanges: _withExchange(
        CompanionExchange(heard: transcript, said: reply),
      ),
      clearError: true,
      clearNotice: true,
    );

    try {
      await ref.read(ttsControllerProvider.notifier).speak(reply);
    } catch (error) {
      if (!ref.mounted || turn != _turn) return;
      state = state.copyWith(
        phase: CompanionPhase.idle,
        noticeMessage:
            'The answer could be written but not read aloud: '
            '${_messageOf(error)}',
      );
      return;
    }

    if (!ref.mounted || turn != _turn) return;
    state = state.copyWith(phase: CompanionPhase.idle);

    // Hands-free: the next turn starts by itself, bounded by the follow-up
    // window and the pause, so the user can simply keep talking.
    if (_resumeAfterTurn &&
        ref.read(companionSettingsProvider).settings.enabled) {
      _resumeAfterTurn = false;
      await start(automatic: true);
    }
  }

  /// Ends whatever is running, keeping what has already been said.
  Future<void> interrupt() async {
    _turn++;
    _resumeAfterTurn = false;
    if (state.isListening) {
      await stop();
      return;
    }

    ref.read(companionTurnRunnerProvider).interrupt();
    await ref.read(ttsControllerProvider.notifier).stop();
    if (!ref.mounted) return;
    state = state.copyWith(
      phase: CompanionPhase.idle,
      levels: _silentLevels,
      noticeMessage: 'Stopped.',
    );
  }

  /// Stops without waiting, for a page that is being disposed.
  void stopSilently() {
    _turn++;
    _resumeAfterTurn = false;
    _autoStarted = false;
    _endpoint?.cancel();
    _endpoint = null;
    _release();
    unawaited(ref.read(ttsControllerProvider.notifier).stop());
  }

  List<CompanionExchange> _withExchange(CompanionExchange exchange) {
    final all = [...state.exchanges, exchange];
    if (all.length <= historyLimit) return all;
    return all.sublist(all.length - historyLimit);
  }

  void _onLevel(double value) {
    if (!ref.mounted || !state.isListening) return;
    final level = value.clamp(0.0, 1.0);

    // A reading is speech when it rises above the background this machine has
    // been hearing. The background falls at once and rises slowly, so a room
    // settles quickly, a sentence does not lift the bar it is measured against,
    // and a blip has to last [speechRunToCount] readings to count.
    final threshold = math.max(speechFloor, _ambientLevel + speechMargin);
    if (level >= threshold) {
      _speechRun++;
      if (_speechRun >= speechRunToCount) {
        _heardSpeech = true;
        _quietChecks = 0;
      }
    } else {
      _speechRun = 0;
    }

    if (_ambientLevel <= 0) {
      _ambientLevel = math.max(level, 0.05);
    } else if (level < _ambientLevel) {
      _ambientLevel = level;
    } else {
      _ambientLevel += (level - _ambientLevel) * 0.01;
    }
    final levels = [...state.levels.skip(1), level];
    state = state.copyWith(levels: levels);
  }

  /// Ends the capture on the pause the settings describe.
  ///
  /// A pause only counts once something has been said: a page opened and left
  /// alone must not decide that silence is a finished sentence. The follow-up
  /// window covers the other end, closing a microphone nobody spoke into.
  void _checkEndpoint() {
    if (!ref.mounted || !state.isListening) return;
    final pause = ref.read(companionSettingsProvider).settings.silenceTimeout;
    final checkMs = _endpointCheck.inMilliseconds;

    // The pill's elapsed readout moves once a second, not on every check.
    _openChecks++;
    if (_openChecks % 5 == 0) {
      state = state.copyWith(
        listeningElapsed: Duration(milliseconds: _openChecks * checkMs),
      );
    }

    if (_heardSpeech) {
      _quietChecks++;
      if (_quietChecks * checkMs >= pause.inMilliseconds) unawaited(stop());
      return;
    }

    // The first capture is the user's own tap, so it waits as long as they
    // need; only an automatic follow-up closes itself.
    if (_autoStarted &&
        _openChecks * checkMs >= followUpWindow.inMilliseconds) {
      unawaited(_closeUnusedFollowUp());
    }
  }

  /// Closes a microphone that reopened after an answer and heard nothing.
  Future<void> _closeUnusedFollowUp() async {
    if (!state.isListening) return;
    _turn++;
    _resumeAfterTurn = false;
    _autoStarted = false;
    _endpoint?.cancel();
    _endpoint = null;

    final recorder = _capturing;
    _capturing = null;
    final subscription = _levels;
    _levels = null;
    if (subscription != null) unawaited(subscription.cancel());

    try {
      await recorder?.cancel();
    } catch (_) {
      // Closing a microphone that heard nothing has nothing to report.
    }
    if (!ref.mounted) return;
    state = state.copyWith(phase: CompanionPhase.idle, levels: _silentLevels);
  }

  /// Releases the microphone without touching state: the provider is gone, so
  /// there is nothing left to tell.
  void _release() {
    _endpoint?.cancel();
    _endpoint = null;

    final subscription = _levels;
    _levels = null;
    if (subscription != null) unawaited(subscription.cancel());

    final recorder = _capturing;
    _capturing = null;
    if (recorder != null) unawaited(recorder.cancel());
  }

  static String _messageOf(Object error) {
    if (error is CompanionTurnException) return error.message;
    const prefix = 'Exception: ';
    final text = error.toString();
    return text.startsWith(prefix) ? text.substring(prefix.length) : text;
  }

  static String _failureMessage(Object error) {
    return 'The microphone could not start: ${_messageOf(error)}';
  }
}
