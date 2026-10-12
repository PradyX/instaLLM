import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_llm/features/model_selection/domain/llm_model.dart';
import 'package:pocket_llm/features/model_selection/presentation/chat_models_provider.dart';
import 'package:pocket_llm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:pocket_llm/features/model_selection/presentation/model_selection_state.dart';

/// Answers with a fixed catalog, so these checks are about the list the
/// composers read rather than about storage.
class _FixedSelection extends ModelSelectionController {
  _FixedSelection(this._initial);

  final ModelSelectionState _initial;

  @override
  ModelSelectionState build() => _initial;
}

ProviderContainer containerFor({
  required List<LlmModel> models,
  String? selectedModelId,
}) {
  final container = ProviderContainer(
    overrides: [
      modelSelectionControllerProvider.overrideWith(
        () => _FixedSelection(
          ModelSelectionState(models: models, selectedModelId: selectedModelId),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

LlmModel model(
  String id, {
  String name = '',
  String parameterSize = '1B',
  bool downloaded = true,
  bool embedding = false,
}) {
  return LlmModel(
    id: id,
    name: name.isEmpty ? 'Model $id' : name,
    parameterSize: parameterSize,
    description: 'test model',
    capabilities: embedding ? const [ModelCapability.embedding] : const [],
    isDownloaded: downloaded,
  );
}

void main() {
  group('chatModelsProvider', () {
    test('keeps installed models only', () {
      final container = containerFor(
        models: [
          model('installed'),
          model('not-downloaded', downloaded: false),
        ],
      );

      expect(container.read(chatModelsProvider).map((m) => m.id), [
        'installed',
      ]);
    });

    test('leaves out models that only make vectors', () {
      final container = containerFor(
        models: [model('chat'), model('bge-small', embedding: true)],
      );

      expect(container.read(chatModelsProvider).map((m) => m.id), ['chat']);
    });

    test('lists the smallest first, whatever order storage reported', () {
      final container = containerFor(
        models: [
          model('internvl', parameterSize: '1.1B'),
          model('qwen', parameterSize: '0.5B'),
          model('minicpm', parameterSize: '1.4B'),
          model('smollm', parameterSize: '360M'),
        ],
      );

      expect(container.read(chatModelsProvider).map((m) => m.id), [
        'smollm',
        'qwen',
        'internvl',
        'minicpm',
      ]);
    });
  });

  group('selectedChatModelProvider', () {
    test('is the selected model while it is installed', () {
      final container = containerFor(
        models: [
          model('small', parameterSize: '360M'),
          model('picked'),
        ],
        selectedModelId: 'picked',
      );

      expect(container.read(selectedChatModelProvider)?.id, 'picked');
    });

    test('falls back to the smallest installed model', () {
      final container = containerFor(
        models: [
          model('big', parameterSize: '1.4B'),
          model('small', parameterSize: '360M'),
        ],
        selectedModelId: 'since-removed',
      );

      expect(container.read(selectedChatModelProvider)?.id, 'small');
    });

    test(
      'is null when nothing is installed, which is what Get a model means',
      () {
        final container = containerFor(
          models: [model('not-downloaded', downloaded: false)],
        );

        expect(container.read(selectedChatModelProvider), isNull);
      },
    );
  });
}
