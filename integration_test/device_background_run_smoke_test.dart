import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:installm/features/agents/application/background_runs_controller.dart';
import 'package:installm/features/bots/application/bots_controller.dart';
import 'package:installm/features/bots/domain/built_in_bots.dart';
import 'package:installm/features/group_chat/application/group_chat_controller.dart';

/// Exercises the real background-run wiring on this machine: the app's own
/// `agents/runs.json`, the provider graph a room turn runs through, and a real
/// notice through the platform notification plugin.
///
/// Unit tests cover the supervisor against a scripted runtime and temp files;
/// what they cannot cover is whether a run started through the app's real
/// controller ends, is recorded where the app looks for it, and reaches the
/// notification plugin of this platform. The test prints what it found and puts
/// the user's run list and rooms file back exactly as they were.
///
/// On a machine with no model installed the run ends as “needs you” (the room
/// asks for the reply to be pasted in, which is the case the notice exists
/// for). With a model installed it answers instead; either ending is a pass —
/// what is asserted is that the run ends, is stored once and is reported.
///
/// Run on a desktop or device:
///
/// ```bash
/// flutter test integration_test/device_background_run_smoke_test.dart -d linux
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a real supervised run ends, is recorded and is reported', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(const SizedBox.shrink());

    // The user's own files, restored afterwards.
    final runStore = await container.read(backgroundRunStoreProvider.future);
    final roomStore = await container.read(groupChatStoreProvider.future);
    final botStore = await container.read(botStoreProvider.future);
    final backups = <String, String?>{
      runStore.filePath: _read(runStore.filePath),
      roomStore.filePath: _read(roomStore.filePath),
      botStore.filePath: _read(botStore.filePath),
    };
    for (final entry in backups.entries) {
      // ignore: avoid_print
      print('under test: ${entry.key} (existed: ${entry.value != null})');
    }
    addTearDown(() {
      for (final entry in backups.entries) {
        final file = File(entry.key);
        final original = entry.value;
        if (original == null) {
          if (file.existsSync()) file.deleteSync();
          continue;
        }
        file.writeAsStringSync(original);
      }
    });

    final botBackend = container.read(botsProvider.notifier);
    await botBackend.whenReady;
    final bots = container.read(botsProvider);
    // A machine that has never made a bot still has to be able to run one, so
    // the smoke test makes the bot it needs and the file is put back after.
    final bot = bots.bots.isEmpty
        ? await botBackend.createBot(
            'Smoke runner',
            templateId: BuiltInBots.researcherId,
          )
        : bots.bots.first;
    expect(bot, isNotNull, reason: 'a bot is available to run the task');
    // ignore: avoid_print
    print('bot used: ${bot!.name} (${bot.id})');

    final rooms = container.read(groupChatsProvider.notifier);
    // The room list is opened once per session; writing into it before its own
    // first read has landed would be overwritten by that read.
    await _until(() => container.read(groupChatsProvider).isReady);
    final room = await rooms.createChat(
      workspaceId: 'smoke',
      name: 'Smoke background run',
      memberBotIds: [bot.id],
    );
    expect(room, isNotNull, reason: 'the room was created');
    // ignore: avoid_print
    print('room under test: ${room!.id} (${room.name})');
    final roomId = room.id;

    await rooms.sendUserMessage(roomId, '/background check the smoke run');
    final runs = container.read(backgroundRunsProvider.notifier);
    await runs.whenReady;
    // Poll until the room's run appears and has ended, so an ending that
    // happens between two polls is still seen in the record it left behind.
    await _until(
      () {
        final mine = container
            .read(backgroundRunsProvider)
            .runs
            .where((candidate) => candidate.chatId == roomId);
        return mine.isNotEmpty &&
            mine.every((candidate) => !candidate.isRunning);
      },
      onTick: () {
        final mine = container.read(backgroundRunsProvider).runs;
        final messages = container
            .read(groupChatsProvider)
            .snapshot
            .messagesFor(roomId);
        // ignore: avoid_print
        print(
          'waiting: runs=${mine.map((run) => run.status.name).toList()} '
          'messages=${messages.length} '
          'last="${messages.isEmpty ? '' : messages.last.text.split('\n').first}"',
        );
      },
    );

    final run = container
        .read(backgroundRunsProvider)
        .runs
        .where((candidate) => candidate.chatId == roomId);
    expect(run, hasLength(1));
    final finished = run.single;
    // ignore: avoid_print
    print(
      'run ${finished.id}: ${finished.status.label} · notified: '
      '${finished.notified} · notice: ${finished.body}',
    );
    expect(finished.isRunning, isFalse, reason: 'the run reached an ending');
    expect(
      finished.notified,
      isTrue,
      reason: 'the platform notification plugin accepted the notice',
    );

    // What the app reads back on the next launch comes from the real file.
    final stored = runStore.load().byId(finished.id);
    expect(stored, isNotNull, reason: 'the run is in agents/runs.json');
    expect(stored!.status, finished.status);
    expect(stored.notified, isTrue);

    await rooms.sendUserMessage(roomId, '/background list');
    final said = container
        .read(groupChatsProvider)
        .snapshot
        .messagesFor(roomId)
        .last
        .text;
    // ignore: avoid_print
    print(said.split('\n').first);
    expect(said, contains('Runs started here'));
    expect(said, contains(finished.id));

    // A run that has ended cannot be stopped, and saying so is honest.
    final stoppedAgain = await runs.stop(finished.id);
    expect(stoppedAgain, isFalse);
    // ignore: avoid_print
    print('stopping the finished run again: $stoppedAgain');
  });
}

String? _read(String path) {
  final file = File(path);
  return file.existsSync() ? file.readAsStringSync() : null;
}

/// Waits until [condition] holds, so a real room turn can be observed.
Future<void> _until(
  bool Function() condition, {
  void Function()? onTick,
}) async {
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  var tick = 0;
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('the run never ended');
    }
    if (onTick != null && tick++ % 50 == 0) onTick();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
