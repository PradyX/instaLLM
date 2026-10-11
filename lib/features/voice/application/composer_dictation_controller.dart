import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_llm/core/settings/voice_settings_provider.dart';
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
  ComposerDictationController(this._ref) : super(const DictationState());

  final Ref _ref;

  /// Opens the mic when idle, finishes and inserts when open.
  Future<void> toggle(TextEditingController target) async {
    switch (state.stage) {
      case DictationStage.idle:
        await _start();
      case DictationStage.listening:
        await _finishPlatform(target);
      case DictationStage.recording:
        await _finishLocal(target);
      case DictationStage.transcribing:
        break;
    }
  }

  Future<void> _start() async {
    final engine = _ref.read(voiceSettingsProvider).sttEngine;
    if (engine == SttEngine.platform) {
      final started = await _ref.read(platformSpeechProvider).listen();
      if (!mounted) return;
      state = DictationState(
        stage: started ? DictationStage.listening : DictationStage.idle,
        errorMessage: started
            ? null
            : 'Device recognition is not available here. Switch the '
                  'transcription engine to the local model in Settings.',
      );
      return;
    }
    await _ref.read(recordingControllerProvider.notifier).start();
    if (!mounted) return;
    final recording = _ref.read(recordingControllerProvider);
    state = DictationState(
      stage: recording.isRecording
          ? DictationStage.recording
          : DictationStage.idle,
      errorMessage: recording.errorMessage,
    );
  }

  Future<void> _finishPlatform(TextEditingController target) async {
    final transcript = await _ref.read(platformSpeechProvider).stop();
    if (!mounted) return;
    if (transcript.trim().isEmpty) {
      state = const DictationState(
        errorMessage: 'Nothing recognizable was heard. Try again.',
      );
      return;
    }
    _insert(target, transcript);
    state = const DictationState();
  }

  Future<void> _finishLocal(TextEditingController target) async {
    final path = await _ref.read(recordingControllerProvider.notifier).stop();
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
        errorMessage: transcription.errorMessage ?? 'No speech was recognized.',
      );
      return;
    }
    _insert(target, transcription.transcript);
    state = const DictationState();
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
