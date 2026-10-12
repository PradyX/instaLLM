import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_llm/core/settings/voice_settings_provider.dart';
import 'package:pocket_llm/core/widgets/chat_composer.dart'
    show ComposerMicState;
import 'package:pocket_llm/features/voice/application/recording_controller.dart';
import 'package:pocket_llm/features/voice/application/transcription_controller.dart';
import 'package:pocket_llm/features/voice/data/platform_speech_service.dart';

/// Where composer dictation is.
enum DictationStage {
  /// The mic is free.
  idle,

  /// The platform recognizer hears the user.
  listening,

  /// The microphone records a clip for the local speech model.
  recording,

  /// A recorded clip runs through the local speech model.
  transcribing,
}

/// What the composer mic shows.
class DictationState {
  const DictationState({this.stage = DictationStage.idle, this.errorMessage});

  final DictationStage stage;
  final String? errorMessage;

  /// True while the mic is open or a transcript is running: the mic locks
  /// into a spinner.
  bool get isBusy => stage != DictationStage.idle;

  DictationState copyWith({DictationStage? stage, String? errorMessage}) {
    return DictationState(
      stage: stage ?? this.stage,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Why device recognition could not open, in words the user can act on.
///
/// The app never asks the system for this permission itself, so the fix is
/// always somewhere the user can reach rather than a retry.
String platformRefusal(PlatformSpeechStatus status) {
  if (status == PlatformSpeechStatus.unsupported) {
    return 'This device has no speech recognizer Pocket LLM can use. Switch '
        'the transcription engine to Whisper in Settings › Voice.';
  }
  return 'Device recognition is not allowed yet. Allow it in Settings › '
      'Voice, or switch the transcription engine to Whisper — that '
      'one needs no speech-recognition permission.';
}

/// What the composer's mic shows for this dictation.
extension DictationMicrophone on DictationState {
  ComposerMicState get microphone => switch (stage) {
    DictationStage.idle => ComposerMicState.idle,
    DictationStage.transcribing => ComposerMicState.transcribing,
    DictationStage.listening ||
    DictationStage.recording => ComposerMicState.active,
  };
}

final composerDictationProvider =
    StateNotifierProvider<ComposerDictationController, DictationState>(
      (ref) => ComposerDictationController(ref),
    );

/// Turns the composer mic into words, in place.
///
/// One tap opens the chosen engine, a second tap finishes: device
/// recognition returns its transcript, a local-model clip is recorded,
/// transcribed and removed. The text lands in the composer's field for
/// review — nothing is ever sent on its own.
class ComposerDictationController extends StateNotifier<DictationState> {
  ComposerDictationController(this._ref) : super(const DictationState()) {
    // A recording can end without a tap: the capture limit stops it. The turn
    // then finishes itself, instead of leaving a mic state nobody can leave.
    _ref.listen<RecordingState>(recordingControllerProvider, _recorderChanged);
  }

  final Ref _ref;

  /// Field the open dictation will be inserted into, held so a turned that
  /// ends on its own still knows where its words belong.
  TextEditingController? _target;

  /// True while a turn is being finished, so the recorder's own stop event
  /// cannot start the same turn a second time.
  bool _finishing = false;

  /// True while an engine is being opened, so a second tap during the
  /// permission round trip is ignored rather than opening it twice.
  bool _starting = false;

  /// Opens the mic when idle, finishes and inserts when open.
  Future<void> toggle(TextEditingController target) async {
    if (_starting) return;
    switch (state.stage) {
      case DictationStage.idle:
        await _start(target);
      case DictationStage.listening:
        await _finishPlatform(target);
      case DictationStage.recording:
        await _finishLocal(target);
      case DictationStage.transcribing:
        break;
    }
  }

  Future<void> _start(TextEditingController target) async {
    final engine = _ref.read(voiceSettingsProvider).sttEngine;
    if (engine == SttEngine.platform) {
      // Opening the recognizer can take a moment; the mic shows that it is
      // engaged meanwhile instead of looking untouched.
      _starting = true;
      state = const DictationState(stage: DictationStage.listening);
      late final PlatformSpeechStatus opened;
      try {
        opened = await _ref.read(platformSpeechProvider).listen();
      } finally {
        _starting = false;
      }
      if (!mounted) return;
      final started = opened == PlatformSpeechStatus.ready;
      _target = started ? target : null;
      state = DictationState(
        stage: started ? DictationStage.listening : DictationStage.idle,
        errorMessage: started ? null : platformRefusal(opened),
      );
      return;
    }
    await _ref.read(recordingControllerProvider.notifier).start();
    if (!mounted) return;
    final recording = _ref.read(recordingControllerProvider);
    _target = recording.isRecording ? target : null;
    state = DictationState(
      stage: recording.isRecording
          ? DictationStage.recording
          : DictationStage.idle,
      errorMessage: recording.errorMessage,
    );
  }

  /// Finishes a clip the recorder ended on its own, such as at the capture
  /// limit, so a closed microphone never leaves the mic showing work.
  void _recorderChanged(RecordingState? previous, RecordingState next) {
    if (_finishing || state.stage != DictationStage.recording) return;
    if (!(previous?.isRecording ?? false) || next.isRecording) return;
    final target = _target;
    if (target == null) return;
    if (next.recordedPath == null) {
      _target = null;
      state = const DictationState(
        errorMessage: 'The recording produced no clip. Try again.',
      );
      return;
    }
    unawaited(_finishLocal(target));
  }

  Future<void> _finishPlatform(TextEditingController target) async {
    final speaker = _ref.read(platformSpeechProvider);
    final transcript = await speaker.stop();
    _target = null;
    if (!mounted) return;
    if (transcript.trim().isEmpty) {
      // The recognizer's own reason is worth passing on: "nothing was heard"
      // is wrong when the session failed for a reason it knows.
      final reason = speaker.lastError?.trim();
      state = DictationState(
        errorMessage: reason == null || reason.isEmpty
            ? 'Nothing recognizable was heard. Try again.'
            : 'Nothing recognizable was heard. The recognizer reported: '
                  '${_shorten(reason)}',
      );
      return;
    }
    _insert(target, transcript);
    state = const DictationState();
  }

  Future<void> _finishLocal(TextEditingController target) async {
    // The recorder's own stop event reaches [_recorderChanged], and a limit
    // that fires while a tap is already finishing the turn must not start a
    // second run over the same clip.
    if (_finishing) return;
    _finishing = true;
    try {
      final path = await _ref.read(recordingControllerProvider.notifier).stop();
      _target = null;
      if (!mounted) return;
      if (path == null) {
        state = const DictationState(
          errorMessage: 'The recording produced no clip. Try again.',
        );
        return;
      }
      state = const DictationState(stage: DictationStage.transcribing);
      await _ref
          .read(transcriptionControllerProvider.notifier)
          .start(audioPath: path);
      if (!mounted) return;
      final transcription = _ref.read(transcriptionControllerProvider);
      // The transcript is what the user keeps, so the audio is removed here
      // rather than left lying in app storage.
      await _ref.read(microphoneRecorderProvider).deleteRecording(path);
      _ref.read(recordingControllerProvider.notifier).clearRecording();
      if (!mounted) return;
      if (!transcription.hasTranscript) {
        state = DictationState(
          errorMessage:
              transcription.errorMessage ?? 'No speech was recognized.',
        );
        return;
      }
      _insert(target, transcription.transcript);
      state = const DictationState();
    } finally {
      _finishing = false;
    }
  }

  /// Keeps a recognizer's explanation to a length a snackbar can show.
  static String _shorten(String text, {int limit = 160}) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= limit ? flat : '${flat.substring(0, limit)}…';
  }

  /// Appends [text] to the field with a separating space, leaving the
  /// cursor at the end so dictation chains naturally.
  static void _insert(TextEditingController target, String text) {
    final current = target.text;
    final spoken = text.trim();
    if (spoken.isEmpty) return;
    final prefix = current.isEmpty
        ? ''
        : (current.endsWith(' ') || current.endsWith('\n')
              ? current
              : '$current ');
    final next = '$prefix$spoken';
    target.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }
}
