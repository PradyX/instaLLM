import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/services/hugging_face_repository_service.dart';
import 'package:installm/core/theme/appearance_preferences.dart';
import 'package:installm/core/theme/theme.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:installm/features/model_selection/presentation/model_selection_page.dart';
import 'package:installm/features/model_selection/presentation/model_selection_state.dart';

const _model = LlmModel(
  id: 'qwen-2.5-7b',
  name: 'Qwen 2.5',
  parameterSize: '7B',
  description: 'Balanced assistant',
  localFileName: 'qwen2.5-7b-instruct-q4_k_m.gguf',
  downloadUrl:
      'https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/'
      'qwen2.5-7b-instruct-q4_k_m.gguf',
);

ModelQuantizationChoices _choices() {
  return const ModelQuantizationChoices(
    repository: HuggingFaceRepository(
      repoId: 'bartowski/Qwen2.5-7B-Instruct-GGUF',
      branch: 'main',
      files: [],
    ),
    variants: [
      HuggingFaceModelVariant(
        filePath: 'qwen2.5-7b-instruct-q4_k_m.gguf',
        sizeBytes: 4683073056,
        quantization: 'Q4_K_M',
      ),
      HuggingFaceModelVariant(
        filePath: 'qwen2.5-7b-instruct-q8_0.gguf',
        sizeBytes: 8179000000,
        quantization: 'Q8_0',
      ),
    ],
  );
}

class _Models extends ModelSelectionController {
  _Models(this.catalog);

  final List<LlmModel> catalog;

  ModelQuantizationChoices? choices;
  final downloadedModels = <String>[];
  final downloadedVariants = <String>[];

  @override
  ModelSelectionState build() => ModelSelectionState(models: catalog);

  @override
  Future<void> refreshStorageInfo() async {}

  @override
  Future<ModelQuantizationChoices?> loadQuantizationChoices(
    LlmModel model,
  ) async => choices;

  @override
  Future<void> downloadModel(LlmModel model) async {
    downloadedModels.add(model.id);
  }

  @override
  Future<void> downloadQuantization({
    required LlmModel model,
    required ModelQuantizationChoices choices,
    required HuggingFaceModelVariant variant,
  }) async {
    downloadedVariants.add(variant.quantization);
  }
}

Future<void> _pumpPage(WidgetTester tester, _Models models) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [modelSelectionControllerProvider.overrideWith(() => models)],
      child: MaterialApp(
        theme: const MaterialTheme(
          TextTheme(),
          surfaceStyle: SurfaceStyle.translucent,
          accent: AccentColor.purple,
        ).dark(),
        home: const ModelSelectionPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pressDownload(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(FilledButton, label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the detail pane states the quantization the model is', (
    tester,
  ) async {
    await _pumpPage(tester, _Models(const [_model]));

    // Nothing has been asked of huggingface.co: the pane shows the file's own
    // label, with no choice to make yet.
    expect(find.text('Q4_K_M'), findsOneWidget);
    expect(find.text('Q8_0'), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Download Q4_K_M'),
      findsOneWidget,
    );
  });

  testWidgets('pressing Download offers the repository quantizations and '
      'nothing downloads until one is chosen', (tester) async {
    final models = _Models(const [_model])..choices = _choices();
    await _pumpPage(tester, models);

    await _pressDownload(tester, 'Download Q4_K_M');

    expect(find.text('Q4_K_M'), findsOneWidget);
    expect(find.text('Q8_0'), findsOneWidget);
    // The size of each choice is part of the choice.
    expect(find.text('4.4 GB'), findsOneWidget);
    expect(find.text('7.6 GB'), findsOneWidget);
    expect(models.downloadedVariants, isEmpty);
    expect(models.downloadedModels, isEmpty);

    await tester.tap(find.text('Q8_0'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Download Q8_0'), findsOneWidget);
    expect(models.downloadedVariants, isEmpty);

    await _pressDownload(tester, 'Download Q8_0');
    expect(models.downloadedVariants, ['Q8_0']);
  });

  testWidgets('a model with nothing to choose between downloads as before', (
    tester,
  ) async {
    // Null is what the controller returns for an offline device, a model with
    // no repository, or a repository carrying only this file.
    final models = _Models(const [_model]);
    await _pumpPage(tester, models);

    await _pressDownload(tester, 'Download Q4_K_M');

    expect(models.downloadedModels, ['qwen-2.5-7b']);
    expect(models.downloadedVariants, isEmpty);
    expect(find.text('Q8_0'), findsNothing);
  });
}
