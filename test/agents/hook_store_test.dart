import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/agents/data/hook_store.dart';
import 'package:installm/features/agents/domain/agent_hook.dart';

void main() {
  late Directory root;
  late File file;
  late HookStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('hook-store-');
    file = File('${root.path}/agents/hooks.json');
    store = HookStore(file);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('an empty store has no rules', () {
    expect(store.load().hooks, isEmpty);
    expect(store.isReadOnly, isFalse);
  });

  test('a saved rule comes back whole and in order', () {
    final first = AgentHook.create(
      id: 'hook-1',
      name: 'Protect secrets',
      toolPattern: 'vault_write_note',
      resourcePattern: 'secrets/**',
      level: HookLevel.ask,
    );
    expect(store.save(HooksSnapshot(hooks: [first])), isTrue);

    final loaded = HookStore(file).load();

    expect(loaded.hooks.single.id, 'hook-1');
    expect(loaded.hooks.single.name, 'Protect secrets');
    expect(loaded.hooks.single.toolPattern, 'vault_write_note');
    expect(loaded.hooks.single.resourcePattern, 'secrets/**');
    expect(loaded.hooks.single.level, HookLevel.ask);
    expect(loaded.hooks.single.enabled, isTrue);
    expect(loaded.hooks.single.builtIn, isFalse);
    expect(
      jsonDecode(file.readAsStringSync())['version'],
      HookStore.currentVersion,
    );

    final second = first.copyWith(name: 'Protect secrets harder');
    store.save(HooksSnapshot(hooks: [first, second]));
    expect(HookStore(file).load().hooks, hasLength(2));
  });

  test('a rule that cannot be read makes the next save keep the original', () {
    const raw =
        '{"version":1,"hooks":[{"name":"no id here"},'
        '{"id":"hook-2","name":"Keep me","unknown":true}]}';
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(raw);

    final loaded = store.load();
    expect(loaded.hooks.single.id, 'hook-2');

    store.save(HooksSnapshot(hooks: loaded.hooks));

    final preserved = root
        .listSync(recursive: true)
        .whereType<File>()
        .where((entry) => entry.path.contains('.preserved-'))
        .toList();
    expect(preserved.single.readAsStringSync(), raw);
    // The rewritten file keeps the rule the build understood.
    expect(HookStore(file).load().hooks.single.name, 'Keep me');
  });

  test('a rule written by a newer build is never rewritten', () {
    const raw = '{"version":99,"hooks":[{"future":"keep"}]}';
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(raw);

    expect(store.load().hooks, isEmpty);
    expect(store.isReadOnly, isTrue);
    expect(store.save(HooksSnapshot.empty), isFalse);
    expect(file.readAsStringSync(), raw);
  });

  test('a corrupt file is reported as empty and kept before a rewrite', () {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('{not json');

    expect(store.load().hooks, isEmpty);
    expect(store.save(HooksSnapshot.empty), isTrue);
    final preserved = root
        .listSync(recursive: true)
        .whereType<File>()
        .where((entry) => entry.path.contains('.preserved-'))
        .toList();
    expect(preserved.single.readAsStringSync(), '{not json');
  });

  test('the built-in floor is not user data and cannot be stored away', () {
    for (final hook in BuiltInHooks.all) {
      expect(hook.builtIn, isTrue);
      expect(hook.toJson().containsKey('builtIn'), isFalse);
    }
    final smuggled = AgentHook.fromJson({
      'id': 'mine',
      'name': 'Pretend built-in',
      'builtIn': true,
      'createdAt': DateTime(2026).toIso8601String(),
      'updatedAt': DateTime(2026).toIso8601String(),
    });
    expect(smuggled!.builtIn, isFalse);
  });
}
