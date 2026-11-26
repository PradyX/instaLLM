import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/widgets/composer_model_pill.dart';
import 'package:installm/core/widgets/composer_reasoning_pill.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/domain/model_reasoning.dart';

const LlmModel _model = LlmModel(
  id: 'qwen3.5-2b',
  name: 'Qwen Qwen3.5 2B Instruct Thinking Coder',
  parameterSize: '3.5B',
  description:
      'The long name that used to push the buttons off a phone screen.',
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
      body: Row(
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
  );
}

void main() {
  testWidgets(
    'a long model name leaves the attach and send buttons on screen',
    (tester) async {
      const width = 360.0;
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(width * 3, 800 * 3);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _actionRow(
          leading: ComposerModelPill(
            models: const [_model],
            selected: _model,
            enabled: true,
            reasoning: const ComposerReasoningPill(
              reasoning: _reasoning,
              choice: ReasoningChoice.thinkingOff,
              enabled: true,
              inline: true,
            ),
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

      // One pill, both selectors: the model name and the reasoning state share
      // the same surface, and the name gives way before the buttons do.
      expect(find.textContaining('Qwen Qwen3.5 2B'), findsOneWidget);
      expect(find.text(ReasoningChoice.thinkingOff.label), findsOneWidget);
      expect(find.byIcon(Icons.expand_more_rounded), findsNWidgets(2));
      expect(find.byKey(reasoningDividerKey), findsOneWidget);
    },
  );

  testWidgets(
    'a model with no reasoning choice draws one selector and no rule',
    (tester) async {
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
      expect(find.byKey(reasoningDividerKey), findsNothing);
    },
  );
}
