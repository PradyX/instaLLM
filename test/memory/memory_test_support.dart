import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/inference/inference_engine.dart';
import 'package:installm/core/services/model_storage_service.dart';
import 'package:installm/core/services/service_providers.dart';
import 'package:installm/features/conversations/data/conversation_store.dart';
import 'package:installm/features/conversations/presentation/conversation_controller.dart';
import 'package:installm/features/group_chat/application/group_chat_controller.dart';
import 'package:installm/features/group_chat/data/group_chat_store.dart';
import 'package:installm/features/home/presentation/home_controller.dart';
import 'package:installm/features/memory/application/memory_controller.dart';
import 'package:installm/features/memory/data/memory_store.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:installm/features/model_selection/presentation/model_selection_state.dart';
import 'package:installm/features/tools/application/tool_registry.dart';
import 'package:installm/features/tools/application/tools_providers.dart';
import 'package:installm/features/workspaces/application/workspaces_controller.dart';
import 'package:installm/features/workspaces/data/workspace_store.dart';
import 'package:installm/features/workspaces/domain/workspace.dart';

class MemoryTestSelection extends ModelSelectionController {
  MemoryTestSelection(this.initial);
  final ModelSelectionState initial;
  @override
  ModelSelectionState build() => initial;
  void choose(String id) => state = state.copyWith(selectedModelId: id);
}

class MemoryTestStorage extends ModelStorageService {
  @override
  Future<String?> resolveModelPath(LlmModel model) async =>
      '/fake/${model.id}.gguf';
  @override
  Future<bool> isModelPathDownloaded(String? path) async => true;
}

class MemoryTestEngine implements InferenceEngine {
  final prompts = <String>[];
  final reservations = <int?>[];
  @override
  bool get isLoaded => true;
  @override
  bool get isGenerating => false;
  @override
  bool get isStopRequested => false;
  @override
  String? get loadedModelPath => '/fake/model.gguf';
  @override
  InferenceRuntimeInfo get runtimeInfo => InferenceRuntimeInfo.unloaded;
  @override
  InferenceCapabilities get capabilities => const InferenceCapabilities(
    streaming: true,
    cancellation: true,
    gpuOffload: false,
    vision: false,
    audio: false,
    embeddings: false,
  );
  @override
  Future<void> loadModel(InferenceLoadRequest request) async {}
  @override
  Future<void> ensureModelLoaded(InferenceLoadRequest request) async {}
  @override
  Future<void> unloadModel() async {}
  @override
  void cancel() {}
  @override
  Stream<String> generateResponse(String prompt, {int? maxTokens}) {
    prompts.add(prompt);
    reservations.add(maxTokens);
    return Stream.value('A local answer.');
  }

  @override
  Stream<String> generateVisionResponse(
    String prompt, {
    required List<String> imagePaths,
    int? maxTokens,
  }) => const Stream.empty();
  @override
  Stream<String> generateAudioResponse(
    String prompt, {
    required String audioPath,
    int? maxTokens,
  }) => const Stream.empty();
}

class MemoryTestHarness {
  MemoryTestHarness({
    this.models = const [],
    MemoryTestEngine? engine,
    this.registry,
  }) : engine = engine ?? MemoryTestEngine() {
    root = Directory.systemTemp.createTempSync('installm_memory_acceptance_');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => root.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    workspaceStore = WorkspaceStore(File('${root.path}/workspaces.json'));
    workspaceStore.save(
      WorkspacesSnapshot(
        workspaces: [
          Workspace.create(id: 'ws1', name: 'Project one'),
          Workspace.create(id: 'ws2', name: 'Project two'),
        ],
        activeWorkspaceId: 'ws1',
      ),
    );
    memoryStore = MemoryStore(File('${root.path}/facts.json'));
    conversationStore = ConversationStore(
      rootDirectory: Directory('${root.path}/chats'),
    );
  }
  final List<LlmModel> models;
  late final Directory root;
  late final WorkspaceStore workspaceStore;
  late final MemoryStore memoryStore;
  late final ConversationStore conversationStore;
  final MemoryTestEngine engine;
  final ToolRegistry? registry;
  final containers = <ProviderContainer>[];

  ProviderContainer container({Future<MemoryStore>? memoryFuture}) {
    final value = ProviderContainer(
      overrides: [
        memoryStoreProvider.overrideWith(
          (ref) => memoryFuture ?? Future.value(MemoryStore(memoryStore.file)),
        ),
        workspaceStoreProvider.overrideWith((ref) async => workspaceStore),
        conversationStoreProvider.overrideWithValue(conversationStore),
        groupChatStoreProvider.overrideWith(
          (ref) async => GroupChatStore(File('${root.path}/rooms.json')),
        ),
        modelSelectionControllerProvider.overrideWith(
          () => MemoryTestSelection(
            ModelSelectionState(
              models: models,
              selectedModelId: models.firstOrNull?.id,
            ),
          ),
        ),
        modelStorageServiceProvider.overrideWithValue(MemoryTestStorage()),
        inferenceEngineProvider.overrideWithValue(engine),
        toolRegistryProvider.overrideWithValue(
          registry ?? ToolRegistry(tools: [], platform: null),
        ),
      ],
    );
    containers.add(value);
    return value;
  }

  Future<HomeController> home(
    ProviderContainer container, {
    bool waitForMemory = true,
  }) async {
    container.listen(homeControllerProvider, (_, _) {});
    await waitFor(
      () => container.read(conversationControllerProvider).isInitialized,
    );
    if (waitForMemory) await container.read(memoryProvider.notifier).whenReady;
    await container.read(workspacesProvider.notifier).whenReady;
    return container.read(homeControllerProvider.notifier);
  }

  Future<void> close() async {
    for (final container in containers) {
      container.dispose();
    }
    // Let already-completed, unawaited persistence finish before cleanup.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    root.deleteSync(recursive: true);
  }
}

Future<void> waitFor(bool Function() ready) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Memory acceptance setup did not become ready.');
}
