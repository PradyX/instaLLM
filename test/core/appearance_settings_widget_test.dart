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
import 'package:pocket_llm/features/settings/presentation/accent_theme_tile.dart';

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
  Finder tile(String label) => find.widgetWithText(AccentThemeTile, label);
  Finder slider(String key) => find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(Slider),
  );
  Future<void> select(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> slideToMax(WidgetTester tester, String key) async {
    final control = slider(key);
    await tester.ensureVisible(control);
    await tester.pumpAndSettle();
    final rect = tester.getRect(control);
    await tester.tapAt(Offset(rect.right - 8, rect.center.dy));
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
      expect(tester.widget<AccentThemeTile>(tile('Green')).selected, isTrue);
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
        'version': 2,
        'surfaceStyle': 'translucent',
        'accent': 'blue',
        'contrast': 1.0,
        'glassOpacity': 0.78,
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
    expect(tester.widget<AccentThemeTile>(tile('Pink')).selected, isTrue);
    expect(tester.widget<ChoiceChip>(chip('Translucent')).selected, isTrue);
    expect(theme(tester).brightness, Brightness.dark);
    expect(container.read(themeModeNotifierProvider), ThemeMode.dark);
  });

  testWidgets('newer preferences disable edits and explain how to recover', (
    tester,
  ) async {
    const raw =
        '{"version":3,"surfaceStyle":"translucent","accent":"pink","future":true}';
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(raw);
    await pump(tester);
    expect(tester.widget<AccentThemeTile>(tile('Blue')).onSelected, isNull);
    expect(
      tester.widget<Slider>(slider('appearance-contrast')).onChanged,
      isNull,
    );
    expect(
      tester.widget<Slider>(slider('appearance-glass-opacity')).onChanged,
      isNull,
    );
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
    await slideToMax(tester, 'appearance-contrast');
    await slideToMax(tester, 'appearance-glass-opacity');
    expect(
      container.read(appearanceProvider).preferences.accent,
      AccentColor.purple,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'slider drag commits once on release and updates the real app theme',
    (tester) async {
      await pump(tester);
      final normal = theme(tester).colorScheme.primary;
      final control = slider('appearance-contrast');
      await tester.ensureVisible(control);
      await tester.pumpAndSettle();
      final rect = tester.getRect(control);
      final gesture = await tester.startGesture(rect.center);
      await tester.pump();
      await gesture.moveTo(Offset(rect.right - 8, rect.center.dy));
      await tester.pump();
      expect(file.existsSync(), isFalse);
      expect(theme(tester).colorScheme.primary, normal);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(container.read(appearanceProvider).preferences.contrast, 2);
      expect(theme(tester).colorScheme.primary, isNot(normal));
      expect(jsonDecode(file.readAsStringSync())['contrast'], 2);
    },
  );

  testWidgets(
    'glass slider enables with translucent, colours the composer, and survives restart',
    (tester) async {
      await pump(tester);
      expect(
        tester.widget<Slider>(slider('appearance-glass-opacity')).onChanged,
        isNull,
      );
      await select(tester, 'Translucent');
      await slideToMax(tester, 'appearance-glass-opacity');
      expect(container.read(appearanceProvider).preferences.glassOpacity, 1);
      expect(theme(tester).cardTheme.color!.a, 1);
      final composerBox = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ChatComposer),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((composerBox.decoration as BoxDecoration).color!.a, 1);
      expect(AppearanceStore(file).load().glassOpacity, 1);
      await select(tester, 'Solid');
      expect(
        tester.widget<Slider>(slider('appearance-glass-opacity')).onChanged,
        isNull,
      );
      expect(container.read(appearanceProvider).preferences.glassOpacity, 1);
    },
  );

  testWidgets('accent tiles resize into columns and expose their selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    await pump(tester);
    final green = tester.getRect(tile('Green'));
    final blue = tester.getRect(tile('Blue'));
    expect(green.top, blue.top);
    expect(blue.left, greaterThan(green.right));
    await select(tester, 'Blue');
    expect(tester.widget<AccentThemeTile>(tile('Blue')).selected, isTrue);
    expect(
      tester.getSemantics(tile('Blue')),
      matchesSemantics(
        label: 'Blue',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    tester.view.physicalSize = const Size(320, 900);
    await tester.pumpAndSettle();
    final resizedGreen = tester.getRect(tile('Green'));
    final resizedBlue = tester.getRect(tile('Blue'));
    expect(resizedGreen.left, resizedBlue.left);
    expect(resizedBlue.top, greaterThan(resizedGreen.bottom));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
