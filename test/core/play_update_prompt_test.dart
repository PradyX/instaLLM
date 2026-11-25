import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/play_update/update_prompt.dart';
import 'package:installm/core/play_update/update_prompt_store.dart';

/// The prompt must be able to disappear for a week without the store losing
/// what it dismissed, and it must come back when a different build lands.
void main() {
  late Directory temp;
  late File file;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('installm_update_prompt');
    file = File('${temp.path}/play_update/state.json');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('asks the first time there is an update', () {
    final policy = UpdatePromptPolicy(UpdatePromptStore(file));

    expect(policy.shouldPrompt(availableVersionCode: 4), isTrue);
  });

  test('a dismissal quiets the prompt for a week, then asks again', () {
    final policy = UpdatePromptPolicy(UpdatePromptStore(file));
    final now = DateTime(2026, 11, 25, 12);

    // Stamped with the same clock the assertions read, so the window is
    // measured from the dismissal rather than from whatever time the suite
    // happens to run at.
    policy.dismiss(availableVersionCode: 4, now: now);

    expect(policy.shouldPrompt(availableVersionCode: 4, now: now), isFalse);
    expect(
      policy.shouldPrompt(
        availableVersionCode: 4,
        now: now.add(const Duration(days: 6)),
      ),
      isFalse,
    );
    expect(
      policy.shouldPrompt(
        availableVersionCode: 4,
        now: now.add(updatePromptDismissWindow),
      ),
      isTrue,
    );
  });

  test('a different build asks straight away', () {
    final policy = UpdatePromptPolicy(UpdatePromptStore(file));
    policy.dismiss(availableVersionCode: 4);

    expect(
      policy.shouldPrompt(availableVersionCode: 5, now: DateTime(2026, 11, 25)),
      isTrue,
    );
  });

  test('the dismissed state survives a reopen', () {
    UpdatePromptPolicy(
      UpdatePromptStore(file),
    ).dismiss(availableVersionCode: 7);

    final reopened = UpdatePromptStore(file).load();
    expect(reopened.dismissedVersionCode, 7);
    expect(reopened.dismissedAt, isNotNull);
  });

  test(
    'an unreadable file is treated as never asked, not as corrupt state',
    () {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('{ not json');

      final policy = UpdatePromptPolicy(UpdatePromptStore(file));

      expect(policy.shouldPrompt(availableVersionCode: 9), isTrue);
      // Saving over it keeps a copy aside instead of deleting the evidence.
      policy.dismiss(availableVersionCode: 9);
      expect(
        file.parent.listSync().where(
          (entry) => entry.path.contains('.corrupt-'),
        ),
        isNotEmpty,
      );
    },
  );

  test('a file from a newer build is never rewritten', () {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({'version': 99, 'dismissedAt': '2030-01-01T00:00:00.000'}),
    );
    final store = UpdatePromptStore(file);
    final policy = UpdatePromptPolicy(store);

    expect(store.isReadOnly, isTrue);
    // The caller skips the prompt entirely; this pins the guard it relies on.
    policy.dismiss(availableVersionCode: 4);
    expect(jsonDecode(file.readAsStringSync())['version'], 99);
  });
}
