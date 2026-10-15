import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/agents/data/background_run_store.dart';
import 'package:installm/features/agents/domain/background_run.dart';

BackgroundRun _run({
  String id = 'run-1',
  String chatId = 'room-1',
  BackgroundRunStatus status = BackgroundRunStatus.running,
  String notice = '',
  bool notified = false,
  String task = 'Summarize the notes',
}) => BackgroundRun(
  id: id,
  chatId: chatId,
  chatName: 'Docs',
  botId: 'one',
  botName: 'One',
  task: task,
  startedAt: DateTime(2026, 10, 15, 12),
  finishedAt: status.isFinished ? DateTime(2026, 10, 15, 12, 5) : null,
  status: status,
  notice: notice,
  notified: notified,
);

void main() {
  group('the run itself', () {
    test('a started run is running and carries its task and place', () {
      final run = BackgroundRun.create(
        id: 'run-1',
        chatId: 'room-1',
        chatName: 'Docs',
        botId: 'one',
        botName: 'One',
        task: '  Summarize the notes  ',
        now: DateTime(2026, 10, 15, 12),
      );

      expect(run.isRunning, isTrue);
      expect(run.status, BackgroundRunStatus.running);
      expect(run.task, 'Summarize the notes');
      expect(run.title, 'One · Docs');
      expect(run.notified, isFalse);
      expect(run.body, contains('Working on'));
    });

    test('a long task is shortened rather than stored whole', () {
      final run = BackgroundRun.create(
        id: 'run-1',
        chatId: 'room-1',
        chatName: 'Docs',
        botId: 'one',
        botName: 'One',
        task: 'x' * (BackgroundRunLimits.maxTaskCharacters + 100),
      );

      expect(run.task.length, BackgroundRunLimits.maxTaskCharacters);
    });

    test('finishing records the state, the notice and no second notice', () {
      final finished = _run().finished(
        status: BackgroundRunStatus.needsInput,
        notice: 'One is waiting for your answer in Docs.',
        now: DateTime(2026, 10, 15, 12, 5),
      );

      expect(finished.isRunning, isFalse);
      expect(finished.status, BackgroundRunStatus.needsInput);
      expect(finished.body, contains('waiting for your answer'));
      expect(finished.notified, isFalse);
      expect(finished.markedNotified().notified, isTrue);
      expect(finished.finishedAt, DateTime(2026, 10, 15, 12, 5));
    });

    test('a notice is capped and an empty one falls back to the state', () {
      final long = _run().finished(
        status: BackgroundRunStatus.done,
        notice: 'y' * (BackgroundRunLimits.maxNoticeCharacters + 50),
      );
      expect(long.notice.length, BackgroundRunLimits.maxNoticeCharacters);

      final empty = _run(
        task: 'Check the board',
      ).finished(status: BackgroundRunStatus.done, notice: '   ');
      expect(empty.body, contains('Finished: Check the board'));
    });
  });

  group('the run store', () {
    late Directory root;
    late File file;
    late BackgroundRunStore store;

    setUp(() {
      root = Directory.systemTemp.createTempSync('runs-store-');
      file = File('${root.path}/agents/runs.json');
      store = BackgroundRunStore(file);
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('a saved run comes back whole', () {
      final run = _run(status: BackgroundRunStatus.done, notice: 'Done.');
      expect(store.save(BackgroundRunsSnapshot(runs: [run])), isTrue);

      final loaded = BackgroundRunStore(file).load();

      expect(loaded.runs.single.id, 'run-1');
      expect(loaded.runs.single.chatName, 'Docs');
      expect(loaded.runs.single.botName, 'One');
      expect(loaded.runs.single.status, BackgroundRunStatus.done);
      expect(loaded.runs.single.notice, 'Done.');
    });

    test('the newest runs are kept and the oldest given up', () {
      final runs = [
        for (var index = 0; index < BackgroundRunLimits.maxRecords + 4; index++)
          _run(id: 'run-$index', chatId: 'room-$index'),
      ];
      store.save(BackgroundRunsSnapshot(runs: runs.reversed.toList()));

      final loaded = store.load();

      expect(loaded.runs, hasLength(BackgroundRunLimits.maxRecords));
      expect(loaded.runs.first.id, 'run-${runs.length - 1}');
      expect(loaded.runs.any((run) => run.id == 'run-0'), isFalse);
    });

    test('finds the run going in a chat, and the one run going overall', () {
      final snapshot = BackgroundRunsSnapshot(
        runs: [
          _run(
            id: 'done-1',
            chatId: 'room-1',
            status: BackgroundRunStatus.done,
          ),
          _run(id: 'gone-1', chatId: 'room-1'),
          _run(id: 'gone-2', chatId: 'room-2'),
        ],
      );

      expect(snapshot.runningIn('room-1')?.id, 'gone-1');
      expect(snapshot.runningIn('room-3'), isNull);
      expect(snapshot.running?.id, 'gone-1');
      expect(snapshot.byId('done-1')?.status, BackgroundRunStatus.done);
    });

    test('an entry with an unknown state is refused, and kept', () {
      const raw =
          '{"version":1,"runs":[{"id":"run-9","chatId":"room-1",'
          '"task":"x","startedAt":"2026-10-15T12:00:00.000",'
          '"status":"teleported"}]}';
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(raw);

      expect(store.load().runs, isEmpty);

      store.save(BackgroundRunsSnapshot.empty);

      final preserved = root
          .listSync(recursive: true)
          .whereType<File>()
          .where((entry) => entry.path.contains('.preserved-'))
          .toList();
      expect(preserved.single.readAsStringSync(), raw);
      expect(
        jsonDecode(file.readAsStringSync())['version'],
        BackgroundRunStore.currentVersion,
      );
    });

    test('a newer schema is never rewritten', () {
      const raw = '{"version":99,"runs":[{"future":"keep"}]}';
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(raw);

      expect(store.load().runs, isEmpty);
      expect(store.isReadOnly, isTrue);
      expect(store.save(BackgroundRunsSnapshot.empty), isFalse);
      expect(file.readAsStringSync(), raw);
    });

    test('corrupt content is reported as empty and kept before a rewrite', () {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('{oops');

      expect(store.load().runs, isEmpty);
      expect(store.save(BackgroundRunsSnapshot.empty), isTrue);
      final preserved = root
          .listSync(recursive: true)
          .whereType<File>()
          .where((entry) => entry.path.contains('.preserved-'))
          .toList();
      expect(preserved.single.readAsStringSync(), '{oops');
    });
  });
}
