import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/companion/application/companion_settings_controller.dart';
import 'package:installm/features/companion/data/companion_settings_store.dart';
import 'package:installm/features/companion/domain/companion_settings.dart';
import 'package:installm/features/companion/presentation/companion_settings_page.dart';
import 'package:path/path.dart' as p;

late Directory _tempDir;
late CompanionSettingsStore _store;

Future<void> _pumpPage(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        companionSettingsStoreProvider.overrideWith((ref) async => _store),
      ],
      child: const MaterialApp(home: CompanionSettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    _tempDir = await Directory.systemTemp.createTemp('companion-settings-ui-');
    _store = CompanionSettingsStore(
      File(p.join(_tempDir.path, 'companion', 'settings.json')),
    );
  });

  tearDown(() async {
    if (_tempDir.existsSync()) await _tempDir.delete(recursive: true);
  });

  testWidgets('shows the stored name and keeps the typed one in the field', (
    tester,
  ) async {
    await _pumpPage(tester);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'Ada');

    await tester.enterText(find.byType(TextField), 'Kai');
    await tester.pump();

    expect(find.text('Kai'), findsOneWidget);
  });

  testWidgets('saves a valid name and refuses a one-letter one', (
    tester,
  ) async {
    await _pumpPage(tester);

    await tester.enterText(find.byType(TextField), 'K');
    await tester.pump();

    expect(find.text('Use at least 2 characters.'), findsOneWidget);
    final blocked = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Save name'),
    );
    expect(blocked.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Kai');
    await tester.pump();
    await tester.tap(find.text('Save name'));
    await tester.pumpAndSettle();

    expect(_store.load().name, 'Kai');
    final saved = tester.widget<TextField>(find.byType(TextField));
    expect(saved.controller?.text, 'Kai');
  });

  testWidgets('the switch is off by default and turns the Companion on', (
    tester,
  ) async {
    await _pumpPage(tester);

    final before = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(before.value, isFalse);
    expect(_store.load().enabled, isFalse);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(_store.load().enabled, isTrue);
    final after = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(after.value, isTrue);
  });

  testWidgets('shows the stored pause and no wake control', (tester) async {
    _store.save(
      const CompanionSettings(
        wakeSensitivity: 0.8,
        silenceTimeout: Duration(milliseconds: 2200),
      ),
    );
    await _pumpPage(tester);

    expect(find.text('2.2 s'), findsOneWidget);
    // The wake word was descoped, so its sensitivity must not be offered.
    expect(find.text('80%'), findsNothing);
    expect(find.text('Wake sensitivity'), findsNothing);
    expect(find.byType(Slider), findsOneWidget);
  });
}
