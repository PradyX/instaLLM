import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/companion/application/companion_turn_runner.dart';
import 'package:installm/features/voice/application/transcription_controller.dart';

/// Reads the words out of one captured clip.
///
/// Behind an interface so the page can be tested without a speech model.
abstract class CompanionTranscriber {
  /// Transcribes [clipPath], throwing [CompanionTurnException] with something
  /// the page can show when it cannot.
  Future<String> transcribe(String clipPath);
}

/// Transcribes through the same speech model and service the voice screens use.
///
/// The transcription controller is the app's one clip-to-text path, so the
/// engine, the chosen speech model and their error messages stay in one place;
/// nothing is written to a conversation here.
class LocalCompanionTranscriber implements CompanionTranscriber {
  LocalCompanionTranscriber(this.ref);

  final Ref ref;

  @override
  Future<String> transcribe(String clipPath) async {
    final controller = ref.read(transcriptionControllerProvider.notifier);
    if (controller.isBusy) {
      throw const CompanionTurnException(
        'The speech model is still transcribing another clip. Try again once '
        'it has finished.',
      );
    }

    // start() resolves the model, runs the clip and returns when the run ends,
    // so the state read straight after it is this clip's result.
    await controller.start(audioPath: clipPath);
    final state = ref.read(transcriptionControllerProvider);

    if (state.hasFailed) {
      throw CompanionTurnException(
        state.errorMessage ?? 'That clip could not be transcribed.',
      );
    }
    if (state.wasStopped) {
      throw const CompanionTurnException(
        'Transcription was stopped before it finished.',
      );
    }
    return state.transcript.trim();
  }
}

final companionTranscriberProvider = Provider<CompanionTranscriber>(
  (ref) => LocalCompanionTranscriber(ref),
);
