import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/theme/theme.dart';
import 'package:installm/features/bots/application/bots_controller.dart';
import 'package:installm/features/bots/data/bot_store.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/group_chat/application/group_chat_controller.dart';
import 'package:installm/features/group_chat/data/group_chat_store.dart';
import 'package:installm/features/group_chat/domain/group_chat.dart';
import 'package:installm/features/group_chat/presentation/room_chat_view.dart';
import 'package:installm/features/profile_images/application/profile_images_controller.dart';
import 'package:installm/features/profile_images/presentation/profile_image_picker.dart';

void main() {
  for (final dark in [false, true]) {
    for (final narrow in [false, true]) {
      testWidgets(
        'compact settings ${dark ? "dark" : "light"} ${narrow ? "320px at 2x" : "wide"} stays usable',
        (tester) async {
          final directory = (await tester.runAsync(
            () => Directory.systemTemp.createTemp('compact_settings'),
          ))!;
          final bots = BotStore(File('${directory.path}/bots.json'));
          final bot = Bot.create(
            id: 'bot',
            name: narrow
                ? 'A long bot name that must wrap without losing any text'
                : 'Orchestrator',
          );
          bots.save(BotsSnapshot(customBots: [bot]));
          final rooms = GroupChatStore(File('${directory.path}/rooms.json'));
          rooms.save(
            GroupChatsSnapshot(
              chats: [
                GroupChat.create(
                  id: 'room',
                  workspaceId: 'ws',
                  name: bot.name,
                  directBotId: bot.id,
                  memberBotIds: [bot.id],
                ),
              ],
            ),
          );
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('plugins.flutter.io/path_provider'),
                (_) async => directory.path,
              );
          final container = ProviderContainer(
            overrides: [
              botStoreProvider.overrideWith((_) async => bots),
              groupChatStoreProvider.overrideWith((_) async => rooms),
              petdexCatalogProvider.overrideWith((_) async => []),
            ],
          );
          addTearDown(() async {
            container.dispose();
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(
                  const MethodChannel('plugins.flutter.io/path_provider'),
                  null,
                );
            await directory.delete(recursive: true);
          });
          await tester.runAsync(() async {
            await container.read(botsProvider.notifier).whenReady;
            container.read(groupChatsProvider);
            for (
              var i = 0;
              i < 100 && !container.read(groupChatsProvider).isReady;
              i++
            ) {
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
          });
          tester.view.physicalSize = Size(narrow ? 320 : 728, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final theme = MaterialTheme(ThemeData().textTheme);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: dark ? theme.dark() : theme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => Center(
                      child: TextButton(
                        onPressed: () => showRoomSettings(context, 'room'),
                        child: const Text('Open'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text(bot.name), findsOneWidget);
          expect(find.byType(OutlinedButton), findsNothing);
          await tester.ensureVisible(find.text('Delete bot'));
          await tester.tap(find.text('Delete bot'));
          await tester.pumpAndSettle();
          expect(find.text('Delete this bot?'), findsOneWidget);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Change image'));
          await tester.tap(find.text('Change image'));
          await tester.pumpAndSettle();
          expect(find.byType(ProfileImagePicker), findsOneWidget);
          await tester.tap(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text('Close'),
            ),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byTooltip('Close'));
          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();
          expect(find.byType(RoomSettingsSheet), findsNothing);
          expect(bots.load().allBots.single.name, bot.name);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
