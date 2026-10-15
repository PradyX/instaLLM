import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/bots/application/bots_controller.dart';
import 'package:installm/features/bots/data/bot_store.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/group_chat/application/group_chat_controller.dart';
import 'package:installm/features/group_chat/presentation/room_chat_view.dart';
import 'package:installm/features/home/presentation/home_page.dart';
import 'package:installm/features/skills/application/skills_controller.dart';
import 'package:installm/features/skills/data/skill_store.dart';
import 'package:installm/features/skills/domain/skill.dart';

import '../memory/memory_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryTestHarness harness;
  late ProviderContainer container;
  setUp(() {
    harness = MemoryTestHarness();
    SkillStore(File('${harness.root.path}/skills/skills.json')).save(
      SkillsSnapshot(
        customSkills: [
          Skill.create(id: 'local', name: 'local-review', workspaceId: 'ws1'),
          Skill.create(
            id: 'other',
            name: 'other-workspace',
            workspaceId: 'ws2',
          ),
          Skill.create(id: 'disabled', name: 'disabled', enabled: false),
          Skill.create(
            id: 'privileged',
            name: 'privileged',
            requiredCapabilities: {'shell.execute'},
          ),
          Skill.create(
            id: 'assigned',
            name: 'assigned',
            assignedBotIds: ['bot'],
          ),
        ],
      ),
    );
    BotStore(File('${harness.root.path}/bots/bots.json')).save(
      BotsSnapshot(
        customBots: [
          Bot.create(
            id: 'bot',
            name: 'Coder',
            skillIds: ['local', 'assigned'],
            toolPermissions: {'filesystem:read'},
          ),
        ],
      ),
    );
    container = harness.container();
  });
  tearDown(() async => harness.close());

  Future<void> pump(WidgetTester tester, Widget page) async {
    await tester.runAsync(() async {
      await harness.home(container);
      await container.read(skillsProvider.notifier).whenReady;
      await container.read(botsProvider.notifier).whenReady;
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: page)),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'Home picker uses active workspace before first send and excludes restricted skills',
    (tester) async {
      await pump(tester, const HomePage());
      expect(find.text('/local-review'), findsOneWidget);
      for (final name in [
        '/other-workspace',
        '/disabled',
        '/privileged',
        '/assigned',
      ]) {
        expect(find.text(name), findsNothing);
      }
      await tester.enterText(find.byType(TextField), '/local');
      await tester.pump();
      await tester.tap(find.text('/local-review'));
      await tester.pump();
      expect(find.text('/local-review'), findsNothing);
      expect(container.read(skillsProvider).skills.length, greaterThan(5));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'room picker offers assigned eligible skills and retains floating bot mentions',
    (tester) async {
      final chat = await tester.runAsync(() async {
        await container.read(botsProvider.notifier).whenReady;
        await waitFor(() => container.read(groupChatsProvider).isReady);
        return container
            .read(groupChatsProvider.notifier)
            .createChat(
              workspaceId: 'ws1',
              name: 'Team',
              memberBotIds: ['bot'],
            );
      });
      await pump(tester, RoomChatView(chatId: chat!.id));
      expect(find.text('/assigned'), findsOneWidget);
      expect(find.text('/local-review'), findsOneWidget);
      expect(find.text('/review'), findsNothing);
      expect(find.text('/privileged'), findsNothing);
      await tester.enterText(find.byType(TextField), '@co');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('@Coder'), findsOneWidget);
      expect(find.text('/assigned'), findsNothing);
      await tester.tap(find.text('@Coder'));
      await tester.pump();
      expect(find.text('@Coder'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
