import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:installm/features/agents/application/run_checkpoint_session.dart';
import 'package:installm/features/agents/domain/review_finding.dart';
import 'package:installm/features/bots/application/bots_controller.dart';
import 'package:installm/features/bots/domain/built_in_bots.dart';
import 'package:installm/features/group_chat/application/group_chat_controller.dart';
import 'package:installm/features/group_chat/domain/group_chat.dart';
import 'package:installm/features/model_selection/presentation/chat_models_provider.dart';
import 'package:installm/features/vault/application/vaults_controller.dart';

/// Exercises `/review` on this machine: the app's own vault registry, room
/// store, checkpoint store and model list, and a real folder on disk that the
/// review reads.
///
/// Unit tests cover the reviewer against a scripted runtime and temp files.
/// What they cannot cover is whether the real app resolves the folder it must
/// read, records the run it reviews in the file `/rewind` reads back, and
/// answers honestly when this machine has no model to review with. The test
/// puts the user's rooms, vault registry and bot list back exactly as they
/// were, and the folder it works in is its own temp directory.
///
/// Run on a desktop or device:
///
/// ```bash
/// flutter test integration_test/device_review_smoke_test.dart -d linux
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a real room reviews a real file and refuses what it cannot', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(const SizedBox.shrink());

    final roomStore = await container.read(groupChatStoreProvider.future);
    final vaultStore = await container.read(vaultStoreProvider.future);
    final botStore = await container.read(botStoreProvider.future);
    final backups = <String, String?>{
      roomStore.filePath: _read(roomStore.filePath),
      vaultStore.filePath: _read(vaultStore.filePath),
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

    final root = Directory.systemTemp.createTempSync('instalm-review-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    final botBackend = container.read(botsProvider.notifier);
    await botBackend.whenReady;
    final bot = container.read(botsProvider).bots.isEmpty
        ? await botBackend.createBot(
            'Smoke reviewer',
            templateId: BuiltInBots.researcherId,
          )
        : container.read(botsProvider).bots.first;
    expect(bot, isNotNull, reason: 'a bot is available to review with');
    // ignore: avoid_print
    print('bot used: ${bot!.name} (${bot.id})');

    // A folder of this test's own, linked the way the app links one.
    final vaults = container.read(vaultsProvider.notifier);
    await vaults.whenReady;
    final vault = await vaults.registerVault('Smoke review', root.path);
    expect(vault, isNotNull, reason: 'the temp folder was registered');
    final linked = await vaults.linkWorkspace(
      workspaceId: 'smoke-review',
      vaultId: vault!.id,
      projectPath: 'Project',
    );
    // ignore: avoid_print
    print('linked ${root.path}/Project (created: $linked)');

    final rooms = container.read(groupChatsProvider.notifier);
    await _until(() => container.read(groupChatsProvider).isReady);
    final room = await rooms.createChat(
      workspaceId: 'smoke-review',
      name: 'Smoke review',
      memberBotIds: [bot.id],
    );
    expect(room, isNotNull, reason: 'the room was created');
    final roomId = room!.id;
    // ignore: avoid_print
    print('room under test: $roomId (${room.name})');

    // Nothing has been written by this room yet, so there is nothing recorded
    // to review — and that is what the room says.
    await rooms.sendUserMessage(roomId, '/review');
    // ignore: avoid_print
    print('bare /review: ${_last(container, roomId)}');
    expect(_last(container, roomId), contains('nothing recorded to review'));

    // A file the user names is read from the linked folder and reviewed.
    final plan = File('${root.path}/Project/notes/plan.md')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('Step one.\nStep two.\n');
    expect(plan.existsSync(), isTrue);
    // A review answers in the room rather than echoing the command, so what
    // says it finished is the answer replacing the one before it.
    final before = _last(container, roomId);
    await rooms.sendUserMessage(roomId, '/review notes/plan.md');
    await _until(
      () => _last(container, roomId) != before,
      // ignore: avoid_print
      onTick: () => print(
        'waiting: messages=${_messages(container, roomId).length} '
        'running=${container.read(groupChatsProvider).runningChatIds.contains(roomId)} '
        'last="${_last(container, roomId).split('\n').first.take(70)}"',
      ),
    );
    final reviewed = _last(container, roomId);
    // ignore: avoid_print
    print('named review:\n$reviewed');
    final installed = container.read(chatModelsProvider);
    // ignore: avoid_print
    print('installed models: ${installed.map((model) => model.id).toList()}');
    if (installed.isEmpty) {
      expect(
        reviewed,
        contains('No model is installed'),
        reason: 'with nothing to review with, the room says so',
      );
      expect(
        reviewed,
        isNot(contains('No findings')),
        reason: 'nothing looked at the changes, so nothing may be claimed',
      );
    } else {
      expect(
        reviewed,
        contains('notes/plan.md'),
        reason: 'the listing names what was reviewed',
      );
      expect(
        reviewed.startsWith('Review of 1 named file(s)'),
        isTrue,
        reason: 'the review ran through the room’s real turn',
      );
      // `/review fix` reads that listing back, so it round-trips on the real
      // path too.
      final findings = ReviewFindings.parse(reviewed);
      if (findings.isEmpty) {
        await rooms.sendUserMessage(roomId, '/review fix 1');
        // ignore: avoid_print
        print('fix with no findings: ${_last(container, roomId)}');
        expect(_last(container, roomId), contains('found nothing to fix'));
      }
    }

    // A named file that is not there is reported rather than reviewed.
    await rooms.sendUserMessage(roomId, '/review notes/gone.md');
    // ignore: avoid_print
    print('missing file: ${_last(container, roomId).split('\n').first}');
    expect(_last(container, roomId), contains('notes/gone.md'));
    expect(_last(container, roomId), contains('Nothing could be read'));

    // A half-written hand-off is refused with the usage, not guessed at.
    await rooms.sendUserMessage(roomId, '/review fix');
    // ignore: avoid_print
    print('bare fix: ${_last(container, roomId)}');
    expect(_last(container, roomId), contains('Which finding'));

    // The run this room recorded is the one `/rewind` and `/review` both read:
    // a review of named files writes nothing, so this stays empty.
    final checkpoints = await container.read(runCheckpointStoreProvider.future);
    final runs = checkpoints.load().forContext('room:$roomId');
    // ignore: avoid_print
    print('runs recorded for this room: ${runs.length}');
    expect(runs, isEmpty, reason: 'reading files for a review is not a write');
  });
}

String _last(ProviderContainer container, String roomId) {
  final messages = _messages(container, roomId);
  return messages.isEmpty ? '' : messages.last.text;
}

List<GroupMessage> _messages(ProviderContainer container, String roomId) =>
    container.read(groupChatsProvider).snapshot.messagesFor(roomId);

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
      throw StateError('the room never answered');
    }
    if (onTick != null && tick++ % 30 == 0) onTick();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// The first [limit] characters of [text], for one-line progress prints.
extension on String {
  String take(int limit) => length <= limit ? this : '${substring(0, limit)}…';
}
