import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/conversations/domain/context_policy.dart';
import 'package:installm/features/memory/application/memory_controller.dart';
import 'package:installm/features/memory/data/memory_store.dart';
import 'package:installm/features/memory/domain/memory_fact.dart';

class FailingStore extends MemoryStore {
  FailingStore(super.file);
  bool fail = false;
  @override
  bool save(List<MemoryFact> facts) => !fail && super.save(facts);
}

void main() {
  late Directory root;
  late FailingStore store;
  late ProviderContainer container;
  late MemoryNotifier memory;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('installm_memory_controller_');
    store = FailingStore(File('${root.path}/facts.json'));
    container = ProviderContainer(
      overrides: [memoryStoreProvider.overrideWith((ref) async => store)],
    );
    memory = container.read(memoryProvider.notifier);
    await memory.whenReady;
  });
  tearDown(() {
    container.dispose();
    root.deleteSync(recursive: true);
  });

  String prompt(BotMemoryScope scope, {int maxTokens = 256}) =>
      memory.promptFacts(
        scope: scope,
        conversationId: 'c1',
        workspaceId: 'ws1',
        maxTokens: maxTokens,
      );

  test('remember defaults to conversation and requires an owner', () async {
    expect(await memory.remember(text: 'No owner'), isNull);
    expect(store.file.existsSync(), isFalse);
    final saved = await memory.remember(
      text: ' Keep it local. ',
      ownerId: 'c1',
    );
    expect(saved?.scope, MemoryScope.conversation);
    expect(saved?.text, 'Keep it local.');
    expect(saved?.source, MemorySource.userStated);
    expect(saved?.globalOptIn, isFalse);
    expect(MemoryStore(store.file).load().single.id, saved?.id);
  });

  test('global requires explicit per-fact opt-in every time', () async {
    expect(
      await memory.remember(text: 'Private', scope: MemoryScope.global),
      isNull,
    );
    final saved = await memory.remember(
      text: 'Shared preference',
      scope: MemoryScope.global,
      globalOptIn: true,
    );
    expect(saved?.globalOptIn, isTrue);
    expect(
      await memory.remember(
        text: 'Another private fact',
        scope: MemoryScope.global,
      ),
      isNull,
    );
    expect(container.read(memoryProvider).facts, hasLength(1));
    expect(prompt(BotMemoryScope.workspace), isEmpty);
    expect(prompt(BotMemoryScope.global), contains('Shared preference'));
  });

  test(
    'scope ceiling excludes other chats/workspaces and none recalls nothing',
    () async {
      for (final owner in ['c1', 'c2']) {
        await memory.remember(text: 'conversation $owner', ownerId: owner);
      }
      for (final owner in ['ws1', 'ws2']) {
        await memory.remember(
          text: 'workspace $owner',
          ownerId: owner,
          scope: MemoryScope.workspace,
        );
      }
      await memory.remember(
        text: 'global fact',
        scope: MemoryScope.global,
        globalOptIn: true,
      );
      expect(prompt(BotMemoryScope.none), isEmpty);
      expect(prompt(BotMemoryScope.conversation), contains('conversation c1'));
      expect(prompt(BotMemoryScope.conversation), isNot(contains('workspace')));
      expect(prompt(BotMemoryScope.workspace), contains('workspace ws1'));
      expect(prompt(BotMemoryScope.workspace), isNot(contains('global fact')));
      final global = prompt(BotMemoryScope.global);
      expect(global, contains('conversation c1'));
      expect(global, contains('workspace ws1'));
      expect(global, contains('global fact'));
      expect(global, isNot(contains('conversation c2')));
      expect(global, isNot(contains('workspace ws2')));
    },
  );

  test(
    'inferred facts are labelled, editable and removable across restart',
    () async {
      final saved = (await memory.remember(
        text: 'Probably likes Dart',
        ownerId: 'c1',
        source: MemorySource.inferred,
      ))!;
      expect(prompt(BotMemoryScope.conversation), contains('; inferred]'));
      expect(
        await memory.edit(saved.id, text: 'Actually prefers Rust'),
        isTrue,
      );
      final restored = MemoryStore(store.file).load().single;
      expect(restored.text, 'Actually prefers Rust');
      expect(restored.source, MemorySource.inferred);
      expect(restored.createdAt, saved.createdAt);
      expect(restored.ownerId, saved.ownerId);
      expect(await memory.forget(saved.id), isTrue);
      expect(MemoryStore(store.file).load(), isEmpty);
      expect(await memory.forget(saved.id), isFalse);
    },
  );

  test(
    'expiry removes recall, retains data, and can explicitly be cleared',
    () async {
      final expired = DateTime.now().subtract(const Duration(days: 1));
      final saved = (await memory.remember(
        text: 'Old fact',
        ownerId: 'c1',
        expiresAt: expired,
      ))!;
      expect(prompt(BotMemoryScope.conversation), isEmpty);
      expect(MemoryStore(store.file).load(), hasLength(1));
      expect(await memory.edit(saved.id, text: 'Still old'), isTrue);
      expect(container.read(memoryProvider).facts.single.expiresAt, expired);
      expect(
        await memory.edit(saved.id, text: 'Current fact', clearExpiry: true),
        isTrue,
      );
      expect(prompt(BotMemoryScope.conversation), contains('Current fact'));
    },
  );

  test(
    'failed remember/edit/forget retain state and previous disk contents',
    () async {
      final saved = (await memory.remember(text: 'Keep', ownerId: 'c1'))!;
      final original = store.file.readAsStringSync();
      store.fail = true;
      expect(await memory.remember(text: 'Failed', ownerId: 'c1'), isNull);
      expect(await memory.edit(saved.id, text: 'Failed'), isFalse);
      expect(await memory.forget(saved.id), isFalse);
      expect(container.read(memoryProvider).facts.single.text, 'Keep');
      expect(store.file.readAsStringSync(), original);
      expect(
        container.read(memoryProvider).errorMessage,
        contains('Check free space'),
      );
      store.fail = false;
      expect(await memory.edit(saved.id, text: 'Saved'), isTrue);
      expect(container.read(memoryProvider).errorMessage, isNull);
    },
  );

  test(
    'concurrent remembers serialize after readiness without losing facts',
    () async {
      await Future.wait([
        for (var i = 0; i < 10; i++)
          memory.remember(text: 'Fact $i', ownerId: 'c1'),
      ]);
      expect(container.read(memoryProvider).facts, hasLength(10));
      expect(MemoryStore(store.file).load(), hasLength(10));
    },
  );

  test(
    'token cap includes labels/separators and skips whole oversized facts',
    () async {
      await memory.remember(text: 'Short fact', ownerId: 'c1');
      await memory.remember(text: 'x' * 900, ownerId: 'c1');
      final result = prompt(BotMemoryScope.conversation, maxTokens: 30);
      expect(result, contains('Short fact'));
      expect(result, isNot(contains('xxx')));
      expect(TokenEstimator.estimateText(result), lessThanOrEqualTo(30));
      expect(prompt(BotMemoryScope.conversation, maxTokens: 0), isEmpty);
      expect(await memory.remember(text: 'x' * 1001, ownerId: 'c1'), isNull);
    },
  );

  test(
    'loading unavailable storage leaves recall empty and writes actionable',
    () async {
      final unavailable = ProviderContainer(
        overrides: [
          memoryStoreProvider.overrideWith(
            (ref) async => throw const FileSystemException('unavailable'),
          ),
        ],
      );
      addTearDown(unavailable.dispose);
      final notifier = unavailable.read(memoryProvider.notifier);
      await notifier.whenReady;
      expect(unavailable.read(memoryProvider).isReady, isTrue);
      expect(unavailable.read(memoryProvider).facts, isEmpty);
      expect(
        unavailable.read(memoryProvider).errorMessage,
        contains('Local chat remains available'),
      );
      expect(
        await notifier.remember(text: 'Cannot save', ownerId: 'c1'),
        isNull,
      );
    },
  );
}
