import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:installm/core/inference/inference_engine.dart';
import 'package:installm/core/services/device_profile_service.dart';
import 'package:installm/core/services/model_storage_service.dart';
import 'package:installm/core/services/process_memory_probe.dart';
import 'package:installm/core/services/service_providers.dart';
import 'package:installm/core/utils/llm_prompt_utils.dart';
import 'package:installm/features/benchmark/domain/local_benchmark_result.dart';
import 'package:installm/features/model_selection/data/model_compatibility_service.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';

final benchmarkServiceProvider = Provider<BenchmarkService>((ref) {
  return BenchmarkService(
    engine: ref.read(inferenceEngineProvider),
    modelStorageService: ref.read(modelStorageServiceProvider),
    deviceProfileService: ref.read(deviceProfileServiceProvider),
    memoryProbe: ref.read(processMemoryProbeProvider),
  );
});

class BenchmarkService {
  static const benchmarkPrompt = 'Explain AI in one sentence.';
  static const benchmarkSystemPrompt =
      'You are a helpful and concise assistant.';
  static const benchmarkMaxTokens = 96;
  static const _benchmarkTemperature = 0.2;
  static const _benchmarkTopP = 0.8;
  static const _benchmarkTopK = 40;

  final InferenceEngine engine;
  final ModelStorageService modelStorageService;
  final DeviceProfileService deviceProfileService;
  final ProcessMemoryProbe memoryProbe;

  const BenchmarkService({
    required this.engine,
    required this.modelStorageService,
    required this.deviceProfileService,
    required this.memoryProbe,
  });

  /// Rough prompt token count used for the prompt-processing rate.
  ///
  /// The bundled runtime exposes no tokenizer through its isolate API, so this
  /// uses the usual ~4 characters per token approximation and the UI marks the
  /// resulting rate as estimated.
  static int estimatePromptTokens(String prompt) {
    final characters = prompt.runes.length;
    if (characters <= 0) return 0;
    return (characters / 4).ceil();
  }

  Future<List<LocalBenchmarkResult>> runLocalBenchmark({
    required List<LlmModel> models,
  }) async {
    final results = <LocalBenchmarkResult>[];

    for (final model in models) {
      results.add(await _runSingleModelBenchmark(model));
    }

    return results;
  }

  Future<LocalBenchmarkResult> _runSingleModelBenchmark(LlmModel model) async {
    if (!model.isDownloaded) {
      return _failedResult(model, 'Model is not downloaded on this device.');
    }

    // Managed downloads and imported/external references both resolve here.
    final modelPath = await modelStorageService.resolveModelPath(model);
    if (modelPath == null ||
        !await modelStorageService.isModelPathDownloaded(modelPath)) {
      return _failedResult(
        model,
        'Model file is missing or incomplete on this device.',
      );
    }

    try {
      final targetNCtx = ModelCompatibilityService.defaultContextTokens;

      await engine.ensureModelLoaded(
        InferenceLoadRequest(
          modelPath: modelPath,
          contextTokens: targetNCtx,
          batchTokens: targetNCtx,
          temperature: _benchmarkTemperature,
          topP: _benchmarkTopP,
          topK: _benchmarkTopK,
        ),
      );

      final promptBundle = buildModelChatPrompt(
        const [LlmPromptMessage.user(benchmarkPrompt)],
        systemPrompt: benchmarkSystemPrompt,
        promptFormatId: model.promptFormatId,
      );
      final stopToken = modelStopToken(model.promptFormatId);
      final responseBuffer = StringBuffer();
      var generatedTokenCount = 0;
      int? ttftMs;
      final stopwatch = Stopwatch()..start();

      await for (final token in engine.generateResponse(
        promptBundle.prompt,
        maxTokens: benchmarkMaxTokens,
      )) {
        final cleanToken = token.replaceAll(stopToken, '');
        if (cleanToken.isNotEmpty) {
          ttftMs ??= stopwatch.elapsedMilliseconds;
          responseBuffer.write(cleanToken);
          generatedTokenCount++;
        }

        if (token.contains(stopToken)) {
          break;
        }
      }

      stopwatch.stop();
      final elapsedMs = stopwatch.elapsedMilliseconds;
      final elapsedSeconds = elapsedMs / 1000.0;
      final tokensPerSecond = elapsedSeconds > 0
          ? generatedTokenCount / elapsedSeconds
          : 0.0;
      final outputText = buildFinalResponseText(responseBuffer.toString());

      final promptTokens = estimatePromptTokens(promptBundle.prompt);
      final promptTokensPerSecond = ttftMs != null && ttftMs > 0
          ? promptTokens / (ttftMs / 1000.0)
          : null;
      final device = await deviceProfileService.collect();
      final peakMemoryBytes = await memoryProbe.readResidentMemoryBytes();
      // The engine's own view of how it was started, so a record describes the
      // run rather than what the settings screen asked for.
      final runtime = engine.runtimeInfo;

      return LocalBenchmarkResult(
        model: model,
        latencyMs: elapsedMs,
        tokensPerSecond: tokensPerSecond,
        generatedTokens: generatedTokenCount,
        outputText: outputText,
        ttftMs: ttftMs,
        promptTokensEstimated: promptTokens > 0 ? promptTokens : null,
        promptTokensPerSecond: promptTokensPerSecond,
        contextTokens: runtime.contextTokens,
        threads: runtime.threads,
        gpuLayers: runtime.gpuLayers,
        offloadKqv: runtime.offloadKqv,
        backend: runtime.backend,
        peakMemoryBytes: peakMemoryBytes,
        deviceSummary: device.summaryLabel,
        deviceCpuCores: device.cpuCores,
        deviceMemoryBytes: device.totalMemoryBytes,
      );
    } catch (error) {
      return _failedResult(model, error.toString());
    }
  }

  static LocalBenchmarkResult _failedResult(LlmModel model, String message) {
    return LocalBenchmarkResult(
      model: model,
      latencyMs: 0,
      tokensPerSecond: 0,
      generatedTokens: 0,
      outputText: '',
      errorMessage: message,
    );
  }
}
