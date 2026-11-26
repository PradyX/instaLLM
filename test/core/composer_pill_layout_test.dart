import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/widgets/composer_model_pill.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/domain/model_reasoning.dart';

const LlmModel _model = LlmModel(
  id: 'qwen3.5-2b',
  name: 'Qwen Qwen3.5 2B Instruct Thinking Coder',
  parameterSize: '3.5B',
  description:
      'The long name that used to push the buttons off a phone screen.',
);

const LlmModel _other = LlmModel(
  id: 'lfm2-350m',
  name: 'LFM2',
  parameterSize: '350M',
  description: 'The model the test switches to.',
);

const ModelReasoning _reasoning = ModelReasoning(
  defaultChoice: ReasoningChoice.thinkingOff,
  prefills: {
    ReasoningChoice.thinkingOn: '',
    ReasoningChoice.thinkingOff: '</think>\n\n',
  },
);

/// The composer's action row, laid out the way `ChatComposer` lays it out: the
/// pill takes what is left, and the buttons keep their own width.
Widget _actionRow({required Widget leading}) {
  return MaterialApp(
    home: Scaffold(
      // The composer lives at the bottom of the screen, and the menu has to open
      // where that leaves room.
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Row(
          children: [
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [Flexible(child: leading)],
              ),
            ),
            const SizedBox.square(
              dimension: 40,
              key: ValueKey('attach'),
              child: Icon(Icons.attach_file),
            ),
            const SizedBox(width: 4),
            const SizedBox.square(
              dimension: 40,
              key: ValueKey('send'),
              child: Icon(Icons.arrow_upward_rounded),
            ),
          ],
        ),
      ),
    ),
  );
}

void _phoneWidth(WidgetTester tester, {double width = 360}) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = Size(width * 3, 800 * 3);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  testWidgets('one pill keeps the buttons on screen and words the state', (
    tester,
  ) async {
    const width = 360.0;
    _phoneWidth(tester, width: width);

    await tester.pumpWidget(
      _actionRow(
        leading: ComposerModelPill(
          models: const [_model, _other],
          selected: _model,
          enabled: true,
          reasoning: _reasoning,
          reasoningChoice: ReasoningChoice.thinkingOff,
          onReasoningSelected: (_) {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    for (final key in ['attach', 'send']) {
      final rect = tester.getRect(find.byKey(ValueKey(key)));
      expect(
        rect.right,
        lessThanOrEqualTo(width),
        reason: '$key must stay inside a ${width.round()} dp screen',
      );
    }

    // One surface, one chevron: the model and its thinking state share the
    // pill instead of sitting in two chips.
    expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
    expect(find.textContaining('Qwen Qwen3.5 2B'), findsOneWidget);
    expect(find.text('· off'), findsOneWidget);
  });

  testWidgets('a tap opens the models and the thinking choice together', (
    tester,
  ) async {
    _phoneWidth(tester);
    LlmModel? picked;
    ReasoningChoice? pickedChoice;

    await tester.pumpWidget(
      _actionRow(
        leading: ComposerModelPill(
          models: const [_model, _other],
          selected: _model,
          enabled: true,
          reasoning: _reasoning,
          reasoningChoice: ReasoningChoice.thinkingOff,
          onSelected: (model) => picked = model,
          onReasoningSelected: (choice) => pickedChoice = choice,
        ),
      ),
    );

    await tester.tap(find.byType(ComposerModelPill));
    await tester.pumpAndSettle();

    expect(find.byKey(composerModelMenuKey), findsOneWidget);
    // Both selectors in the same card: every model, and the thinking segments.
    expect(find.byKey(const ValueKey('composer-model-qwen3.5-2b')), findsOne);
    expect(find.byKey(const ValueKey('composer-model-lfm2-350m')), findsOne);
    expect(find.byKey(const ValueKey('composer-reasoning-off')), findsOne);
    expect(find.byKey(const ValueKey('composer-reasoning-on')), findsOne);

    await tester.tap(find.byKey(const ValueKey('composer-model-lfm2-350m')));
    await tester.pumpAndSettle();
    expect(picked?.id, 'lfm2-350m');
    expect(find.byKey(composerModelMenuKey), findsNothing);

    // The menu closed on the pick; the thinking choice is one tap away again.
    await tester.tap(find.byType(ComposerModelPill));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-reasoning-on')));
    await tester.pumpAndSettle();
    expect(pickedChoice, ReasoningChoice.thinkingOn);
    // Choosing a state leaves the menu open, so the other rows stay reachable.
    expect(find.byKey(composerModelMenuKey), findsOneWidget);
  });

  testWidgets('a model with no reasoning choice shows no state and no row', (
    tester,
  ) async {
    _phoneWidth(tester);

    await tester.pumpWidget(
      _actionRow(
        leading: const ComposerModelPill(
          models: [_model],
          selected: _model,
          enabled: true,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
    expect(find.text('· off'), findsNothing);

    await tester.tap(find.byType(ComposerModelPill));
    await tester.pumpAndSettle();

    expect(find.byKey(composerModelMenuKey), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-reasoning-off')), findsNothing);
  });

  testWidgets('a closed pill cannot be opened while a run is in flight', (
    tester,
  ) async {
    _phoneWidth(tester);

    await tester.pumpWidget(
      _actionRow(
        leading: const ComposerModelPill(
          models: [_model],
          selected: _model,
          enabled: false,
        ),
      ),
    );

    await tester.tap(find.byType(ComposerModelPill));
    await tester.pumpAndSettle();
    expect(find.byKey(composerModelMenuKey), findsNothing);
  });
}
