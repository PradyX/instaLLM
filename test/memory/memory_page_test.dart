import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/features/memory/application/memory_controller.dart';
import 'package:installm/features/memory/domain/memory_fact.dart';
import 'package:installm/features/memory/presentation/memory_page.dart';
import 'package:installm/features/settings/presentation/settings_page.dart';
import 'package:installm/features/home/presentation/home_page.dart';
import 'package:installm/core/widgets/chat_composer.dart';

import 'memory_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryTestHarness harness;
  late ProviderContainer container;
  setUp(() {
    harness = MemoryTestHarness();
    container = harness.container();
  });
  tearDown(() => harness.close());

  Future<void> pump(
    WidgetTester tester, {
    bool dark = false,
    double scale = 1,
  }) async {
    await tester.runAsync(() => harness.home(container));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const MemoryPage(),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseScope(WidgetTester tester, String scope) async {
    await tester.tap(find.byType(DropdownButtonFormField<MemoryScope>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(scope).last);
    await tester.pumpAndSettle();
  }

  Future<void> action(WidgetTester tester, String id, String action) async {
    final row = find.byKey(ValueKey('fact-$id'));
    await tester.ensureVisible(row);
    await tester.tap(
      find.descendant(of: row, matching: find.byType(PopupMenuButton<String>)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  testWidgets('Settings Memory entry opens the management page', (
    tester,
  ) async {
    await tester.runAsync(() => harness.home(container));
    final router = GoRouter(
      initialLocation: AppRoutes.settings,
      routes: [
        GoRoute(
          path: AppRoutes.settings,
          builder: (_, _) => const SettingsPage(),
        ),
        GoRoute(path: AppRoutes.memory, builder: (_, _) => const MemoryPage()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Memory'), 300);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Memory'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Memory'));
    await tester.pumpAndSettle();
    expect(find.byType(MemoryPage), findsOneWidget);
    expect(find.text('No saved facts yet.'), findsOneWidget);
  });

  testWidgets('home composer accepts memory commands with no installed model', (
    tester,
  ) async {
    await tester.runAsync(() => harness.home(container));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    final composer = find.byType(ChatComposer);
    expect(tester.widget<ChatComposer>(composer).enabled, isTrue);
    await tester.enterText(
      find.descendant(of: composer, matching: find.byType(TextField)),
      'remember Use Dart.',
    );
    await tester.tap(find.byTooltip('Send'));
    for (
      var attempt = 0;
      attempt < 80 && harness.memoryStore.load().isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();
    expect(harness.memoryStore.load().single.text, 'Use Dart.');
    expect(harness.engine.prompts, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Settings can add a workspace fact and refuses invalid dates', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Add fact'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('memory-text')),
      'Use Flutter for this project.',
    );
    await chooseScope(tester, 'Workspace');
    await tester.enterText(
      find.byKey(const ValueKey('memory-expiry')),
      '2026-02-31',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid date as YYYY-MM-DD.'), findsOneWidget);
    expect(harness.memoryStore.load(), isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('memory-expiry')),
      '2027-01-01',
    );
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: container.read(memoryProvider).errorMessage,
    );
    final fact = harness.memoryStore.load().single;
    expect(fact.ownerId, 'ws1');
    expect(fact.scope, MemoryScope.workspace);
    expect(fact.source, MemorySource.userStated);
    expect(fact.expiresAt, DateTime(2027));
    expect(find.text('Use Flutter for this project.'), findsOneWidget);
  });

  testWidgets('global opt-in is per fact and can be revoked through editing', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Add fact'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('memory-text')),
      'I prefer brief answers.',
    );
    await chooseScope(tester, 'Global');
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(harness.memoryStore.load(), isEmpty);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    final fact = harness.memoryStore.load().single;
    expect(fact.globalOptIn, isTrue);
    await action(tester, fact.id, 'Edit fact');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(harness.memoryStore.load().single.globalOptIn, isFalse);
    expect(find.textContaining('Global recall off'), findsOneWidget);
    await tester.tap(find.byTooltip('Add fact'));
    await tester.pumpAndSettle();
    await chooseScope(tester, 'Global');
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'inferred and expired facts stay visible, editable and individually deletable',
    (tester) async {
      final fact = await tester.runAsync(
        () async => container
            .read(memoryProvider.notifier)
            .remember(
              text: 'An inferred fact',
              scope: MemoryScope.workspace,
              ownerId: 'ws2',
              source: MemorySource.inferred,
              expiresAt: DateTime(2000),
            ),
      );
      await pump(tester);
      expect(find.textContaining('Inferred'), findsOneWidget);
      expect(find.textContaining('Expired'), findsOneWidget);
      expect(find.textContaining('Project two'), findsOneWidget);
      await action(tester, fact!.id, 'Edit fact');
      await tester.enterText(
        find.byKey(const ValueKey('memory-text')),
        'A corrected fact',
      );
      await tester.enterText(find.byKey(const ValueKey('memory-expiry')), '');
      await tester.tap(find.text('Save'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(harness.memoryStore.load().single.source, MemorySource.inferred);
      expect(harness.memoryStore.load().single.expiresAt, isNull);
      await action(tester, fact.id, 'Delete');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(harness.memoryStore.load(), hasLength(1));
      await action(tester, fact.id, 'Delete');
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(harness.memoryStore.load(), isEmpty);
    },
  );

  for (final dark in [false, true]) {
    testWidgets('fits 320px and 2x text ${dark ? 'dark' : 'light'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(
        () async => container
            .read(memoryProvider.notifier)
            .remember(
              text: 'A fact with enough words to wrap across several lines.',
              ownerId: 'old-chat',
              source: MemorySource.inferred,
            ),
      );
      await pump(tester, dark: dark, scale: 2);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Add fact'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('unsupported schema is read-only and remains untouched', (
    tester,
  ) async {
    final file = File('${harness.root.path}/facts.json');
    const raw = '{"version":99,"facts":[{"future":"keep"}]}';
    file.writeAsStringSync(raw);
    await pump(tester);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(Icons.add),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('unsupported format'), findsOneWidget);
    expect(file.readAsStringSync(), raw);
  });
}
