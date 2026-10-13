import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:installm/core/services/model_storage_service.dart';
import 'package:installm/core/settings/voice_settings_provider.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/voice/application/transcription_controller.dart';
import 'package:installm/features/voice/application/whisper_models_controller.dart';
import 'package:installm/features/voice/data/speech_to_text_service.dart';
import 'package:installm/features/voice/data/whisper_model_service.dart';
import 'package:installm/features/voice/data/whisper_speech_service.dart';
import 'package:installm/features/voice/domain/whisper_model_option.dart';

/// Speech runtime whose output the test controls token by token, so streaming,
/// stopping and failures can be observed without a model on disk.
class _ControllableRuntime implements SpeechRuntime {
  _ControllableRuntime({this.failure});

  /// When set, transcription fails with this message instead of streaming.
  final String? failure;

  final StreamController<String> _tokens = StreamController<String>();

  int transcribeCalls = 0;
  bool cancelled = false;
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
    final failure = this.failure;
    if (failure != null) return Stream<String>.error(Exception(failure));
    return _tokens.stream;
  }

  @override
  void cancel() => cancelled = true;

  void emit(String token) => _tokens.add(token);

  Future<void> finish() async {
    // A controller nobody listened to never completes its close future.
    if (!_tokens.hasListener) return;
    await _tokens.close();
  }
}

/// Pumps the event loop until [condition] holds.
///
/// A run checks the clip on disk, resolves the model paths and starts the
/// engine, so a single event-loop turn is not enough to reach the runtime.
Future<void> pumpUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 400; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition was never met');
}

void main() {
  late Directory tempDir;
  late String clip;

  final tiny = WhisperModelCatalog.models[0];
  final small = WhisperModelCatalog.models[2];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('installm_stt_run');
    final file = File(p.join(tempDir.path, 'note.wav'));
    await file.writeAsBytes(const [0, 1, 2, 3]);
    clip = file.path;
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  LlmModel speechModel() => const LlmModel(
    id: 'speech-model',
    name: 'Speech Model',
    parameterSize: '3B',
    description: 'test speech model',
    capabilities: [ModelCapability.audio],
  );

  ProviderContainer containerFor({
    required SpeechRuntime runtime,
    LlmModel? model,
    Future<String?> Function()? picker,
    bool modelReady = true,
    SttEngine engine = SttEngine.localModel,
    String? whisperModelId,
    List<WhisperModelOption> whisperInstalled = const [],
    WhisperRunner? whisperRunner,
  }) {
    return ProviderContainer(
      overrides: [
        voiceSettingsProvider.overrideWith(
          (ref) => _InMemoryVoiceSettings(
            engine: engine,
            whisperModelId: whisperModelId,
          ),
        ),
        transcriptionModelProvider.overrideWithValue(modelReady ? model : null),
        voiceAudioPickerProvider.overrideWithValue(picker ?? () async => clip),
        speechToTextServiceProvider.overrideWithValue(
          SpeechToTextService(
            runtime: runtime,
            resolveModelPath: (_) async => '/models/speech.gguf',
            resolveProjectorPath: (_) async => '/models/speech-mmproj.gguf',
            isFileReady: (_) async => true,
          ),
        ),
        whisperModelServiceProvider.overrideWithValue(
          _FakeWhisperModelService(whisperInstalled),
        ),
        if (whisperRunner != null)
          whisperRunnerProvider.overrideWithValue(whisperRunner),
      ],
    );
  }

  test('transcribes the picked clip and keeps the transcript', () async {
    final runtime = _ControllableRuntime();
    final container = containerFor(runtime: runtime, model: speechModel());
    addTearDown(container.dispose);
    final controller = container.read(transcriptionControllerProvider.notifier);

    final run = controller.start();
    await pumpUntil(() => runtime.transcribeCalls == 1);
    runtime.emit('Hello');
    runtime.emit(' world');
    await pumpUntil(
      () => container.read(transcriptionControllerProvider).hasTranscript,
    );
    await runtime.finish();
    await run;

    final state = container.read(transcriptionControllerProvider);
    expect(state.stage, TranscriptionStage.finished);
    expect(state.transcript, 'Hello world');
    expect(state.audioPath, clip);
    expect(state.audioLabel, 'note.wav');
    expect(state.modelName, 'Speech Model');
    expect(state.generatedTokens, 2);
    expect(state.wasStopped, isFalse);
    expect(state.errorMessage, isNull);
    expect(runtime.audioPath, clip);
  });

  test('keeps the words decoded before a stop', () async {
    final runtime = _ControllableRuntime();
    final container = containerFor(runtime: runtime, model: speechModel());
    addTearDown(container.dispose);
    final controller = container.read(transcriptionControllerProvider.notifier);

    final run = controller.start();
    await pumpUntil(() => runtime.transcribeCalls == 1);
    runtime.emit('Partial words');
    await pumpUntil(
      () => container.read(transcriptionControllerProvider).hasTranscript,
    );

    controller.cancel();
    expect(runtime.cancelled, isTrue);
    expect(
      container.read(transcriptionControllerProvider).statusText,
      'Stopping...',
    );

    await runtime.finish();
    await run;

    final state = container.read(transcriptionControllerProvider);
    expect(state.stage, TranscriptionStage.finished);
    expect(state.wasStopped, isTrue);
    expect(state.transcript, 'Partial words');
    expect(state.errorMessage, isNull);
  });

  test('leaves the screen alone when the picker is dismissed', () async {
    final runtime = _ControllableRuntime();
    final container = containerFor(
      runtime: runtime,
      model: speechModel(),
      picker: () async => null,
    );
    addTearDown(container.dispose);

    await container.read(transcriptionControllerProvider.notifier).start();

    final state = container.read(transcriptionControllerProvider);
    expect(state.stage, TranscriptionStage.idle);
    expect(state.transcript, isEmpty);
    expect(runtime.transcribeCalls, 0);
  });

  test('explains that a speech model has to be chosen first', () async {
    final runtime = _ControllableRuntime();
    final container = containerFor(runtime: runtime, modelReady: false);
    addTearDown(container.dispose);

    await container.read(transcriptionControllerProvider.notifier).start();

    final state = container.read(transcriptionControllerProvider);
    expect(state.stage, TranscriptionStage.failed);
    expect(state.errorMessage, contains('Choose a speech model'));
    expect(runtime.transcribeCalls, 0);
  });

  test('runs one clip at a time', () async {
    final runtime = _ControllableRuntime();
    final container = containerFor(runtime: runtime, model: speechModel());
    addTearDown(container.dispose);
    final controller = container.read(transcriptionControllerProvider.notifier);

    final run = controller.start();
    await pumpUntil(() => runtime.transcribeCalls == 1);
    await controller.start();

    expect(runtime.transcribeCalls, 1);

    await runtime.finish();
    await run;
  });

  test('reports a runtime failure without the exception prefix', () async {
    final runtime = _ControllableRuntime(failure: 'the clip was unreadable');
    final container = containerFor(runtime: runtime, model: speechModel());
    addTearDown(container.dispose);

    await container.read(transcriptionControllerProvider.notifier).start();

    final state = container.read(transcriptionControllerProvider);
    expect(state.stage, TranscriptionStage.failed);
    expect(state.errorMessage, 'the clip was unreadable');
  });

  test('clears the transcript and any error', () async {
    final runtime = _ControllableRuntime();
    final container = containerFor(runtime: runtime, model: speechModel());
    addTearDown(container.dispose);
    final controller = container.read(transcriptionControllerProvider.notifier);

    final run = controller.start();
    await pumpUntil(() => runtime.transcribeCalls == 1);
    runtime.emit('Done');
    await pumpUntil(
      () => container.read(transcriptionControllerProvider).hasTranscript,
    );
    await runtime.finish();
    await run;
    expect(
      container.read(transcriptionControllerProvider).hasTranscript,
      isTrue,
    );

    controller.clear();

    final state = container.read(transcriptionControllerProvider);
    expect(state.stage, TranscriptionStage.idle);
    expect(state.transcript, isEmpty);
    expect(state.audioLabel, isNull);
  });

  test('runs a clip through Whisper when that engine is chosen', () async {
    final runtime = _ControllableRuntime();
    final runner = _FakeWhisperRunner(transcript: 'Whisper heard this');
    final container = containerFor(
      runtime: runtime,
      // The GGUF model with an audio projector is not involved on this path,
      // so none being chosen must not block a Whisper run.
      modelReady: false,
      engine: SttEngine.whisper,
      whisperModelId: tiny.id,
      whisperInstalled: [tiny],
      whisperRunner: runner,
    );
    addTearDown(container.dispose);

    await container.read(transcriptionControllerProvider.notifier).start();

    final state = container.read(transcriptionControllerProvider);
    expect(state.stage, TranscriptionStage.finished);
    expect(state.transcript, 'Whisper heard this');
    expect(state.modelName, tiny.name);
    expect(state.audioLabel, 'note.wav');
    expect(state.errorMessage, isNull);
    expect(runner.transcribeCalls, 1);
    expect(runner.audioPath, clip);
    expect(runner.encoderPath, '/models/${tiny.encoder.fileName}');
    expect(runner.decoderPath, '/models/${tiny.decoder.fileName}');
    expect(runner.tokensPath, '/models/${tiny.tokens.fileName}');
    expect(runner.language, autoLanguage);
    expect(runtime.transcribeCalls, 0);
  });

  test(
    'Whisper falls back to an installed model when the chosen one is gone',
    () async {
      final runtime = _ControllableRuntime();
      final runner = _FakeWhisperRunner();
      final container = containerFor(
        runtime: runtime,
        modelReady: false,
        engine: SttEngine.whisper,
        whisperModelId: small.id,
        whisperInstalled: [tiny],
        whisperRunner: runner,
      );
      addTearDown(container.dispose);

      await container.read(transcriptionControllerProvider.notifier).start();

      expect(
        container.read(transcriptionControllerProvider).hasTranscript,
        isTrue,
      );
      expect(runner.encoderPath, '/models/${tiny.encoder.fileName}');
    },
  );

  test('Whisper says what to do when no model is installed', () async {
    final runtime = _ControllableRuntime();
    final runner = _FakeWhisperRunner();
    final container = containerFor(
      runtime: runtime,
      modelReady: false,
      engine: SttEngine.whisper,
      whisperRunner: runner,
    );
    addTearDown(container.dispose);

    await container.read(transcriptionControllerProvider.notifier).start();

    final state = container.read(transcriptionControllerProvider);
    expect(state.stage, TranscriptionStage.failed);
    expect(state.errorMessage, contains('Whisper model'));
    expect(state.errorMessage, contains('Settings'));
    expect(runner.transcribeCalls, 0);
    expect(runtime.transcribeCalls, 0);
  });

  test('a stopped Whisper run reports a stop, not a failure', () async {
    final runtime = _ControllableRuntime();
    final runner = _FakeWhisperRunner()..gate = Completer<void>();
    final container = containerFor(
      runtime: runtime,
      modelReady: false,
      engine: SttEngine.whisper,
      whisperInstalled: [tiny],
      whisperRunner: runner,
    );
    addTearDown(container.dispose);
    final controller = container.read(transcriptionControllerProvider.notifier);

    final run = controller.start();
    await pumpUntil(() => runner.transcribeCalls == 1);
    expect(
      container.read(transcriptionControllerProvider).stage,
      TranscriptionStage.running,
    );

    controller.cancel();
    expect(runner.cancelled, isTrue);

    // The native abort of a decode in flight surfaces as an error; the clip
    // was stopped by the user, which is not something to report as a failure.
    runner.failure = 'decode aborted';
    runner.gate!.complete();
    await run;

    final state = container.read(transcriptionControllerProvider);
    expect(state.stage, TranscriptionStage.finished);
    expect(state.wasStopped, isTrue);
    expect(state.errorMessage, isNull);
  });

  test('reports a Whisper failure with the binding\'s own message', () async {
    final runtime = _ControllableRuntime();
    final runner = _FakeWhisperRunner(failure: 'failed to load the model');
    final container = containerFor(
      runtime: runtime,
      modelReady: false,
      engine: SttEngine.whisper,
      whisperInstalled: [tiny],
      whisperRunner: runner,
    );
    addTearDown(container.dispose);

    await container.read(transcriptionControllerProvider.notifier).start();

    final state = container.read(transcriptionControllerProvider);
    expect(state.stage, TranscriptionStage.failed);
    expect(state.errorMessage, 'failed to load the model');
    expect(state.wasStopped, isFalse);
  });
}

/// Settings that stay in memory, so the tests never touch secure storage.
class _InMemoryVoiceSettings extends VoiceSettingsNotifier {
  _InMemoryVoiceSettings({
    SttEngine engine = SttEngine.localModel,
    String? whisperModelId,
  }) {
    state = state.copyWith(sttEngine: engine, whisperModelId: whisperModelId);
  }

  @override
  Future<void> setSttEngine(SttEngine engine) async {
    state = state.copyWith(sttEngine: engine);
  }

  @override
  Future<void> setWhisperModel(String? modelId) async {
    state = state.copyWith(whisperModelId: modelId);
  }
}

/// Whisper model files the test decides on, so no download is involved.
class _FakeWhisperModelService extends WhisperModelService {
  _FakeWhisperModelService(this.installedOptions)
    : super(ModelStorageService());

  final List<WhisperModelOption> installedOptions;

  @override
  Future<List<InstalledWhisperModel>> installed() async {
    return [
      for (final option in WhisperModelCatalog.models)
        if (installedOptions.contains(option))
          InstalledWhisperModel(
            option: option,
            encoderPath: '/models/${option.encoder.fileName}',
            decoderPath: '/models/${option.decoder.fileName}',
            tokensPath: '/models/${option.tokens.fileName}',
          ),
    ];
  }
}

/// Whisper, faked: the native library only exists inside a built app.
class _FakeWhisperRunner implements WhisperRunner {
  _FakeWhisperRunner({this.transcript = 'hello', this.failure});

  final String transcript;

  /// When set, the run fails with this message instead of answering.
  String? failure;

  /// When set, the run waits on it, so a running decode can be stopped.
  Completer<void>? gate;

  int transcribeCalls = 0;
  bool cancelled = false;
  String? encoderPath;
  String? decoderPath;
  String? tokensPath;
  String? audioPath;
  String? language;

  @override
  Future<String> transcribe({
    required String encoderPath,
    required String decoderPath,
    required String tokensPath,
    required String audioPath,
    String language = autoLanguage,
  }) async {
    transcribeCalls++;
    this.encoderPath = encoderPath;
    this.decoderPath = decoderPath;
    this.tokensPath = tokensPath;
    this.audioPath = audioPath;
    this.language = language;
    final gate = this.gate;
    if (gate != null) await gate.future;
    final failure = this.failure;
    if (failure != null) throw Exception(failure);
    return transcript;
  }

  @override
  Future<void> cancel() async => cancelled = true;
}
