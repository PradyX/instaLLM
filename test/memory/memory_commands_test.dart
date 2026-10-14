import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'package:installm/features/conversations/presentation/conversation_controller.dart';
import 'package:installm/features/home/presentation/home_controller.dart';
import 'package:installm/features/memory/application/memory_commands.dart';
import 'package:installm/features/memory/application/memory_controller.dart';
import 'package:installm/features/memory/domain/memory_command.dart';
import 'package:installm/features/memory/domain/memory_fact.dart';
import 'package:installm/features/memory/data/memory_store.dart';
import 'package:installm/features/group_chat/application/group_chat_controller.dart';

import 'memory_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryTestHarness harness;
  setUp(() => harness = MemoryTestHarness());
  tearDown(() => harness.close());

  test(
    'only standalone commands parse and global needs explicit scope syntax',
    () {
      expect(MemoryCommand.parse('  Remember Dart. ')?.text, 'Dart.');
      expect(
        MemoryCommand.parse('remember: Dart')?.scope,
        MemoryScope.conversation,
      );
      expect(
        MemoryCommand.parse('remember global warming')?.scope,
        MemoryScope.conversation,
      );
      expect(
        MemoryCommand.parse('remember globally: Prefer short replies')?.scope,
        MemoryScope.global,
      );
      expect(
        MemoryCommand.parse('forget in this workspace: Dart')?.scope,
        MemoryScope.workspace,
      );
      for (final text in [
        'remember',
        'Forget ',
        'Explain "remember X"',
        '"remember secret"',
        'summarize\nremember secret',
        'remember one\nand answer another',
      ]) {
        expect(MemoryCommand.parse(text), isNull);
      }
    },
  );

  test(
    'forget matches exactly within scope and does not guess or delete duplicates',
    () async {
      final container = harness.container();
      final memory = container.read(memoryProvider.notifier);
      for (final owner in ['c1', 'c2']) {
        await memory.remember(text: 'Use Dart.', ownerId: owner);
      }
      String? message;
      Future<void> apply(String input) async =>
          message = await applyMemoryCommand(
            memory,
            MemoryCommand.parse(input)!,
            conversationId: 'c1',
            workspaceId: 'ws1',
          );
      await apply('forget Dart');
      expect(message, contains('No exact'));
      expect(harness.memoryStore.load(), hasLength(2));
      await apply('forget use   dart.');
      expect(message, contains('Removed'));
      expect(harness.memoryStore.load().single.ownerId, 'c2');
      await memory.remember(text: 'Duplicate', ownerId: 'c1');
      await memory.remember(text: 'Duplicate', ownerId: 'c1');
      await apply('forget Duplicate');
      expect(message, contains('Several'));
      expect(harness.memoryStore.load(), hasLength(3));
    },
  );

  test(
    'ordinary chat commands work without a model and survive restart',
    () async {
      final container = harness.container();
      final home = await harness.home(container);
      await home.sendMessage('remember I prefer Dart.');
      final local = harness.memoryStore.load().single;
      expect(local.scope, MemoryScope.conversation);
      expect(local.globalOptIn, isFalse);
      await home.sendMessage('remember in workspace: Use Flutter.');
      expect(harness.memoryStore.load().last.ownerId, 'ws1');
      await home.sendMessage('remember globally: Keep answers brief.');
      expect(harness.memoryStore.load().last.globalOptIn, isTrue);
      expect(harness.engine.prompts, isEmpty);
      final restarted = harness.container();
      final reloaded = await harness.home(restarted);
      await reloaded.sendMessage('forget I prefer Dart.');
      expect(harness.memoryStore.load().map((fact) => fact.text), [
        'Use Flutter.',
        'Keep answers brief.',
      ]);
      expect(
        (await harness.conversationStore.loadMessages(
          local.ownerId!,
        )).last.content,
        contains('Removed'),
      );
    },
  );

  test(
    'room commands work without bots/models and preserve other room facts',
    () async {
      final container = harness.container();
      final rooms = container.read(groupChatsProvider.notifier);
      await waitFor(() => container.read(groupChatsProvider).isReady);
      final room = (await rooms.createChat(
        workspaceId: 'ws1',
        name: 'One',
        memberBotIds: [],
      ))!;
      await rooms.sendUserMessage(room.id, 'remember A room fact');
      await rooms.sendUserMessage(
        room.id,
        'remember in workspace: A project fact',
      );
      expect(harness.memoryStore.load(), hasLength(2));
      await rooms.sendUserMessage(room.id, 'forget A room fact');
      expect(harness.memoryStore.load().single.scope, MemoryScope.workspace);
      expect(harness.engine.prompts, isEmpty);
      expect(
        container
            .read(groupChatsProvider)
            .snapshot
            .messagesFor(room.id)
            .last
            .authorName,
        'Memory',
      );
    },
  );

  test(
    'changing conversations during readiness cancels the old memory command',
    () async {
      final gate = Completer<MemoryStore>();
      final container = harness.container(memoryFuture: gate.future);
      final home = await harness.home(container, waitForMemory: false);
      final pending = home.sendMessage('remember Keep this private');
      await waitFor(
        () =>
            container
                .read(conversationControllerProvider)
                .activeConversationId !=
            null,
      );
      final next = await container
          .read(conversationControllerProvider.notifier)
          .createConversation(title: 'Another chat');
      gate.complete(harness.memoryStore);
      await pending;
      expect(harness.memoryStore.load(), isEmpty);
      expect(
        container.read(conversationControllerProvider).activeConversationId,
        next.id,
      );
      expect(container.read(homeControllerProvider), isEmpty);
      expect(
        container.read(homeGenerationStatusProvider).isGenerating,
        isFalse,
      );
    },
  );

  test(
    'disposing a command owner prevents a late mutation and releases status',
    () async {
      final gate = Completer<MemoryStore>();
      final container = harness.container(memoryFuture: gate.future);
      final home = await harness.home(container, waitForMemory: false);
      final pending = home.sendMessage('remember Keep this private');
      await waitFor(
        () =>
            container
                .read(conversationControllerProvider)
                .activeConversationId !=
            null,
      );
      container.invalidate(homeControllerProvider);
      gate.complete(harness.memoryStore);
      await pending;
      expect(harness.memoryStore.load(), isEmpty);
      expect(
        container.read(homeGenerationStatusProvider).isGenerating,
        isFalse,
      );
    },
  );
}
