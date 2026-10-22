import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/theme/appearance_preferences.dart';
import 'package:installm/core/theme/theme.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:installm/features/model_selection/presentation/model_selection_page.dart';
import 'package:installm/features/model_selection/presentation/model_selection_state.dart';

const _catalog = <LlmModel>[
  LlmModel(
    id: 'qwen-3-4b',
    name: 'Qwen 3',
    parameterSize: '4B',
    description: 'Reasons before it answers.',
    localFileName: 'qwen3-4b-q4_k_m.gguf',
  ),
  LlmModel(
    id: 'smollm2-360m',
    name: 'SmolLM2',
    parameterSize: '360M',
    description: 'Runs on an old phone.',
    localFileName: 'smollm2-360m-instruct-q4_k_m.gguf',
  ),
];

class _Models extends ModelSelectionController {
  _Models(this.catalog);

  final List<LlmModel> catalog;

  @override
  ModelSelectionState build() => ModelSelectionState(models: catalog);

  @override
  Future<void> refreshStorageInfo() async {}
}

Future<void> _pumpPage(
  WidgetTester tester,
  _Models models, {
  double width = 1200,
}) async {
  tester.view.physicalSize = Size(width, 900);
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

void main() {
  testWidgets('a wide window shows the list beside the focused model', (
    tester,
  ) async {
    await _pumpPage(tester, _Models(_catalog));

    // The list, and the smallest model open in the pane beside it: the
    // focused name appears in its list row and as the pane title.
    expect(find.text('Qwen 3'), findsOneWidget);
    expect(find.text('SmolLM2'), findsNWidgets(2));

    await tester.tap(find.text('Qwen 3'));
    await tester.pumpAndSettle();

    // The row focuses the pane; it does not choose the model for the app.
    expect(find.text('Qwen 3'), findsNWidgets(2));
    expect(find.text('SmolLM2'), findsOneWidget);
    expect(find.text('Use this model'), findsNothing);
  });

  testWidgets('a narrow window swaps the list for the detail and back', (
    tester,
  ) async {
    await _pumpPage(tester, _Models(_catalog), width: 700);

    // Only the list fits, so the pane is not shown yet.
    expect(find.text('SmolLM2'), findsOneWidget);
    expect(find.text('All models'), findsNothing);

    await tester.tap(find.text('SmolLM2'));
    await tester.pumpAndSettle();

    // The detail replaces the list: the pane title is the model name by
    // itself, and back returns to the list.
    expect(find.text('SmolLM2'), findsOneWidget);
    expect(find.text('All models'), findsOneWidget);

    await tester.tap(find.text('All models'));
    await tester.pumpAndSettle();

    expect(find.text('Qwen 3'), findsOneWidget);
  });

  testWidgets('an installed model offers itself to the app from the pane', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _Models(const [
        LlmModel(
          id: 'qwen-3-4b',
          name: 'Qwen 3',
          parameterSize: '4B',
          description: 'Reasons before it answers.',
          localFileName: 'qwen3-4b-q4_k_m.gguf',
          isDownloaded: true,
        ),
      ]),
    );

    expect(find.text('Use this model'), findsOneWidget);
    expect(find.text('GGUF metadata'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('one family of sizes is one list entry whose variants are '
      'picked from the pane', (tester) async {
    const family = [
      LlmModel(
        id: 'qwen-s-0.5b',
        name: 'Qwen S',
        parameterSize: '0.5B',
        description: 'Small.',
        localFileName: 'qwen-s-0.5b-q4_k_m.gguf',
      ),
      LlmModel(
        id: 'qwen-s-1.5b',
        name: 'Qwen S',
        parameterSize: '1.5B',
        description: 'Small.',
        localFileName: 'qwen-s-1.5b-q4_k_m.gguf',
      ),
    ];
    await _pumpPage(tester, _Models(family));

    // One row, with the count and best variant on its second line.
    expect(find.textContaining('2 variants'), findsOneWidget);

    // The pane is the family ledger: the title is the name by itself, and a
    // row per variant shows its size.
    expect(find.text('Qwen S'), findsNWidgets(2));
    expect(find.text('0.5B'), findsOneWidget);
    expect(find.text('1.5B'), findsOneWidget);

    // Viewing another variant does not download or choose it; the pane
    // follows it: its row opens in place (the ID shows in the expanded File
    // facts) and there is no checkmark left anywhere, because the ledger
    // marks focus with the wash and the footer carries the action.
    await tester.tap(find.text('1.5B'));
    await tester.pumpAndSettle();

    expect(find.text('qwen-s-1.5b'), findsOneWidget);
    expect(find.text('Quantization'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Download Q4_K_M'),
      findsOneWidget,
    );
  });

  testWidgets('a fresh page starts with Installed and Best fit on', (
    tester,
  ) async {
    await _pumpPage(tester, _Models(_catalog));

    final installedChip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'Installed (0)'),
    );
    final bestFitChip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'Best fit'),
    );
    expect(
      installedChip.selected,
      isTrue,
      reason: 'installed first by default',
    );
    expect(bestFitChip.selected, isTrue, reason: 'best-fit sort by default');
  });

  testWidgets('the filters are one band across the page above the split', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _Models(const [
        LlmModel(
          id: 'qwen-3-4b',
          name: 'Qwen 3',
          parameterSize: '4B',
          description: 'Reasons before it answers.',
          localFileName: 'qwen3-4b-q4_k_m.gguf',
          capabilities: [ModelCapability.vision],
        ),
      ]),
    );

    // The chips sit on one line instead of wrapping inside the 300px list
    // column, and that line is above the list and the open model.
    final installed = tester.getRect(
      find.widgetWithText(FilterChip, 'Installed (0)'),
    );
    final bestFit = tester.getRect(find.widgetWithText(FilterChip, 'Best fit'));
    final vision = tester.getRect(
      find.widgetWithText(FilterChip, 'Vision (1)'),
    );
    expect(vision.top, installed.top);
    expect(
      bestFit.right,
      greaterThan(300),
      reason: 'the band spans past the list column',
    );

    final firstRow = tester.getRect(find.text('Qwen 3').first);
    expect(installed.bottom, lessThan(firstRow.top));
  });

  testWidgets('filter chips keep their icons', (tester) async {
    await _pumpPage(
      tester,
      _Models(const [
        LlmModel(
          id: 'qwen-3-4b',
          name: 'Qwen 3',
          parameterSize: '4B',
          description: 'Reasons before it answers.',
          localFileName: 'qwen3-4b-q4_k_m.gguf',
          capabilities: [ModelCapability.vision],
        ),
      ]),
    );

    final installedChip = find.widgetWithText(FilterChip, 'Installed (0)');
    expect(installedChip, findsOneWidget);
    expect(
      find.descendant(of: installedChip, matching: find.byType(Icon)),
      findsOneWidget,
    );

    final visionChip = find.widgetWithText(FilterChip, 'Vision (1)');
    expect(visionChip, findsOneWidget);
    expect(
      find.descendant(of: visionChip, matching: find.byType(Icon)),
      findsOneWidget,
    );
  });
}
