import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/agents/application/run_checkpoint_session.dart';
import 'package:installm/features/agents/data/run_checkpoint_store.dart';
import 'package:installm/features/agents/domain/run_checkpoint.dart';

RunCheckpointEntry _entry({
  String relativePath = 'notes/ok.md',
  String? before,
  required String after,
  String? blocked,
}) {
  final path = '/vault/Project/$relativePath';
  return RunCheckpointEntry(
    relativePath: relativePath,
    path: path,
    beforeExists: before != null,
    beforeContent: before,
    beforeHash: runCheckpointHash(before ?? ''),
    afterHash: runCheckpointHash(after),
    writtenAt: DateTime(2026, 10, 15, 12),
    blocked: blocked,
  );
}

RunCheckpoint _run(List<RunCheckpointEntry> entries, {String id = 'run-1'}) =>
    RunCheckpoint(
      id: id,
      contextKey: 'room:r1',
      label: 'One',
      startedAt: DateTime(2026, 10, 15, 12),
      entries: entries,
    );

void main() {
  group('snapshot store', () {
    late Directory root;
    late File file;
    late RunCheckpointStore store;

    setUp(() {
      root = Directory.systemTemp.createTempSync('run-checkpoints-');
      file = File('${root.path}/agents/checkpoints.json');
      store = RunCheckpointStore(file);
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('a saved run comes back with its files and snapshots', () {
      final run = _run([
        _entry(before: 'before text\n', after: 'after text\n'),
        _entry(relativePath: 'notes/new.md', after: 'created\n'),
      ]);
      expect(store.save(RunCheckpointsSnapshot(runs: [run])), isTrue);

      final loaded = RunCheckpointStore(file).load();

      expect(loaded.runs.single.id, 'run-1');
      expect(loaded.runs.single.label, 'One');
      expect(loaded.runs.single.contextKey, 'room:r1');
      expect(loaded.runs.single.entries, hasLength(2));
      expect(loaded.runs.single.entries.first.beforeContent, 'before text\n');
      expect(loaded.runs.single.entries.first.isRestorable, isTrue);
      expect(loaded.runs.single.entries.last.removesFile, isTrue);
      expect(loaded.runs.single.isRestorable, isTrue);
    });

    test('a newer schema turns the store read-only and is kept', () {
      const raw = '{"version":99,"runs":[{"future":"keep"}]}';
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(raw);

      expect(store.load().runs, isEmpty);
      expect(store.isReadOnly, isTrue);
      expect(store.save(RunCheckpointsSnapshot.empty), isFalse);
      expect(file.readAsStringSync(), raw);
    });

    test('a run that cannot be read makes the next save keep the original', () {
      const raw =
          '{"version":1,"runs":[{"id":"run-9","contextKey":"room:r1",'
          '"label":"One","startedAt":"2026-10-15T12:00:00.000",'
          '"entries":[{"relativePath":"a.md","path":"/v/a.md"}]}]}';
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(raw);

      final loaded = store.load();
      expect(loaded.runs.single.entries.single.beforeHash, isEmpty);

      store.save(loaded);

      final preserved = root
          .listSync(recursive: true)
          .whereType<File>()
          .where((entry) => entry.path.contains('.preserved-'))
          .toList();
      expect(preserved.single.readAsStringSync(), raw);
      expect(
        jsonDecode(file.readAsStringSync())['version'],
        RunCheckpointStore.currentVersion,
      );
    });

    test('corrupt content is reported as empty and kept before a rewrite', () {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('[not a store');

      expect(store.load().runs, isEmpty);
      expect(store.save(RunCheckpointsSnapshot.empty), isTrue);
      final preserved = root
          .listSync(recursive: true)
          .whereType<File>()
          .where((entry) => entry.path.contains('.preserved-'))
          .toList();
      expect(preserved.single.readAsStringSync(), '[not a store');
    });

    test('the oldest runs go first when the store is over its limits', () {
      final runs = [
        for (var index = 0; index < RunCheckpointLimits.maxRuns + 5; index++)
          _run([_entry(after: 'x')], id: 'run-$index'),
      ];
      // Newest first, as the store keeps them.
      final bounded = RunCheckpointsSnapshot(
        runs: runs.reversed.toList(),
      ).bounded();

      expect(bounded.runs, hasLength(RunCheckpointLimits.maxRuns));
      expect(bounded.runs.first.id, 'run-${runs.length - 1}');
      expect(
        bounded.runs.any((run) => run.id == 'run-0'),
        isFalse,
        reason: 'the oldest run is given up whole',
      );
    });

    test('content over the byte limit drops the oldest runs', () {
      final big = 'x' * (RunCheckpointLimits.maxTotalBytes ~/ 3);
      final runs = [
        for (var index = 0; index < 5; index++)
          _run([_entry(before: big, after: 'y')], id: 'run-$index'),
      ];

      final bounded = RunCheckpointsSnapshot(
        runs: runs.reversed.toList(),
      ).bounded();

      expect(bounded.runs.length, lessThan(runs.length));
      expect(bounded.runs.first.id, 'run-4');
    });
  });

  group('run recorder', () {
    late Directory root;
    late RunCheckpointStore store;

    setUp(() {
      root = Directory.systemTemp.createTempSync('run-session-');
      store = RunCheckpointStore(File('${root.path}/agents/checkpoints.json'));
    });

    tearDown(() => root.deleteSync(recursive: true));

    RunCheckpointSession session() => RunCheckpointSession(
      store: store,
      contextKey: 'room:r1',
      label: 'One',
      id: 'run-1',
      startedAt: DateTime(2026, 10, 15, 12),
    );

    test('a run that only read, or whose write failed, leaves no record', () {
      final run = session();
      run.recordBefore(
        path: '/vault/Project/notes/ok.md',
        relativePath: 'notes/ok.md',
        content: 'before\n',
      );

      expect(run.hasRecordedWrites, isFalse);
      expect(store.load().runs, isEmpty);
    });

    test(
      'the first before-state and the last write decide the entry',
      () async {
        final run = session();
        run.recordBefore(
          path: '/vault/Project/notes/ok.md',
          relativePath: 'notes/ok.md',
          content: 'before\n',
        );
        await run.recordAfter(
          path: '/vault/Project/notes/ok.md',
          relativePath: 'notes/ok.md',
          content: 'first write\n',
        );
        run.recordBefore(
          path: '/vault/Project/notes/ok.md',
          relativePath: 'notes/ok.md',
          content: 'second before\n',
        );
        await run.recordAfter(
          path: '/vault/Project/notes/ok.md',
          relativePath: 'notes/ok.md',
          content: 'second write\n',
        );

        final entry = store.load().runs.single.entries.single;
        expect(entry.beforeContent, 'before\n');
        expect(entry.afterHash, runCheckpointHash('second write\n'));
      },
    );

    test('a created file is recorded as removable', () async {
      final run = session();
      run.recordBefore(
        path: '/vault/Project/notes/new.md',
        relativePath: 'notes/new.md',
        content: null,
      );
      await run.recordAfter(
        path: '/vault/Project/notes/new.md',
        relativePath: 'notes/new.md',
        content: 'created\n',
      );

      final entry = store.load().runs.single.entries.single;
      expect(entry.beforeExists, isFalse);
      expect(entry.removesFile, isTrue);
      expect(entry.isRestorable, isTrue);
    });

    test('a file kept too big is recorded as blocked, not skipped', () async {
      final run = session();
      final huge = 'x' * (RunCheckpointLimits.maxContentBytes + 1);
      run.recordBefore(
        path: '/vault/Project/notes/big.md',
        relativePath: 'notes/big.md',
        content: huge,
      );
      await run.recordAfter(
        path: '/vault/Project/notes/big.md',
        relativePath: 'notes/big.md',
        content: 'small now\n',
      );

      final entry = store.load().runs.single.entries.single;
      expect(entry.blocked, isNotNull);
      expect(entry.isRestorable, isFalse);
      expect(store.load().runs.single.isRestorable, isFalse);
    });

    test(
      'a run that wrote too many files cannot be rewound as a whole',
      () async {
        final run = session();
        for (
          var index = 0;
          index <= RunCheckpointLimits.maxEntriesPerRun;
          index++
        ) {
          final path = '/vault/Project/notes/$index.md';
          run.recordBefore(
            path: path,
            relativePath: 'notes/$index.md',
            content: null,
          );
          await run.recordAfter(
            path: path,
            relativePath: 'notes/$index.md',
            content: 'written $index\n',
          );
        }

        final stored = store.load().runs.single;
        expect(
          stored.entries,
          hasLength(RunCheckpointLimits.maxEntriesPerRun + 1),
        );
        expect(stored.isRestorable, isFalse);
        expect(stored.entries.last.blocked, contains('more than'));
      },
    );

    test('a read-only store leaves the run usable and unrecorded', () async {
      final file = File('${root.path}/agents/checkpoints.json');
      file.parent.createSync(recursive: true);
      const raw = '{"version":99,"runs":[]}';
      file.writeAsStringSync(raw);

      final run = session();
      run.recordBefore(
        path: '/vault/Project/notes/ok.md',
        relativePath: 'notes/ok.md',
        content: null,
      );
      await run.recordAfter(
        path: '/vault/Project/notes/ok.md',
        relativePath: 'notes/ok.md',
        content: 'written\n',
      );

      expect(run.isUsable, isFalse);
      expect(file.readAsStringSync(), raw);
    });

    test('runs are listed newest first and only for their own chat', () async {
      final first = session();
      first.recordBefore(
        path: '/vault/Project/a.md',
        relativePath: 'a.md',
        content: null,
      );
      await first.recordAfter(
        path: '/vault/Project/a.md',
        relativePath: 'a.md',
        content: 'a\n',
      );
      final second = RunCheckpointSession(
        store: store,
        contextKey: 'room:other',
        label: 'Two',
        id: 'run-2',
        startedAt: DateTime(2026, 10, 15, 13),
      );
      second.recordBefore(
        path: '/vault/Project/b.md',
        relativePath: 'b.md',
        content: null,
      );
      await second.recordAfter(
        path: '/vault/Project/b.md',
        relativePath: 'b.md',
        content: 'b\n',
      );

      final snapshot = store.load();
      expect(snapshot.runs.first.id, 'run-2');
      expect(snapshot.forContext('room:r1').single.id, 'run-1');
      expect(snapshot.forContext('room:none'), isEmpty);
    });
  });

  group('rewind planner', () {
    test('puts an edited file back and removes a created one', () {
      final run = _run([
        _entry(before: 'before\n', after: 'after\n'),
        _entry(relativePath: 'notes/new.md', after: 'created\n'),
      ]);

      final plan = RewindPlanner.plan(
        run: run,
        currentContent: (entry) =>
            entry.relativePath == 'notes/new.md' ? 'created\n' : 'after\n',
      );

      expect(plan.canRun, isTrue);
      expect(plan.steps, hasLength(2));
      expect(plan.steps.first.remove, isFalse);
      expect(plan.steps.last.remove, isTrue);
      expect(plan.steps.first.entry.beforeContent, 'before\n');
    });

    test('refuses when a file changed after the run wrote it', () {
      final run = _run([_entry(before: 'before\n', after: 'after\n')]);

      final plan = RewindPlanner.plan(
        run: run,
        currentContent: (entry) => 'the user edited this\n',
      );

      expect(plan.canRun, isFalse);
      expect(plan.steps, isEmpty);
      expect(plan.refusals.single, contains('changed after this run wrote it'));
      expect(
        plan.refusals.single,
        contains(shortRunCheckpointHash(runCheckpointHash('after\n'))),
      );
    });

    test('refuses when a file the run wrote is gone', () {
      final plan = RewindPlanner.plan(
        run: _run([_entry(before: 'before\n', after: 'after\n')]),
        currentContent: (entry) => null,
      );

      expect(plan.canRun, isFalse);
      expect(plan.refusals.single, contains('is gone'));
    });

    test('one conflicted file refuses the whole run', () {
      final run = _run([
        _entry(before: 'before\n', after: 'after\n'),
        _entry(relativePath: 'notes/other.md', before: 'x\n', after: 'y\n'),
      ]);

      final plan = RewindPlanner.plan(
        run: run,
        currentContent: (entry) =>
            entry.relativePath == 'notes/other.md' ? 'edited\n' : 'after\n',
      );

      expect(plan.canRun, isFalse);
      expect(plan.steps, isEmpty);
      expect(plan.refusals.single, contains('notes/other.md'));
    });

    test('a blocked or incomplete entry refuses the whole run', () {
      final blocked = RewindPlanner.plan(
        run: _run([
          _entry(after: 'after\n', blocked: 'the file was too large.'),
        ]),
        currentContent: (entry) => 'after\n',
      );
      expect(blocked.canRun, isFalse);
      expect(blocked.refusals.single, contains('too large'));

      final missingBefore = RewindPlanner.plan(
        run: RunCheckpoint(
          id: 'run-1',
          contextKey: 'room:r1',
          label: 'One',
          startedAt: DateTime(2026, 10, 15, 12),
          entries: [
            RunCheckpointEntry(
              relativePath: 'notes/ok.md',
              path: '/vault/Project/notes/ok.md',
              beforeExists: true,
              beforeHash: runCheckpointHash('gone'),
              afterHash: runCheckpointHash('after\n'),
              writtenAt: DateTime(2026, 10, 15, 12),
            ),
          ],
        ),
        currentContent: (entry) => 'after\n',
      );
      expect(missingBefore.canRun, isFalse);
      expect(missingBefore.refusals.single, contains('not kept'));
    });

    test('a run that wrote nothing has nothing to rewind', () {
      final plan = RewindPlanner.plan(
        run: _run(const []),
        currentContent: (entry) => null,
      );

      expect(plan.canRun, isFalse);
      expect(plan.refusals.single, contains('wrote no files'));
    });
  });
}
