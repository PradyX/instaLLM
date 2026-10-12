import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pocket_llm/app.dart';
import 'package:pocket_llm/core/navigation/app_router.dart';
import 'package:pocket_llm/core/theme/appearance_preferences.dart';
import 'package:pocket_llm/core/theme/appearance_provider.dart';
import 'package:pocket_llm/core/theme/appearance_store.dart';
import 'package:pocket_llm/core/theme/theme_provider.dart';
import 'package:pocket_llm/core/widgets/chat_composer.dart';
import 'package:pocket_llm/features/settings/presentation/appearance_settings_section.dart';

void main() {
  late Directory directory;
  late File file;
  late Map<String, String> secureStore;
  late TextEditingController composer;
  late GoRouter router;
  late ProviderContainer container;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('appearance_widget');
    file = File('${directory.path}/appearance/preferences.json');
    secureStore = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args = call.arguments as Map;
            if (call.method == 'read') return secureStore[args['key']];
            if (call.method == 'write') {
              secureStore[args['key'] as String] = args['value'] as String;
            }
            return null;
          },
        );
    composer = TextEditingController();
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            key: const Key('appearance-probe'),
            appBar: AppBar(title: const Text('Appearance')),
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const AppearanceSettingsSection(),
                    ChatComposer(
                      controller: composer,
                      enabled: true,
                      hintText: 'Message',
                      onSend: () async {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
    container = ProviderContainer(
      overrides: [
        appearanceStoreProvider.overrideWith(
          (ref) async => AppearanceStore(file),
        ),
        appRouterProvider.overrideWithValue(router),
      ],
    );
  });
  tearDown(() async {
    router.dispose();
    container.dispose();
    composer.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
    await directory.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MyApp()),
    );
    await tester.pumpAndSettle();
  }

  Finder chip(String label) => find.widgetWithText(ChoiceChip, label);
  Future<void> select(WidgetTester tester, String label) async {
    await tester.ensureVisible(chip(label));
    await tester.tap(chip(label));
    await tester.pumpAndSettle();
  }

  ThemeData theme(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(AppearanceSettingsSection)));

  testWidgets(
    'shows separate mode, surface and accent controls with solid green defaults',
    (tester) async {
      await pump(tester);
      for (final text in [
        'Theme mode',
        'Surface style',
        'Accent colour',
        'Auto',
        'Light',
        'Dark',
        'Solid',
        'Translucent',
        'Green',
        'Blue',
        'Purple',
        'Teal',
        'Pink',
        'Orange',
        'Red',
        'Amber',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(tester.widget<ChoiceChip>(chip('Auto')).selected, isTrue);
      expect(tester.widget<ChoiceChip>(chip('Solid')).selected, isTrue);
      expect(tester.widget<ChoiceChip>(chip('Green')).selected, isTrue);
      expect(find.byType(BackdropFilter), findsNothing);
    },
  );

  testWidgets(
    'accent and surface selections update the real app theme and are saved',
    (tester) async {
      await pump(tester);
      final green = theme(tester).colorScheme.primary;
      await select(tester, 'Blue');
      await select(tester, 'Translucent');
      expect(theme(tester).colorScheme.primary, isNot(green));
      expect(theme(tester).scaffoldBackgroundColor.a, lessThan(1));
      expect(find.byType(BackdropFilter), findsWidgets);
      expect(jsonDecode(file.readAsStringSync()), {
        'version': 1,
        'surfaceStyle': 'translucent',
        'accent': 'blue',
      });
      await select(tester, 'Dark');
      expect(theme(tester).brightness, Brightness.dark);
      expect(
        container.read(appearanceProvider).preferences.accent,
        AccentColor.blue,
      );
      expect(
        container.read(appearanceProvider).preferences.surfaceStyle,
        SurfaceStyle.translucent,
      );
      expect(jsonDecode(secureStore['app_theme_mode']!)['mode'], 'dark');
    },
  );

  testWidgets(
    'switching back to solid removes blur and restores opaque surfaces',
    (tester) async {
      await pump(tester);
      await select(tester, 'Translucent');
      expect(find.byType(BackdropFilter), findsWidgets);
      await select(tester, 'Solid');
      expect(find.byType(BackdropFilter), findsNothing);
      expect(theme(tester).scaffoldBackgroundColor.a, 1);
      expect(
        container.read(appearanceProvider).preferences.surfaceStyle,
        SurfaceStyle.solid,
      );
    },
  );

  testWidgets('saved theme mode and appearance choices restore independently', (
    tester,
  ) async {
    secureStore['app_theme_mode'] = '{"mode":"dark"}';
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '{"version":1,"surfaceStyle":"translucent","accent":"pink"}',
    );
    await pump(tester);
    expect(tester.widget<ChoiceChip>(chip('Dark')).selected, isTrue);
    expect(tester.widget<ChoiceChip>(chip('Pink')).selected, isTrue);
    expect(tester.widget<ChoiceChip>(chip('Translucent')).selected, isTrue);
    expect(theme(tester).brightness, Brightness.dark);
    expect(container.read(themeModeNotifierProvider), ThemeMode.dark);
  });

  testWidgets('newer preferences disable edits and explain how to recover', (
    tester,
  ) async {
    const raw =
        '{"version":2,"surfaceStyle":"translucent","accent":"pink","future":true}';
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(raw);
    await pump(tester);
    expect(tester.widget<ChoiceChip>(chip('Blue')).onSelected, isNull);
    expect(tester.widget<ChoiceChip>(chip('Translucent')).onSelected, isNull);
    expect(
      find.text(
        'These appearance preferences need a newer app version. Update the app to change them.',
      ),
      findsOneWidget,
    );
    expect(file.readAsStringSync(), raw);
  });

  testWidgets('controls fit a narrow screen with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester);
    await select(tester, 'Translucent');
    await select(tester, 'Purple');
    expect(
      container.read(appearanceProvider).preferences.accent,
      AccentColor.purple,
    );
    expect(tester.takeException(), isNull);
  });
}
