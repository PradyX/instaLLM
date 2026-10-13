import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/theme/appearance_preferences.dart';
import 'package:installm/core/theme/appearance_provider.dart';
import 'package:installm/core/theme/appearance_store.dart';
import 'package:installm/core/theme/appearance_surfaces.dart';
import 'package:installm/core/theme/theme.dart';
import 'package:installm/core/theme/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File file;
  late AppearanceStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('appearance_test');
    file = File('${directory.path}/appearance/preferences.json');
    store = AppearanceStore(file);
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<ProviderContainer> loaded() async {
    final container = ProviderContainer(
      overrides: [appearanceStoreProvider.overrideWith((ref) async => store)],
    );
    addTearDown(container.dispose);
    container.read(appearanceProvider);
    for (
      var i = 0;
      i < 50 && !container.read(appearanceProvider).isReady;
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(container.read(appearanceProvider).isReady, isTrue);
    return container;
  }

  test('defaults to solid green without creating a preferences file', () {
    final preferences = store.load();
    expect(preferences.surfaceStyle, SurfaceStyle.solid);
    expect(preferences.accent, AccentColor.green);
    expect(preferences.contrast, 1);
    expect(preferences.glassOpacity, 0.78);
    expect(file.existsSync(), isFalse);
  });

  test(
    'persists appearance preferences with a schema version and restores on restart',
    () async {
      final first = await loaded();
      final notifier = first.read(appearanceProvider.notifier);
      expect(await notifier.setSurfaceStyle(SurfaceStyle.translucent), isTrue);
      expect(await notifier.setAccent(AccentColor.grey), isTrue);
      expect(await notifier.setContrast(1.5), isTrue);
      expect(await notifier.setGlassOpacity(0.9), isTrue);
      expect(jsonDecode(file.readAsStringSync()), {
        'version': 2,
        'surfaceStyle': 'translucent',
        'accent': 'grey',
        'contrast': 1.5,
        'glassOpacity': 0.9,
      });
      final second = await loaded();
      expect(
        second.read(appearanceProvider).preferences.surfaceStyle,
        SurfaceStyle.translucent,
      );
      expect(
        second.read(appearanceProvider).preferences.accent,
        AccentColor.grey,
      );
      expect(second.read(appearanceProvider).preferences.contrast, 1.5);
      expect(second.read(appearanceProvider).preferences.glassOpacity, 0.9);
    },
  );

  test('concurrent selections preserve all choices', () async {
    final container = await loaded();
    final notifier = container.read(appearanceProvider.notifier);
    expect(
      await Future.wait([
        notifier.setSurfaceStyle(SurfaceStyle.translucent),
        notifier.setAccent(AccentColor.blue),
        notifier.setContrast(1.4),
        notifier.setGlassOpacity(0.7),
      ]),
      [true, true, true, true],
    );
    final restored = store.load();
    expect(restored.surfaceStyle, SurfaceStyle.translucent);
    expect(restored.accent, AccentColor.blue);
    expect(restored.contrast, 1.4);
    expect(restored.glassOpacity, 0.7);
  });

  test(
    'reads partial unversioned preferences and upgrades without losing a valid choice',
    () {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('{"accent":"teal","surfaceStyle":42}');
      final preferences = store.load();
      expect(preferences.accent, AccentColor.teal);
      expect(preferences.surfaceStyle, SurfaceStyle.solid);
      expect(store.save(preferences), isTrue);
      expect(jsonDecode(file.readAsStringSync())['version'], 2);
      expect(store.load().accent, AccentColor.teal);
    },
  );

  test(
    'unknown choices fall back per field and preserve a valid other field',
    () {
      final preferences = AppearancePreferences.fromJson({
        'accent': 'future-colour',
        'surfaceStyle': 'translucent',
      });
      expect(preferences.accent, AccentColor.green);
      expect(preferences.surfaceStyle, SurfaceStyle.translucent);
    },
  );

  test('backs up corrupt JSON before writing valid preferences', () {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('broken json');
    expect(store.load().accent, AccentColor.green);
    expect(
      store.save(const AppearancePreferences(accent: AccentColor.red)),
      isTrue,
    );
    final backups = file.parent.listSync().whereType<File>().where(
      (file) => file.path.contains('.corrupt-'),
    );
    expect(backups, hasLength(1));
    expect(backups.single.readAsStringSync(), 'broken json');
  });

  test('an unusable payload is preserved before recovery', () {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('{"version":1,"accent":7}');
    store.load();
    expect(store.save(const AppearancePreferences()), isTrue);
    expect(
      file.parent.listSync().where((file) => file.path.contains('.corrupt-')),
      hasLength(1),
    );
  });

  test('newer preferences stay read-only and untouched', () async {
    file.parent.createSync(recursive: true);
    const raw =
        '{"version":3,"accent":"blue","surfaceStyle":"translucent","future":true}';
    file.writeAsStringSync(raw);
    final container = await loaded();
    expect(container.read(appearanceProvider).isReadOnly, isTrue);
    expect(
      await container
          .read(appearanceProvider.notifier)
          .setAccent(AccentColor.red),
      isFalse,
    );
    expect(file.readAsStringSync(), raw);
    expect(
      await container.read(appearanceProvider.notifier).setContrast(2),
      isFalse,
    );
    expect(
      await container.read(appearanceProvider.notifier).setGlassOpacity(1),
      isFalse,
    );
  });

  test(
    'v1 choices migrate to v2 on a save without changing the saved theme',
    () async {
      file.parent.createSync(recursive: true);
      const raw =
          '{"version":1,"accent":"orange","surfaceStyle":"translucent"}';
      file.writeAsStringSync(raw);
      final container = await loaded();
      final initial = container.read(appearanceProvider).preferences;
      expect(initial.accent, AccentColor.orange);
      expect(initial.surfaceStyle, SurfaceStyle.translucent);
      expect(initial.contrast, 1);
      expect(initial.glassOpacity, 0.78);
      expect(file.readAsStringSync(), raw);
      await container.read(appearanceProvider.notifier).setContrast(1.5);
      expect(jsonDecode(file.readAsStringSync()), {
        'version': 2,
        'accent': 'orange',
        'surfaceStyle': 'translucent',
        'contrast': 1.5,
        'glassOpacity': 0.78,
      });
      expect(
        file.parent.listSync().where((file) => file.path.contains('.corrupt-')),
        isEmpty,
      );
    },
  );

  test(
    'partial v2 data preserves valid numbers and repairs invalid fields',
    () {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        '{"version":2,"glassOpacity":0.65,"contrast":"strong"}',
      );
      final preferences = store.load();
      expect(preferences.glassOpacity, 0.65);
      expect(preferences.contrast, 1);
      expect(preferences.accent, AccentColor.green);
      expect(store.save(preferences), isTrue);
      expect(store.load().glassOpacity, 0.65);
      final bounded = AppearancePreferences.fromJson({
        'contrast': 999,
        'glassOpacity': -1,
        'accent': 'pink',
      });
      expect(bounded.contrast, 2);
      expect(bounded.glassOpacity, 0.5);
      expect(bounded.accent, AccentColor.pink);
      final invalid = AppearancePreferences.fromJson({
        'contrast': double.nan,
        'glassOpacity': double.infinity,
      });
      expect(invalid.contrast, 1);
      expect(invalid.glassOpacity, 0.78);
    },
  );

  test('invalid slider values are normalized before being written', () async {
    final container = await loaded();
    final notifier = container.read(appearanceProvider.notifier);
    expect(await notifier.setContrast(double.nan), isTrue);
    expect(await notifier.setGlassOpacity(double.infinity), isTrue);
    expect(store.load().contrast, 1);
    expect(store.load().glassOpacity, 0.78);
    expect(await notifier.setGlassOpacity(10), isTrue);
    expect(store.load().glassOpacity, 1);
  });

  test(
    'failed persistence leaves the existing appearance and reports a save error',
    () async {
      final container = await loaded();
      // A regular file where the preferences directory should be prevents saving.
      File(file.parent.path).writeAsStringSync('preserve this file');
      expect(
        await container
            .read(appearanceProvider.notifier)
            .setAccent(AccentColor.blue),
        isFalse,
      );
      expect(
        container.read(appearanceProvider).preferences.accent,
        AccentColor.green,
      );
      expect(container.read(appearanceProvider).error, AppearanceError.save);
      expect(File(file.parent.path).readAsStringSync(), 'preserve this file');
    },
  );

  test(
    'surface/accent preferences retain the legacy saved dark theme mode',
    () async {
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      const legacy = '{"mode":"dark"}';
      final writes = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'read' &&
                (call.arguments as Map)['key'] == 'app_theme_mode') {
              return legacy;
            }
            if (call.method == 'write') {
              writes.add((call.arguments as Map)['key'] as String);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final container = await loaded();
      final subscription = container.listen(
        themeModeNotifierProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      for (
        var i = 0;
        i < 50 && container.read(themeModeNotifierProvider) != ThemeMode.dark;
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      await container
          .read(appearanceProvider.notifier)
          .setAccent(AccentColor.blue);
      expect(container.read(themeModeNotifierProvider), ThemeMode.dark);
      expect(writes, isEmpty);
    },
  );

  test('default solid green keeps the original colour schemes', () {
    const theme = MaterialTheme(TextTheme());
    expect(theme.light().colorScheme, MaterialTheme.lightScheme());
    expect(theme.dark().colorScheme, MaterialTheme.darkScheme());
    expect(theme.light().scaffoldBackgroundColor.a, 1);
  });

  test(
    'every accent has readable light/dark foregrounds and colours its theme',
    () {
      double contrast(Color a, Color b) {
        final first = a.computeLuminance();
        final second = b.computeLuminance();
        return ((first > second ? first : second) + 0.05) /
            ((first < second ? first : second) + 0.05);
      }

      final lightPrimaries = <Color>{};
      for (final accent in AccentColor.values) {
        final theme = MaterialTheme(const TextTheme(), accent: accent);
        lightPrimaries.add(theme.light().colorScheme.primary);
        for (final data in [theme.light(), theme.dark()]) {
          expect(
            contrast(data.colorScheme.primary, data.colorScheme.onPrimary),
            greaterThanOrEqualTo(4.5),
            reason: '${accent.name} ${data.brightness}',
          );
          expect(
            contrast(data.colorScheme.surface, data.colorScheme.onSurface),
            greaterThanOrEqualTo(4.5),
            reason: '${accent.name} ${data.brightness}',
          );
        }
      }
      expect(lightPrimaries, hasLength(AccentColor.values.length));
    },
  );

  test(
    'translucent themes enable glass surfaces while keeping text/button colours opaque',
    () {
      const theme = MaterialTheme(
        TextTheme(),
        accent: AccentColor.blue,
        surfaceStyle: SurfaceStyle.translucent,
      );
      for (final data in [theme.light(), theme.dark()]) {
        expect(data.extension<SurfaceAppearance>()!.isTranslucent, isTrue);
        expect(data.scaffoldBackgroundColor.a, lessThan(1));
        expect(data.colorScheme.onSurface.a, 1);
        expect(data.colorScheme.primary.a, 1);
      }
    },
  );

  test(
    'contrast increases readable foreground and border contrast for every accent',
    () {
      double ratio(Color a, Color b) {
        final first = a.computeLuminance();
        final second = b.computeLuminance();
        return ((first > second ? first : second) + 0.05) /
            ((first < second ? first : second) + 0.05);
      }

      for (final accent in AccentColor.values) {
        final normal = MaterialTheme(const TextTheme(), accent: accent);
        final strong = MaterialTheme(
          const TextTheme(),
          accent: accent,
          contrast: 2,
        );
        for (final brightness in Brightness.values) {
          final baseline = normal.scheme(brightness);
          final adjusted = strong.scheme(brightness);
          expect(adjusted.primary, isNot(baseline.primary));
          expect(
            ratio(adjusted.onPrimary, adjusted.primary),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            ratio(adjusted.onSurface, adjusted.surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            ratio(adjusted.outline, adjusted.surface),
            greaterThan(ratio(baseline.outline, baseline.surface)),
          );
        }
      }
    },
  );

  test(
    'glass opacity controls panels and becomes fully opaque at 100 percent',
    () {
      for (final brightness in Brightness.values) {
        for (final opacity in [0.5, 0.78, 1.0]) {
          final theme = MaterialTheme(
            const TextTheme(),
            surfaceStyle: SurfaceStyle.translucent,
            glassOpacity: opacity,
          );
          final data = theme.theme(theme.scheme(brightness));
          expect(data.extension<SurfaceAppearance>()!.glassOpacity, opacity);
          expect(data.cardTheme.color!.a, closeTo(opacity, 0.001));
          expect(data.dialogTheme.backgroundColor!.a, closeTo(opacity, 0.001));
          expect(data.popupMenuTheme.color!.a, closeTo(opacity, 0.001));
          expect(data.colorScheme.onSurface.a, 1);
          expect(
            data.scaffoldBackgroundColor.a,
            closeTo(
              opacity == 1
                  ? 1
                  : opacity == 0.78
                  ? 0.54
                  : 0.346,
              0.002,
            ),
          );
        }
      }
      expect(
        const MaterialTheme(
              TextTheme(),
              glassOpacity: 0.5,
            ).light().cardTheme.color?.a ??
            1,
        1,
      );
    },
  );
}
