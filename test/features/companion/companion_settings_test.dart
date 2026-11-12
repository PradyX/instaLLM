import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/companion/application/companion_settings_controller.dart';
import 'package:installm/features/companion/data/companion_settings_store.dart';
import 'package:installm/features/companion/domain/companion_settings.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late CompanionSettingsStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('companion-settings-');
    store = CompanionSettingsStore(
      File(p.join(tempDir.path, 'companion', 'settings.json')),
    );
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('CompanionSettings', () {
    test('an untouched install is called Ada and switched off', () {
      const settings = CompanionSettings();
      expect(settings.name, 'Ada');
      expect(settings.enabled, isFalse);
      expect(settings.wakeSensitivity, 0.6);
      expect(settings.silenceTimeout, const Duration(milliseconds: 1500));
      expect(settings.wakePhrase, 'Hey Ada');
    });

    test('out-of-range values are clamped into what the screen can show', () {
      final settings = CompanionSettings(
        name: '  Kai  ',
        wakeSensitivity: 1.9,
        silenceTimeout: const Duration(milliseconds: 5000),
      ).normalized();

      expect(settings.name, 'Kai');
      expect(settings.wakeSensitivity, 1.0);
      expect(settings.silenceTimeout, const Duration(milliseconds: 3000));
      expect(
        const CompanionSettings(
          silenceTimeout: Duration(milliseconds: 250),
        ).normalized().silenceTimeout,
        const Duration(milliseconds: 800),
      );
      expect(
        const CompanionSettings(
          silenceTimeout: Duration(milliseconds: 1475),
        ).normalized().silenceTimeout,
        const Duration(milliseconds: 1500),
      );
    });

    test('a name the app cannot use falls back instead of breaking', () {
      expect(const CompanionSettings(name: 'A').normalized().name, 'Ada');
      expect(const CompanionSettings(name: '   ').normalized().name, 'Ada');
      expect(
        CompanionSettings(name: 'X' * 21).normalized().name,
        CompanionSettings.defaultName,
      );
    });

    test('reads a partial payload field by field', () {
      final settings = CompanionSettings.fromJson({
        'version': 1,
        'name': 'Nova',
      });
      expect(settings.name, 'Nova');
      expect(settings.enabled, isFalse);
      expect(
        settings.wakeSensitivity,
        CompanionSettings.defaultWakeSensitivity,
      );
    });

    test('validates the name length and warns about hard-to-say names', () {
      expect(CompanionSettings.validateName(''), isNotNull);
      expect(CompanionSettings.validateName('A'), isNotNull);
      expect(CompanionSettings.validateName('X' * 21), isNotNull);
      expect(CompanionSettings.validateName('Ada'), isNull);
      expect(CompanionSettings.validateName('  Kai  '), isNull);

      expect(CompanionSettings.nameWarning('Ada'), isNull);
      expect(CompanionSettings.nameWarning("O'Brien"), isNull);
      expect(CompanionSettings.nameWarning('Zoë'), isNotNull);
    });
  });

  group('CompanionSettingsStore', () {
    test('a missing file means the defaults', () {
      expect(store.load().enabled, isFalse);
      expect(store.load().name, CompanionSettings.defaultName);
      expect(store.isReadOnly, isFalse);
    });

    test('round-trips every field', () {
      final saved = CompanionSettings(
        name: 'Nova',
        enabled: true,
        wakeSensitivity: 0.9,
        silenceTimeout: const Duration(milliseconds: 2200),
      );
      expect(store.save(saved), isTrue);

      final loaded = store.load();
      expect(loaded.name, 'Nova');
      expect(loaded.enabled, isTrue);
      expect(loaded.wakeSensitivity, 0.9);
      expect(loaded.silenceTimeout, const Duration(milliseconds: 2200));
      expect(jsonDecode(File(store.filePath).readAsStringSync())['version'], 1);
    });

    test('copies an unreadable file aside before rewriting it', () {
      final file = File(store.filePath)..createSync(recursive: true);
      file.writeAsStringSync('{not json');

      expect(store.load().enabled, isFalse);
      expect(store.save(const CompanionSettings(name: 'Kai')), isTrue);

      final backups = Directory(
        p.dirname(store.filePath),
      ).listSync().where((entry) => entry.path.contains('.corrupt-')).toList();
      expect(backups, hasLength(1));
      expect(store.load().name, 'Kai');
    });

    test('leaves a file from a newer build untouched and read-only', () {
      final file = File(store.filePath)..createSync(recursive: true);
      file.writeAsStringSync(jsonEncode({'version': 2, 'name': 'Nova'}));

      expect(store.load().name, CompanionSettings.defaultName);
      expect(store.isReadOnly, isTrue);
      expect(store.save(const CompanionSettings(enabled: true)), isFalse);
      expect(File(store.filePath).readAsStringSync(), contains('"version":2'));
    });
  });

  group('CompanionSettingsNotifier', () {
    ProviderContainer containerFor(CompanionSettingsStore store) {
      final container = ProviderContainer(
        overrides: [
          companionSettingsStoreProvider.overrideWith((ref) async => store),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<CompanionSettingsState> ready(ProviderContainer container) async {
      for (var attempt = 0; attempt < 100; attempt++) {
        final state = container.read(companionSettingsProvider);
        if (state.isReady) return state;
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      fail('the Companion settings never loaded');
    }

    test('loads what is stored and writes a switch straight away', () async {
      store.save(const CompanionSettings(name: 'Nova'));
      final container = containerFor(store);
      final loaded = await ready(container);

      expect(loaded.settings.name, 'Nova');
      expect(loaded.settings.enabled, isFalse);

      final saved = await container
          .read(companionSettingsProvider.notifier)
          .setEnabled(true);
      expect(saved, isTrue);
      expect(
        container.read(companionSettingsProvider).settings.enabled,
        isTrue,
      );
      expect(store.load().enabled, isTrue);
    });

    test('refuses an invalid name and keeps the stored one', () async {
      final container = containerFor(store);
      await ready(container);

      final notifier = container.read(companionSettingsProvider.notifier);
      expect(await notifier.setName('X'), isFalse);
      expect(container.read(companionSettingsProvider).settings.name, 'Ada');
      expect(store.load().name, 'Ada');
    });

    test('clamps a pause that is outside the slider', () async {
      final container = containerFor(store);
      await ready(container);

      await container
          .read(companionSettingsProvider.notifier)
          .setSilenceTimeout(const Duration(milliseconds: 200));

      expect(
        container.read(companionSettingsProvider).settings.silenceTimeout,
        const Duration(milliseconds: 800),
      );
      expect(store.load().silenceTimeout, const Duration(milliseconds: 800));
    });

    test('a newer schema makes the screen read-only', () async {
      final file = File(store.filePath)..createSync(recursive: true);
      file.writeAsStringSync(jsonEncode({'version': 2, 'name': 'Nova'}));

      final container = containerFor(store);
      final loaded = await ready(container);
      expect(loaded.isReadOnly, isTrue);
      expect(loaded.settings.enabled, isFalse);

      final saved = await container
          .read(companionSettingsProvider.notifier)
          .setEnabled(true);
      expect(saved, isFalse);
      expect(
        container.read(companionSettingsProvider).settings.enabled,
        isFalse,
      );
      expect(File(store.filePath).readAsStringSync(), contains('"version":2'));
    });
  });
}
