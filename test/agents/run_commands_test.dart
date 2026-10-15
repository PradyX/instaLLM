import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/agents/application/run_commands.dart';
import 'package:installm/features/agents/domain/run_checkpoint.dart';

RunCheckpoint _run({
  String id = 'run-1',
  String label = 'One',
  List<RunCheckpointEntry> entries = const [],
}) => RunCheckpoint(
  id: id,
  contextKey: 'room:r1',
  label: label,
  startedAt: DateTime(2026, 10, 15, 14, 32),
  entries: entries,
);

RunCheckpointEntry _entry(String relativePath, {String? blocked}) =>
    RunCheckpointEntry(
      relativePath: relativePath,
      path: '/vault/Project/$relativePath',
      beforeExists: false,
      beforeHash: runCheckpointHash(''),
      afterHash: blocked == null ? runCheckpointHash('written\n') : '',
      writtenAt: DateTime(2026, 10, 15, 14, 32),
      blocked: blocked,
    );

void main() {
  group('parse', () {
    test('ignores text that is not the rewind command', () {
      expect(RewindCommand.parse('rewind'), isNull);
      expect(RewindCommand.parse('/rewinds'), isNull);
      expect(RewindCommand.parse('please /rewind'), isNull);
      expect(RewindCommand.parse('/skills'), isNull);
    });

    test('bare and list forms list without running anything', () {
      expect(RewindCommand.parse('/rewind')!.list, isTrue);
      expect(RewindCommand.parse('  /rewind  ')!.list, isTrue);
      expect(RewindCommand.parse('/REWIND list')!.list, isTrue);
      expect(RewindCommand.parse('/rewind')!.runId, isNull);
    });

    test('last and an id are the two ways to run it', () {
      expect(RewindCommand.parse('/rewind last')!.runId, 'last');
      expect(RewindCommand.parse('/rewind Last')!.runId, 'last');
      expect(RewindCommand.parse('/rewind run-1699')!.runId, 'run-1699');
    });

    test('a half-written command shows the usage instead of guessing', () {
      final command = RewindCommand.parse('/rewind two words')!;
      expect(command.runId, isNull);
      expect(command.list, isFalse);
      expect(command.message, RewindCommand.usage);
    });

    test('the composer offers the command', () {
      expect(RewindCommand.option().command, '/rewind');
      expect(RewindCommand.option().description, isNotEmpty);
    });
  });

  group('listing', () {
    test('says so when nothing was written yet', () {
      expect(rewindListing(const []), contains('has written a file yet'));
    });

    test('names each run, its files and the command that puts them back', () {
      final listing = rewindListing([
        _run(entries: [_entry('notes/a.md')]),
        _run(id: 'run-0', label: 'Two', entries: [_entry('notes/b.md')]),
      ]);

      expect(listing, contains('Agent runs that wrote files here'));
      expect(listing, contains('run-1 · One · 14:32 · 1 file'));
      expect(listing, contains('/rewind run-1'));
      expect(listing, contains('run-0 · Two'));
      expect(listing, contains('notes/a.md'));
      expect(listing, contains('notes/b.md'));
    });

    test('marks a run that cannot be put back as a whole', () {
      final listing = rewindListing([
        _run(entries: [_entry('notes/big.md', blocked: 'the file was there.')]),
      ]);

      expect(listing, contains('cannot be rewound as a whole'));
    });

    test('shows at most ten runs', () {
      final listing = rewindListing([
        for (var index = 0; index < 12; index++)
          _run(id: 'run-$index', entries: [_entry('notes/$index.md')]),
      ]);

      expect(listing, contains('/rewind run-9'));
      expect(listing, isNot(contains('/rewind run-10')));
    });
  });
}
