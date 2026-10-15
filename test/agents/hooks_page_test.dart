import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/features/agents/application/hooks_controller.dart';
import 'package:installm/features/agents/data/hook_store.dart';
import 'package:installm/features/agents/presentation/hooks_page.dart';
import 'package:installm/features/settings/presentation/settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late File file;
  late ProviderContainer container;

  setUp(() {
    root = Directory.systemTemp.createTempSync('hooks-page-');
    file = File('${root.path}/agents/hooks.json');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => root.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
    container = ProviderContainer(
      overrides: [
        hookStoreProvider.overrideWith((ref) async => HookStore(file)),
      ],
    );
  });

  tearDown(() {
    container.dispose();
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
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HooksPage()),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> addRule(
    WidgetTester tester, {
    required String name,
    String path = '',
    String tool = '*',
    bool ask = false,
  }) async {
    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('hook-name')), name);
    await tester.enterText(find.byKey(const ValueKey('hook-path')), path);
    await tester.enterText(find.byKey(const ValueKey('hook-tool')), tool);
    if (ask) {
      await tester.tap(find.text('Ask first'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists the built-in floor read-only and no rules of its own', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Git internals'), findsOneWidget);
    expect(find.textContaining('Always on'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('builtin-builtin-git-internals')),
        matching: find.byType(Switch),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('builtin-builtin-git-internals')),
        matching: find.byIcon(Icons.delete_outline),
      ),
      findsNothing,
    );
    expect(find.textContaining('No rules of your own yet'), findsOneWidget);
  });

  testWidgets('adds, disables, edits and deletes a rule through the file', (
    tester,
  ) async {
    await pump(tester);
    await addRule(tester, name: 'Protect secrets', path: 'secrets/**');

    expect(find.text('Protect secrets'), findsOneWidget);
    expect(find.textContaining('secrets/**'), findsOneWidget);
    var stored = HookStore(file).load().hooks;
    expect(stored.single.name, 'Protect secrets');
    expect(stored.single.resourcePattern, 'secrets/**');
    expect(stored.single.level.name, 'refuse');

    final row = find.byKey(ValueKey('hook-${stored.single.id}'));
    await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(HookStore(file).load().hooks.single.enabled, isFalse);

    await tester.tap(find.text('Protect secrets'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('hook-name')),
      'Protect keys',
    );
    await tester.tap(find.text('Ask first'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    stored = HookStore(file).load().hooks;
    expect(stored.single.name, 'Protect keys');
    expect(stored.single.level.name, 'ask');
    expect(find.text('Protect keys'), findsOneWidget);

    await tester.tap(
      find.descendant(of: row, matching: find.byIcon(Icons.delete_outline)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Delete the hook'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(HookStore(file).load().hooks, isEmpty);
    expect(find.textContaining('No rules of your own yet'), findsOneWidget);
  });

  testWidgets('a nameless rule is refused before it is stored', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('hook-name')), '  ');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Give the rule a name'), findsWidgets);
    expect(file.existsSync(), isFalse);
  });

  testWidgets('a store from a newer build stays read-only', (tester) async {
    file.parent.createSync(recursive: true);
    const raw = '{"version":99,"hooks":[{"future":"keep"}]}';
    file.writeAsStringSync(raw);

    await pump(tester);

    expect(find.textContaining('newer version'), findsOneWidget);
    expect(file.readAsStringSync(), raw);
  });

  testWidgets('fits 320px and 2x text', (tester) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester);
    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('Settings opens the hooks page from its Hooks entry', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: AppRoutes.settings,
      routes: [
        GoRoute(
          path: AppRoutes.settings,
          builder: (_, _) => const SettingsPage(),
        ),
        GoRoute(path: AppRoutes.hooks, builder: (_, _) => const HooksPage()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Hooks'), 300);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hooks'));
    await tester.pumpAndSettle();

    expect(find.byType(HooksPage), findsOneWidget);
    expect(find.text('Git internals'), findsOneWidget);
  });
}
