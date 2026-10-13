import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:installm/features/model_selection/presentation/model_selection_state.dart';

/// The two smallest catalog chat models. Installing both leaves a real choice,
/// so "what the user picked" can differ from "what the app would pick".
const _catalogFirstId = 'qwen-2.5-0.5b';
const _chosenId = 'qwen-2.5-coder-0.5b';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Map<String, String> secureStore;

  /// Writes a file the app accepts as an installed model: the GGUF magic bytes
  /// are what tell a model apart from a half-finished download.
  Future<void> installModel(String modelId) async {
    final model = LlmModel.availableModels.firstWhere((m) => m.id == modelId);
    final file = File(p.join(tempDir.path, 'models', model.localFileName!));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(const [0x47, 0x47, 0x55, 0x46]);
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('installm_selected_model');
    secureStore = <String, String>{};
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
  });

  tearDown(() async {
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
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// A launch of the app. The controller loads after it builds and disposes
  /// without a listener, so the subscription is what keeps the load alive —
  /// the same subscription every surface reading the selection holds.
  ProviderContainer launch() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
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
      if (done(state)) return state;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return container.read(modelSelectionControllerProvider);
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

  test('a first launch starts on a model the device can run', () async {
    await installModel(_catalogFirstId);
    await installModel(_chosenId);

    final container = launch();
    final state = await waitForSelection(
      container,
      (state) => state.selectedModelId != null,
    );

    // Nothing chosen yet: the app starts on an installed model rather than on
    // an empty selection, and that start is remembered below like any choice.
    expect(state.selectedModelId, _catalogFirstId);
  });

  test('the next launch opens on the model the user chose', () async {
    await installModel(_catalogFirstId);
    await installModel(_chosenId);

    final first = launch();
    await waitForSelection(first, (state) => state.selectedModelId != null);

    // Switching models is what every surface does — home's pill, a room's —
    // and all of them go through this one call.
    final chosen = first
        .read(modelSelectionControllerProvider)
        .models
        .firstWhere((model) => model.id == _chosenId);
    first.read(modelSelectionControllerProvider.notifier).selectModel(chosen);

    expect(
      first.read(modelSelectionControllerProvider).selectedModelId,
      _chosenId,
    );
    await waitForStored(_chosenId);
    expect(
      secureStore[ModelSelectionController.selectedModelStorageKey],
      _chosenId,
    );

    // A second launch of the app, with the same models installed.
    final second = launch();
    final restored = await waitForSelection(
      second,
      (state) => state.selectedModelId == _chosenId,
    );

    expect(restored.selectedModelId, _chosenId);
  });

  test('a choice that is no longer installed falls back', () async {
    await installModel(_catalogFirstId);
    // A pick made in an earlier run, for a model since deleted from the app.
    secureStore[ModelSelectionController.selectedModelStorageKey] =
        'qwen-2.5-coder-3b';

    final container = launch();
    final state = await waitForSelection(
      container,
      (state) => state.selectedModelId != null,
    );

    expect(state.selectedModelId, _catalogFirstId);
  });
}
