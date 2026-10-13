import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/widgets/composer_model_pill.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';

const _alpha = LlmModel(
  id: 'm-alpha',
  name: 'Alpha',
  parameterSize: '1B',
  description: 'test model',
  isDownloaded: true,
);

const _beta = LlmModel(
  id: 'm-beta',
  name: 'Beta',
  parameterSize: '3B',
  description: 'test model',
  isDownloaded: true,
);

Future<void> _pump(WidgetTester tester, Widget pill) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: pill)),
    ),
  );
}

void main() {
  testWidgets('names the model the next answer runs on', (tester) async {
    await _pump(
      tester,
      ComposerModelPill(
        models: const [_alpha, _beta],
        selected: _alpha,
        enabled: true,
        onSelected: (_) {},
      ),
    );

    expect(find.text('Alpha · 1B'), findsOneWidget);
  });

  testWidgets('offers every model and reports the one tapped', (tester) async {
    LlmModel? picked;
    await _pump(
      tester,
      ComposerModelPill(
        models: const [_alpha, _beta],
        selected: _alpha,
        enabled: true,
        onSelected: (model) => picked = model,
      ),
    );

    await tester.tap(find.text('Alpha · 1B'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(CheckedPopupMenuItem<String>, 'Beta · 3B'),
      findsOneWidget,
    );

    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<String>, 'Beta · 3B'),
    );
    await tester.pumpAndSettle();

    expect(picked?.id, 'm-beta');
  });

  testWidgets('a run in flight keeps the pill closed', (tester) async {
    await _pump(
      tester,
      ComposerModelPill(
        models: const [_alpha, _beta],
        selected: _alpha,
        enabled: false,
        onSelected: (_) {},
      ),
    );

    await tester.tap(find.text('Alpha · 1B'));
    await tester.pumpAndSettle();

    expect(find.byType(CheckedPopupMenuItem<String>), findsNothing);
    // The model in use stays readable while it cannot be changed.
    expect(find.text('Alpha · 1B'), findsOneWidget);
  });

  testWidgets('offers models and nothing else', (tester) async {
    await _pump(
      tester,
      ComposerModelPill(
        models: const [_alpha, _beta],
        selected: _beta,
        enabled: true,
        onSelected: (_) {},
      ),
    );

    await tester.tap(find.text('Beta · 3B'));
    await tester.pumpAndSettle();

    // Every row is a model that can answer: the menu carries no second kind
    // of choice, so nothing in it can be mistaken for a setting.
    expect(find.byType(CheckedPopupMenuItem<String>), findsNWidgets(2));
    expect(
      find.widgetWithText(CheckedPopupMenuItem<String>, 'Alpha · 1B'),
      findsOneWidget,
    );
  });

  testWidgets('with nothing to offer it opens the model library', (
    tester,
  ) async {
    var pressed = false;
    await _pump(
      tester,
      ComposerModelPill(
        models: const [],
        selected: null,
        enabled: true,
        onEmptyPressed: () => pressed = true,
      ),
    );

    expect(find.text('Get a model'), findsOneWidget);
    await tester.tap(find.text('Get a model'));
    await tester.pumpAndSettle();

    expect(pressed, isTrue);
  });
}
