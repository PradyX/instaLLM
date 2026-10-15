import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/agents/application/rewind_service.dart';
import 'package:installm/features/agents/domain/run_checkpoint.dart';
import 'package:installm/features/vault/domain/vault_paths.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';

RunCheckpointEntry _entry({
  required String relativePath,
  String? before,
  required String after,
}) {
  return RunCheckpointEntry(
    relativePath: relativePath,
    path: '/vault/Project/$relativePath',
    beforeExists: before != null,
    beforeContent: before,
    beforeHash: runCheckpointHash(before ?? ''),
    afterHash: runCheckpointHash(after),
    writtenAt: DateTime(2026, 10, 15, 12),
  );
}

void main() {
  late Directory root;
  late VaultPaths paths;

  setUp(() {
    root = Directory.systemTemp.createTempSync('rewind-');
    paths = VaultPaths(vaultRoot: root.path, projectPath: 'Project');
    Directory('${root.path}/Project/notes').createSync(recursive: true);
  });

  tearDown(() => root.deleteSync(recursive: true));

  File note(String relativePath) => File('${root.path}/Project/$relativePath');

  RunCheckpoint run(List<RunCheckpointEntry> entries) => RunCheckpoint(
    id: 'run-1',
    contextKey: 'room:r1',
    label: 'One',
    startedAt: DateTime(2026, 10, 15, 12),
    entries: entries,
  );

  test('puts back the text a file held before the run', () async {
    note('notes/ok.md').writeAsStringSync('the run wrote this\n');

    final outcome = await const RewindService().rewind(
      run: run([
        _entry(
          relativePath: 'notes/ok.md',
          before: 'before\n',
          after: 'the run wrote this\n',
        ),
      ]),
      paths: paths,
    );

    expect(outcome.restored, isTrue, reason: outcome.message);
    expect(outcome.restoredPaths, ['notes/ok.md']);
    expect(note('notes/ok.md').readAsStringSync(), 'before\n');
    expect(outcome.message, contains('The conversation is unchanged'));
  });

  test(
    'removes a file the run created when it still holds that text',
    () async {
      note('notes/new.md').writeAsStringSync('created by the run\n');

      final outcome = await const RewindService().rewind(
        run: run([
          _entry(relativePath: 'notes/new.md', after: 'created by the run\n'),
        ]),
        paths: paths,
      );

      expect(outcome.restored, isTrue, reason: outcome.message);
      expect(note('notes/new.md').existsSync(), isFalse);
      expect(outcome.message, contains('notes/new.md (removed)'));
    },
  );

  test('refuses every file when one changed after the run wrote it', () async {
    note('notes/ok.md').writeAsStringSync('the run wrote this\n');
    note('notes/other.md').writeAsStringSync('the user edited this\n');

    final outcome = await const RewindService().rewind(
      run: run([
        _entry(
          relativePath: 'notes/ok.md',
          before: 'before\n',
          after: 'the run wrote this\n',
        ),
        _entry(
          relativePath: 'notes/other.md',
          before: 'older\n',
          after: 'the run wrote other\n',
        ),
      ]),
      paths: paths,
    );

    expect(outcome.restored, isFalse);
    expect(outcome.restoredPaths, isEmpty);
    expect(outcome.message, contains('changed after this run wrote it'));
    expect(outcome.message, contains('notes/other.md'));
    expect(
      note('notes/ok.md').readAsStringSync(),
      'the run wrote this\n',
      reason:
          'a refusal changes no file, not even the ones that were still intact',
    );
    expect(note('notes/other.md').readAsStringSync(), 'the user edited this\n');
  });

  test('keeps a deletion the user made after the run', () async {
    final outcome = await const RewindService().rewind(
      run: run([
        _entry(
          relativePath: 'notes/gone.md',
          before: 'before\n',
          after: 'written\n',
        ),
      ]),
      paths: paths,
    );

    expect(outcome.restored, isFalse);
    expect(outcome.message, contains('is gone'));
    expect(note('notes/gone.md').existsSync(), isFalse);
  });

  test('touches nothing outside the run', () async {
    note('notes/ok.md').writeAsStringSync('written\n');
    note('notes/neighbour.md').writeAsStringSync('untouched\n');

    final outcome = await const RewindService().rewind(
      run: run([
        _entry(
          relativePath: 'notes/ok.md',
          before: 'before\n',
          after: 'written\n',
        ),
      ]),
      paths: paths,
    );

    expect(outcome.restored, isTrue);
    expect(note('notes/neighbour.md').readAsStringSync(), 'untouched\n');
  });

  test('reports a file it could not read instead of guessing', () async {
    final outcome = await const RewindService().rewind(
      run: run([
        _entry(
          relativePath: '../outside.md',
          before: 'before\n',
          after: 'written\n',
        ),
      ]),
      paths: paths,
      permissions: VaultPermissions.defaults,
    );

    expect(outcome.restored, isFalse);
    expect(outcome.message, contains('Rewind changed nothing'));
    expect(outcome.message, contains('Outside the project folder'));
  });

  test('a run with no files says so', () async {
    final outcome = await const RewindService().rewind(
      run: run(const []),
      paths: paths,
    );

    expect(outcome.restored, isFalse);
    expect(outcome.message, contains('wrote no files'));
  });
}
