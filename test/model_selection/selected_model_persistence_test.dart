import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:installm/features/model_selection/presentation/model_selection_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Map<String, String> secureStore;
  final containers = <ProviderContainer>[];
  // Derive choices from the current catalog instead of pinning a model family.
  final candidates = LlmModel.availableModels
      .where((model) => !model.isEmbeddingModel && model.localFileName != null)
      .take(3)
      .toList();
  final catalogFirstId = candidates[0].id;
  final chosenId = candidates[1].id;

  /// Creates only a four-byte GGUF marker in the temporary directory.
  /// No model weights are downloaded or loaded by this persistence test.
  Future<void> createModelFixture(String modelId) async {
    final model = LlmModel.availableModels.firstWhere((m) => m.id == modelId);
    final file = File(p.join(tempDir.path, 'models', model.localFileName!));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(const [0x47, 0x47, 0x55, 0x46]);
  }

  setUpAll(() {
    // The app resolves its own folders through a platform channel, so the
    // temporary directory keeps this test off the real app folders.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    // The choice is persisted in secure storage; the channel stands in for the
    // keychain with a map that outlives a container, as the keychain does.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final arguments = (call.arguments as Map).cast<String, Object?>();
            final key = arguments['key'] as String?;
            if (key == null) return null;

            switch (call.method) {
              case 'write':
                secureStore[key] = arguments['value'] as String;
                return null;
              case 'read':
                return secureStore[key];
              case 'containsKey':
                return secureStore.containsKey(key);
              case 'delete':
                secureStore.remove(key);
                return null;
              case 'readAll':
                return Map<String, String>.from(secureStore);
              case 'deleteAll':
                secureStore.clear();
                return null;
              default:
                return null;
            }
          },
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('installm/storage_info'),
          (call) async => {'freeBytes': 1, 'totalBytes': 2},
        );
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('installm_selected_model');
    final fetchedAt = DateTime.now().toIso8601String();
    // The persistence check needs no HTTP: give background metadata refreshes
    // fresh caches for whichever models the catalog currently contains.
    secureStore = {
      'hf_discovered_models_cache_v1': jsonEncode({
        'models': [],
        'fetchedAt': fetchedAt,
      }),
      'hf_model_capabilities_cache_v1': jsonEncode({
        'entries': {
          for (final model in LlmModel.availableModels)
            if (Uri.tryParse(model.downloadUrl ?? '') case final uri?
                when uri.host == 'huggingface.co' &&
                    uri.pathSegments.length >= 2)
              uri.pathSegments.take(2).join('/'): {
                'capabilities': model.capabilities.map((c) => c.id).toList(),
                'fetchedAt': fetchedAt,
              },
        },
      }),
    };
  });

  tearDown(() async {
    for (final container in containers) {
      container.dispose();
    }
    containers.clear();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // Keep the channel mocks installed across test boundaries. Removing them
  // while a previous controller resumes a background cache read activates the
  // Linux singleton's sticky file fallback and poisons the following test.
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('installm/storage_info'),
          null,
        );
  });

  /// A launch of the app. The controller loads after it builds and disposes
  /// without a listener, so the subscription is what keeps the load alive —
  /// the same subscription every surface reading the selection holds.
  ProviderContainer launch() {
    final container = ProviderContainer();
    containers.add(container);
    container.listen(modelSelectionControllerProvider, (previous, next) {});
    return container;
  }

  /// Waits for the load to reach [done] the way a surface does: the controller
  /// does real file and channel work, so its state is read from the event loop
  /// rather than awaited directly.
  Future<ModelSelectionState> waitForSelection(
    ProviderContainer container,
    bool Function(ModelSelectionState state) done,
  ) async {
    for (var attempt = 0; attempt < 300; attempt++) {
      final state = container.read(modelSelectionControllerProvider);
      // Selection is published before storage info and background refreshes.
      // Wait for initialization to advance past that platform await as well.
      if (state.freeStorageBytes != null && done(state)) return state;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Model selection did not finish initializing.');
  }

  /// Waits for the write a selection schedules to reach storage: picking a
  /// model answers the user first and stores the choice behind the gesture.
  Future<void> waitForStored(String modelId) async {
    for (var attempt = 0; attempt < 200; attempt++) {
      if (secureStore[ModelSelectionController.selectedModelStorageKey] ==
          modelId) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('a first launch starts on an installed catalog model', () async {
    await createModelFixture(catalogFirstId);
    await createModelFixture(chosenId);

    final container = launch();
    final state = await waitForSelection(
      container,
      (state) => state.selectedModelId != null,
    );

    // Nothing chosen yet: the app starts on an installed model rather than on
    // an empty selection, and that start is remembered below like any choice.
    expect(state.selectedModelId, catalogFirstId);
  });

  test('the next launch opens on the model the user chose', () async {
    await createModelFixture(catalogFirstId);
    await createModelFixture(chosenId);

    final first = launch();
    await waitForSelection(first, (state) => state.selectedModelId != null);

    // Switching models is what every surface does — home's pill, a room's —
    // and all of them go through this one call.
    final chosen = first
        .read(modelSelectionControllerProvider)
        .models
        .firstWhere((model) => model.id == chosenId);
    first.read(modelSelectionControllerProvider.notifier).selectModel(chosen);

    expect(
      first.read(modelSelectionControllerProvider).selectedModelId,
      chosenId,
    );
    await waitForStored(chosenId);
    expect(
      secureStore[ModelSelectionController.selectedModelStorageKey],
      chosenId,
    );

    // A second launch of the app, with the same models installed.
    final second = launch();
    final restored = await waitForSelection(
      second,
      (state) => state.selectedModelId == chosenId,
    );

    expect(restored.selectedModelId, chosenId);
  });

  test('a choice that is no longer installed falls back', () async {
    await createModelFixture(catalogFirstId);
    // A pick made in an earlier run, for a model since deleted from the app.
    secureStore[ModelSelectionController.selectedModelStorageKey] =
        candidates.last.id;

    final container = launch();
    final state = await waitForSelection(
      container,
      (state) => state.selectedModelId != null,
    );

    expect(state.selectedModelId, catalogFirstId);
  });
}
