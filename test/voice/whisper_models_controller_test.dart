import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/services/model_storage_service.dart';
import 'package:installm/features/voice/application/whisper_models_controller.dart';
import 'package:installm/features/voice/data/whisper_model_service.dart';
import 'package:installm/features/voice/domain/whisper_model_option.dart';

/// A model standing on disk, as the service would report it.
InstalledWhisperModel installedModel(WhisperModelOption option) {
  return InstalledWhisperModel(
    option: option,
    encoderPath: '/models/${option.encoder.fileName}',
    decoderPath: '/models/${option.decoder.fileName}',
    tokensPath: '/models/${option.tokens.fileName}',
  );
}

/// Service whose downloads the test drives: it can hold one open, fail it, or
/// let it finish, which is what the controller's states are made of.
class _FakeWhisperModelService extends WhisperModelService {
  _FakeWhisperModelService({List<InstalledWhisperModel> installed = const []})
    : installedModels = List<InstalledWhisperModel>.from(installed),
      super(ModelStorageService());

  List<InstalledWhisperModel> installedModels;
  final List<String> removedIds = <String>[];
  Object? downloadError;

  /// When set, a download waits on it, so the test can inspect a running one.
  Completer<void>? gate;

  @override
  Future<List<InstalledWhisperModel>> installed() async => installedModels;

  @override
  Future<void> download(
    WhisperModelOption option, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    onProgress?.call(1 * 1024 * 1024, option.approximateBytes);
    final gate = this.gate;
    if (gate != null) await gate.future;
    final error = downloadError;
    if (error != null) throw error;
    installedModels = [...installedModels, installedModel(option)];
    onProgress?.call(option.approximateBytes, option.approximateBytes);
  }

  @override
  Future<void> remove(WhisperModelOption option) async {
    removedIds.add(option.id);
    installedModels = installedModels
        .where((model) => model.option.id != option.id)
        .toList();
  }
}

/// Lets the queued futures of the controller settle.
Future<void> settle() async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  final tiny = WhisperModelCatalog.models[0];
  final small = WhisperModelCatalog.models[2];

  test('reads the model directory when it is created', () async {
    final service = _FakeWhisperModelService(
      installed: [installedModel(small)],
    );
    final controller = WhisperModelsController(service);
    addTearDown(controller.dispose);

    expect(controller.state.isLoading, isTrue);
    await settle();

    expect(controller.state.isLoading, isFalse);
    expect(controller.state.isInstalled(small.id), isTrue);
    expect(controller.state.isInstalled(tiny.id), isFalse);
    expect(
      controller.state.installedModel(small.id)?.encoderPath,
      '/models/${small.encoder.fileName}',
    );
  });

  test(
    'reports progress and installs the model when a download ends',
    () async {
      final service = _FakeWhisperModelService()..gate = Completer<void>();
      final controller = WhisperModelsController(service);
      addTearDown(controller.dispose);
      await settle();

      final run = controller.download(tiny);
      await settle();

      expect(controller.state.downloadingId, tiny.id);
      expect(controller.state.isDownloading, isTrue);
      expect(
        controller.state.progressFor(tiny.id),
        closeTo(1 * 1024 * 1024 / tiny.approximateBytes, 0.0001),
      );
      // One download at a time.
      expect(await controller.download(small), isFalse);

      service.gate!.complete();
      expect(await run, isTrue);

      expect(controller.state.isDownloading, isFalse);
      expect(controller.state.progressFor(tiny.id), isNull);
      expect(controller.state.isInstalled(tiny.id), isTrue);
      expect(controller.state.errorMessage, isNull);
    },
  );

  test('reports a failed download without the exception prefix', () async {
    final service = _FakeWhisperModelService()
      ..downloadError = Exception('the connection dropped');
    final controller = WhisperModelsController(service);
    addTearDown(controller.dispose);
    await settle();

    expect(await controller.download(tiny), isFalse);

    expect(controller.state.isDownloading, isFalse);
    expect(controller.state.errorMessage, 'the connection dropped');
    expect(controller.state.isInstalled(tiny.id), isFalse);
  });

  test('a cancelled download is not reported as a problem', () async {
    final service = _FakeWhisperModelService()..gate = Completer<void>();
    final controller = WhisperModelsController(service);
    addTearDown(controller.dispose);
    await settle();

    final run = controller.download(tiny);
    await settle();
    controller.cancelDownload();
    service.downloadError = StateError('download cancelled');
    service.gate!.complete();

    expect(await run, isFalse);
    expect(controller.state.isDownloading, isFalse);
    expect(controller.state.errorMessage, isNull);
  });

  test('removing a model deletes it and refreshes the list', () async {
    final service = _FakeWhisperModelService(installed: [installedModel(tiny)]);
    final controller = WhisperModelsController(service);
    addTearDown(controller.dispose);
    await settle();

    await controller.remove(tiny);

    expect(service.removedIds, [tiny.id]);
    expect(controller.state.isInstalled(tiny.id), isFalse);
    expect(controller.state.isLoading, isFalse);
  });
}
