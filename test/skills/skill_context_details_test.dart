import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/skills/application/skill_usage.dart';
import 'package:installm/features/skills/application/skill_session.dart';
import 'package:installm/features/skills/domain/skill.dart';
import 'package:installm/features/skills/presentation/skill_context_details.dart';

void main() {
  test(
    'script results share the resource/body budget and cannot exhaust the full context',
    () {
      final session = SkillSession(
        skills: [Skill.create(name: 'docs', body: 'Instructions')],
        tokenBudget: 200,
        isCurrent: (_) => true,
      );
      final result = session.recordScriptResult('Output data ' * 4000);
      expect(result.length, lessThan(800));
      expect(session.scriptTokens, greaterThan(0));
      expect(session.usedTokens, lessThanOrEqualTo(200));
      final usage = SkillUsage.capture(
        session,
        input: 900,
        reserved: 128,
        window: 2048,
      );
      expect(usage.skills + usage.otherInput, usage.inputTokens);
      expect(usage.otherInput, greaterThan(0));
      expect(session.recordScriptResult('more data'), contains('omitted'));
    },
  );
  testWidgets('ordinary context readout remains visible when no skill ran', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SkillContextDetails(
              sessionKey: 'conversation:normal',
              child: Text('Context: 42'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Context: 42'), findsOneWidget);
    expect(find.textContaining('Context details'), findsNothing);
  });
  for (final brightness in Brightness.values) {
    testWidgets(
      'context inspector remains readable at 320px 2x text in ${brightness.name}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              skillUsageProvider.overrideWith(
                (ref) => {
                  'room:c': const SkillUsage(
                    instructions: 20,
                    resources: 30,
                    scriptResults: 40,
                    inputTokens: 600,
                    reservedOutput: 128,
                    window: 1024,
                  ),
                },
              ),
            ],
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: const Scaffold(
                body: SkillContextDetails(sessionKey: 'room:c'),
              ),
            ),
          ),
        );
        await tester.tap(find.textContaining('Context details'));
        await tester.pumpAndSettle();
        expect(find.text('Skill instructions'), findsOneWidget);
        expect(find.text('Skill resources'), findsOneWidget);
        expect(find.text('Skill script results'), findsOneWidget);
        expect(
          find.text('510'),
          findsOneWidget,
        ); // Other input, not double-counted.
        expect(find.text('600'), findsOneWidget);
        expect(find.text('128'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
