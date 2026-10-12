import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pocket_llm/core/settings/voice_settings_provider.dart';
import 'package:pocket_llm/core/widgets/chat_composer.dart'
    show ComposerMicState;
import 'package:pocket_llm/features/model_selection/domain/llm_model.dart';
import 'package:pocket_llm/features/voice/application/composer_dictation_controller.dart';
import 'package:pocket_llm/features/voice/application/recording_controller.dart';
import 'package:pocket_llm/features/voice/application/transcription_controller.dart';
import 'package:pocket_llm/features/voice/data/microphone_recorder.dart';
import 'package:pocket_llm/features/voice/data/platform_speech_service.dart';
import 'package:pocket_llm/features/voice/data/speech_to_text_service.dart';

/// Device recognizer the test drives: it hears [transcript] or nothing.
class _FakeListener implements PlatformSpeechListener {
  _FakeListener({
    this.outcome = PlatformSpeechStatus.ready,
    this.transcript = '',
    this.gate,
    this.error,
  });

  /// Reason the recognizer reports when it stops, if any.
  final String? error;

  /// What the device answers when asked to open.
  final PlatformSpeechStatus outcome;

  /// What the recognizer returns when it is stopped.
  final String transcript;

  /// When set, the recognizer only answers once the test releases it, which
  /// is what opening the microphone for the first time looks like while the
  /// permission prompt is up.
  final Completer<bool>? gate;

  int listenCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  bool _listening = false;

  @override
  bool get isListening => _listening;

  @override
  Future<PlatformSpeechStatus> status() async => outcome;

  @override
  Future<PlatformSpeechStatus> requestAuthorization() async => outcome;

  @override
  String? get lastError => error;

  @override
  Future<PlatformSpeechStatus> listen() async {
    listenCalls++;
    final gate = this.gate;
    if (gate != null && !await gate.future) {
      return PlatformSpeechStatus.notAuthorized;
    }
    if (outcome != PlatformSpeechStatus.ready) return outcome;
    _listening = true;
    return outcome;
  }

  @override
  Future<String> stop() async {
    stopCalls++;
    _listening = false;
    return transcript;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    _listening = false;
  }
}

/// Microphone that writes a real clip file and records what was removed.
class _FakeRecorder implements MicrophoneRecorder {
  _FakeRecorder({required this.clipPath, this.permissionGranted = true});

  final String clipPath;
  final bool permissionGranted;

  int startCalls = 0;
  int stopCalls = 0;
  final List<String> deleted = [];

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<String> start() async {
    startCalls++;
    await File(clipPath).writeAsBytes(const [0, 1, 2, 3]);
    return clipPath;
  }

  @override
  Future<String?> stop() async {
    stopCalls++;
    return clipPath;
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> deleteRecording(String path) async {
    deleted.add(path);
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }

  @override
  void dispose() {}
}

/// Speech runtime whose tokens the test pushes, so dictation is asserted
/// without a model on disk.
class _FakeRuntime implements SpeechRuntime {
  final StreamController<String> _tokens = StreamController<String>();

  int transcribeCalls = 0;
  String? audioPath;

  @override
  bool isGenerating = false;

  @override
  Future<void> load({
    required String modelPath,
    required String projectorPath,
    required int contextTokens,
  }) async {}

  @override
  Stream<String> transcribe(
    String prompt, {
    required String audioPath,
    required int maxTokens,
  }) {
    transcribeCalls++;
    this.audioPath = audioPath;
    return _tokens.stream;
  }

  @override
  void cancel() {}

  void emit(String token) => _tokens.add(token);

  /// Ends the stream. Only useful once the controller is listening.
  Future<void> finish() async {
    if (!_tokens.hasListener) return;
    await _tokens.close();
  }
}

/// Settings that stay in memory, so the tests never touch secure storage.
class _InMemoryVoiceSettings extends VoiceSettingsNotifier {
  _InMemoryVoiceSettings({SttEngine engine = SttEngine.localModel}) {
    state = state.copyWith(sttEngine: engine);
  }

  @override
  Future<void> setSttEngine(SttEngine engine) async {
    state = state.copyWith(sttEngine: engine);
  }
}

/// Pumps the event loop until [condition] holds.
Future<void> pumpUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 400; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition was never met');
}

const _speechModel = LlmModel(
  id: 'speech-model',
  name: 'Speech Model',
  parameterSize: '3B',
  description: 'test speech model',
  capabilities: [ModelCapability.audio],
);

void main() {
  late Directory tempDir;
  late String clipPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pocket_llm_dictation');
    clipPath = p.join(tempDir.path, 'dictation.wav');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  ProviderContainer buildContainer({
    required SttEngine engine,
    _FakeListener? listener,
    _FakeRecorder? recorder,
    _FakeRuntime? runtime,
    Duration tickInterval = const Duration(hours: 1),
    Duration? maximumLength,
  }) {
    final speech = _FakeListener(transcript: 'hello from the composer');
    return ProviderContainer(
      overrides: [
        voiceSettingsProvider.overrideWith(
          (ref) => _InMemoryVoiceSettings(engine: engine),
        ),
        platformSpeechProvider.overrideWithValue(listener ?? speech),
        microphoneRecorderProvider.overrideWithValue(
          recorder ?? _FakeRecorder(clipPath: clipPath),
        ),
        recordingControllerProvider.overrideWith(
          (ref) => RecordingController(
            ref,
            maximumLength: maximumLength,
            tickInterval: tickInterval,
          ),
        ),
        transcriptionModelProvider.overrideWithValue(_speechModel),
        speechToTextServiceProvider.overrideWithValue(
          SpeechToTextService(
            runtime: runtime ?? _FakeRuntime(),
            resolveModelPath: (_) async => '/models/speech.gguf',
            resolveProjectorPath: (_) async => '/models/speech-mmproj.gguf',
            isFileReady: (_) async => true,
          ),
        ),
      ],
    );
  }

  test('device recognition listens on the first tap and inserts on the '
      'second, appending to the draft', () async {
    final container = buildContainer(engine: SttEngine.platform);
    addTearDown(container.dispose);
    final listener = container.read(platformSpeechProvider) as _FakeListener;
    final field = TextEditingController(text: 'Draft:');
    addTearDown(field.dispose);
    final controller = container.read(composerDictationProvider.notifier);

    await controller.toggle(field);

    expect(
      container.read(composerDictationProvider).stage,
      DictationStage.listening,
    );
    expect(container.read(composerDictationProvider).isBusy, isTrue);
    expect(listener.listenCalls, 1);
    expect(field.text, 'Draft:');

    await controller.toggle(field);

    expect(
      container.read(composerDictationProvider).stage,
      DictationStage.idle,
    );
    expect(container.read(composerDictationProvider).isBusy, isFalse);
    expect(listener.stopCalls, 1);
    // Words land in the field for review; nothing is sent.
    expect(field.text, 'Draft: hello from the composer');
    // The cursor sits after the inserted words so dictation chains.
    expect(field.selection.baseOffset, field.text.length);
  });

  test('a device that has not allowed recognition reports it instead of '
      'opening the mic', () async {
    final container = buildContainer(
      engine: SttEngine.platform,
      listener: _FakeListener(outcome: PlatformSpeechStatus.notAuthorized),
    );
    addTearDown(container.dispose);
    final field = TextEditingController();
    addTearDown(field.dispose);

    await container.read(composerDictationProvider.notifier).toggle(field);

    final state = container.read(composerDictationProvider);
    expect(state.stage, DictationStage.idle);
    expect(state.isBusy, isFalse);
    expect(state.errorMessage, contains('not allowed yet'));
    expect(field.text, isEmpty);
  });

  test('a platform with no recognizer names Whisper instead', () async {
    final container = buildContainer(
      engine: SttEngine.platform,
      listener: _FakeListener(outcome: PlatformSpeechStatus.unsupported),
    );
    addTearDown(container.dispose);
    final field = TextEditingController();
    addTearDown(field.dispose);

    await container.read(composerDictationProvider.notifier).toggle(field);

    final state = container.read(composerDictationProvider);
    expect(state.stage, DictationStage.idle);
    expect(state.errorMessage, contains('no speech recognizer'));
    expect(state.errorMessage, contains('Whisper'));
  });

  test(
    'a silence report carries the recognizer\'s own reason when it has one',
    () async {
      final container = buildContainer(
        engine: SttEngine.platform,
        listener: _FakeListener(
          transcript: '',
          error: 'Recognition request was canceled  \n  because of an error',
        ),
      );
      addTearDown(container.dispose);
      final field = TextEditingController();
      addTearDown(field.dispose);
      final controller = container.read(composerDictationProvider.notifier);

      await controller.toggle(field);
      await controller.toggle(field);

      final error = container.read(composerDictationProvider).errorMessage;
      expect(error, contains('The recognizer reported: Recognition request'));
      // Flattened, so a multi-line native message fits a snackbar.
      expect(error, isNot(contains('\n')));
      expect(field.text, isEmpty);
    },
  );

  test('nothing recognizable leaves the draft alone and says so', () async {
    final container = buildContainer(
      engine: SttEngine.platform,
      listener: _FakeListener(transcript: '   '),
    );
    addTearDown(container.dispose);
    final field = TextEditingController(text: 'Keep me');
    addTearDown(field.dispose);
    final controller = container.read(composerDictationProvider.notifier);

    await controller.toggle(field);
    await controller.toggle(field);

    final state = container.read(composerDictationProvider);
    expect(state.stage, DictationStage.idle);
    expect(state.errorMessage, 'Nothing recognizable was heard. Try again.');
    expect(field.text, 'Keep me');
  });

  test('the local speech model records, transcribes in place and removes the '
      'clip', () async {
    final runtime = _FakeRuntime();
    final recorder = _FakeRecorder(clipPath: clipPath);
    final container = buildContainer(
      engine: SttEngine.localModel,
      recorder: recorder,
      runtime: runtime,
    );
    addTearDown(container.dispose);
    final field = TextEditingController();
    addTearDown(field.dispose);
    final controller = container.read(composerDictationProvider.notifier);

    await controller.toggle(field);

    expect(
      container.read(composerDictationProvider).stage,
      DictationStage.recording,
    );
    expect(recorder.startCalls, 1);
    expect(File(clipPath).existsSync(), isTrue);

    runtime.emit('local ');
    runtime.emit('words');
    final finishing = controller.toggle(field);
    await pumpUntil(() => runtime.transcribeCalls == 1);
    await runtime.finish();
    await finishing;

    final state = container.read(composerDictationProvider);
    expect(state.stage, DictationStage.idle);
    expect(state.errorMessage, isNull);
    expect(runtime.audioPath, clipPath);
    expect(field.text, 'local words');
    // The transcript is what the user keeps, so the audio is gone.
    expect(recorder.deleted, [clipPath]);
    expect(File(clipPath).existsSync(), isFalse);
    expect(container.read(recordingControllerProvider).recordedPath, isNull);
  });

  test('a clip the model cannot read is reported and still deleted', () async {
    final runtime = _FakeRuntime();
    final recorder = _FakeRecorder(clipPath: clipPath);
    final container = buildContainer(
      engine: SttEngine.localModel,
      recorder: recorder,
      runtime: runtime,
    );
    addTearDown(container.dispose);
    final field = TextEditingController(text: 'Existing');
    addTearDown(field.dispose);
    final controller = container.read(composerDictationProvider.notifier);

    await controller.toggle(field);
    final finishing = controller.toggle(field);
    await pumpUntil(() => runtime.transcribeCalls == 1);
    await runtime.finish();
    await finishing;

    final state = container.read(composerDictationProvider);
    expect(state.stage, DictationStage.idle);
    expect(state.errorMessage, 'No speech was recognized.');
    expect(field.text, 'Existing');
    expect(recorder.deleted, [clipPath]);
    expect(File(clipPath).existsSync(), isFalse);
  });

  test(
    'a recording the capture limit ends finishes the turn by itself',
    () async {
      final runtime = _FakeRuntime();
      final recorder = _FakeRecorder(clipPath: clipPath);
      final container = buildContainer(
        engine: SttEngine.localModel,
        recorder: recorder,
        runtime: runtime,
        maximumLength: const Duration(milliseconds: 40),
        tickInterval: const Duration(milliseconds: 10),
      );
      addTearDown(container.dispose);
      final field = TextEditingController();
      addTearDown(field.dispose);
      final controller = container.read(composerDictationProvider.notifier);

      runtime.emit('local ');
      runtime.emit('words');
      await controller.toggle(field);
      expect(
        container.read(composerDictationProvider).microphone,
        ComposerMicState.active,
      );

      // The recorder stops on its own at the limit; the turn must not be left
      // waiting for a tap that can never come.
      await pumpUntil(() => runtime.transcribeCalls == 1);
      await runtime.finish();
      await pumpUntil(() => field.text == 'local words');

      expect(
        container.read(composerDictationProvider).stage,
        DictationStage.idle,
      );
      expect(runtime.transcribeCalls, 1);
      expect(recorder.deleted, [clipPath]);
    },
  );

  test('the mic shows a finish control while voice is open and a spinner only '
      'while transcribing', () {
    expect(const DictationState().microphone, ComposerMicState.idle);
    expect(
      const DictationState(stage: DictationStage.listening).microphone,
      ComposerMicState.active,
    );
    expect(
      const DictationState(stage: DictationStage.recording).microphone,
      ComposerMicState.active,
    );
    expect(
      const DictationState(stage: DictationStage.transcribing).microphone,
      ComposerMicState.transcribing,
    );
  });

  test(
    'a tap while the recognizer is still opening does not open it twice',
    () async {
      final gate = Completer<bool>();
      final listener = _FakeListener(gate: gate);
      final container = buildContainer(
        engine: SttEngine.platform,
        listener: listener,
      );
      addTearDown(container.dispose);
      final field = TextEditingController();
      addTearDown(field.dispose);
      final controller = container.read(composerDictationProvider.notifier);

      final opening = controller.toggle(field);

      // The mic shows that it is engaged while the permission prompt is up,
      // rather than looking untouched.
      expect(
        container.read(composerDictationProvider).stage,
        DictationStage.listening,
      );

      await controller.toggle(field);
      expect(listener.listenCalls, 1);
      expect(listener.stopCalls, 0);

      gate.complete(true);
      await opening;
      expect(
        container.read(composerDictationProvider).stage,
        DictationStage.listening,
      );

      await controller.toggle(field);
      expect(listener.stopCalls, 1);
    },
  );

  test('a refused microphone reports the permission problem', () async {
    final container = buildContainer(
      engine: SttEngine.localModel,
      recorder: _FakeRecorder(clipPath: clipPath, permissionGranted: false),
    );
    addTearDown(container.dispose);
    final field = TextEditingController();
    addTearDown(field.dispose);

    await container.read(composerDictationProvider.notifier).toggle(field);

    final state = container.read(composerDictationProvider);
    expect(state.stage, DictationStage.idle);
    expect(state.errorMessage, contains('needs microphone access'));
    expect(File(clipPath).existsSync(), isFalse);
  });
}
