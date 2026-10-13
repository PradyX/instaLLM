import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/settings/reasoning_settings_provider.dart';
import 'package:installm/core/widgets/composer_reasoning_pill.dart';
import 'package:installm/features/model_selection/domain/model_reasoning.dart';
import 'package:installm/features/model_selection/presentation/model_reasoning_provider.dart';

/// What a thinking model declares, in the shape the parser produces: two states,
/// thinking on by default, and the template's own rendering for each.
const _thinkingModel = ModelReasoning(
  defaultChoice: ReasoningChoice.thinkingOn,
  prefills: {
    ReasoningChoice.thinkingOn: '',
    ReasoningChoice.thinkingOff: '<think>\n\n</think>\n\n',
  },
);

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> secureStore;

  setUp(() {
    secureStore = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final arguments = (call.arguments as Map).cast<String, Object?>();
            final key = arguments['key'] as String?;
            if (key == null) return null;
            if (call.method == 'write') {
              secureStore[key] = arguments['value'] as String;
              return null;
            }
            if (call.method == 'read') return secureStore[key];
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });

  testWidgets('names the state in force', (tester) async {
    await _pump(
      tester,
      const ComposerReasoningPill(
        reasoning: _thinkingModel,
        choice: ReasoningChoice.thinkingOff,
        enabled: true,
      ),
    );

    expect(find.text('No thinking'), findsOneWidget);
  });

  testWidgets('offers the states the model declares, default marked', (
    tester,
  ) async {
    await _pump(
      tester,
      const ComposerReasoningPill(
        reasoning: _thinkingModel,
        choice: ReasoningChoice.thinkingOn,
        enabled: true,
      ),
    );

    await tester.tap(find.text('Thinking'));
    await tester.pumpAndSettle();

    expect(
      find.byType(CheckedPopupMenuItem<ReasoningChoice>),
      findsNWidgets(2),
    );
    expect(find.text('No thinking'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    // The state in force is the checked one.
    final checked = tester.widget<CheckedPopupMenuItem<ReasoningChoice>>(
      find.widgetWithText(CheckedPopupMenuItem<ReasoningChoice>, 'Thinking'),
    );
    expect(checked.checked, isTrue);
  });

  testWidgets('reports the state the user picked', (tester) async {
    ReasoningChoice? picked;
    await _pump(
      tester,
      ComposerReasoningPill(
        reasoning: _thinkingModel,
        choice: ReasoningChoice.thinkingOn,
        enabled: true,
        onSelected: (choice) => picked = choice,
      ),
    );

    await tester.tap(find.text('Thinking'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<ReasoningChoice>, 'No thinking'),
    );
    await tester.pumpAndSettle();

    expect(picked, ReasoningChoice.thinkingOff);
  });

  testWidgets('a run in flight keeps it closed', (tester) async {
    await _pump(
      tester,
      const ComposerReasoningPill(
        reasoning: _thinkingModel,
        choice: ReasoningChoice.thinkingOn,
        enabled: false,
      ),
    );

    await tester.tap(find.text('Thinking'));
    await tester.pumpAndSettle();

    expect(find.byType(CheckedPopupMenuItem<ReasoningChoice>), findsNothing);
  });

  group('the control beside the model pill', () {
    Future<ProviderContainer> pumpControl(
      WidgetTester tester,
      ModelReasoning? reasoning,
    ) async {
      final container = ProviderContainer(
        overrides: [
          modelReasoningProvider(
            'm-alpha',
          ).overrideWith((ref) async => reasoning),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: Center(
                child: ComposerReasoningControl(
                  modelId: 'm-alpha',
                  enabled: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('draws nothing for a model that declares no reasoning', (
      tester,
    ) async {
      await pumpControl(tester, null);

      // Not a disabled chip, not an explanatory label: nothing. The model has
      // no such setting, and an empty control would invent one.
      expect(find.byType(ComposerReasoningPill), findsNothing);
      expect(find.text('Thinking'), findsNothing);
    });

    testWidgets('draws the model\'s own states and remembers the pick', (
      tester,
    ) async {
      final container = await pumpControl(tester, _thinkingModel);

      // Nothing chosen yet: the chip shows the model's default.
      expect(find.text('Thinking'), findsOneWidget);

      await tester.tap(find.text('Thinking'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          CheckedPopupMenuItem<ReasoningChoice>,
          'No thinking',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        container.read(reasoningSettingsProvider).choiceFor('m-alpha'),
        ReasoningChoice.thinkingOff,
      );
      expect(find.text('No thinking'), findsOneWidget);
      expect(
        secureStore[ReasoningSettingsNotifier.settingsKey],
        contains('m-alpha'),
      );
    });
  });
}
