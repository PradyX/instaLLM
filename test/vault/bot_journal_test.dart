import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/vault/application/bot_journal_service.dart';
import 'package:installm/features/vault/application/vault_notes_service.dart';
import 'package:installm/features/vault/domain/vault_paths.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';
import 'package:installm/features/vault/data/journal_checkpoint_store.dart';
import 'package:installm/features/conversations/domain/conversation_memory.dart';
import 'package:installm/features/tools/application/tool_registry.dart';
import 'package:installm/features/tools/domain/tool_call.dart';
import 'package:installm/features/tools/domain/tool_definition.dart';
import 'package:installm/features/tools/domain/tool_execution_result.dart';

class _Gate implements ToolPermissionGate {
  bool allow = false;
  int requests = 0;
  @override
  Future<bool> requestApproval(ToolApprovalRequest request) async {
    requests++;
    return allow;
  }
}

void main() {
  late Directory root;
  late VaultPaths paths;
  late JournalCheckpointStore checkpoints;
  setUp(() {
    root = Directory.systemTemp.createTempSync('installm-journal-');
    paths = VaultPaths(vaultRoot: root.path, projectPath: 'Project');
    checkpoints = JournalCheckpointStore(
      File('${root.path}/support/checkpoints.json'),
    );
  });
  tearDown(() => root.deleteSync(recursive: true));
  Future<BotJournalSession> session({
    String bot = 'one',
    VaultPermissions? Function()? live,
  }) async => (await BotJournalSession.open(
    paths: paths,
    permissions: VaultPermissions.defaults,
    botId: bot,
    checkpoints: checkpoints,
    contextKey: 'vault|workspace',
    now: DateTime(2026, 10, 14),
    resolvePermissions: live,
  ))!;
  File note(String path) => File(paths.projectFile(path)!);

  test(
    'bot-written summaries and dated decisions are bounded and strip reasoning',
    () async {
      final journal = await session();
      expect(
        await journal.record(
          '<think>private reasoning</think> Summary: Use\n Dart. ${'x' * 5000}',
        ),
        startsWith('Saved'),
      );
      final text = await note(journal.summaryPath).readAsString();
      expect(text, isNot(contains('private reasoning')));
      expect(text, startsWith('Use Dart.'));
      expect(
        text.length,
        lessThanOrEqualTo(ConversationMemory.maxSummaryCharacters + 1),
      );
      expect(
        await journal.record('Keep data local.', decision: true),
        startsWith('Saved'),
      );
      expect(journal.decisionPath, 'bots/bot-one/decisions/2026-10-14.md');
      expect(
        await note(journal.decisionPath).readAsString(),
        'Keep data local.\n',
      );
      final original = await note(journal.summaryPath).readAsString();
      expect(
        await journal.record('<think>unfinished'),
        contains('No project summary'),
      );
      expect(await note(journal.summaryPath).readAsString(), original);
    },
  );

  test(
    'ownership survives restart; user edits between runs and during a run are preserved',
    () async {
      final first = await session();
      await first.record('First summary.');
      checkpoints = JournalCheckpointStore(checkpoints.file);
      final second = await session();
      expect(await second.record('Second summary.'), startsWith('Saved'));
      final file = note(second.summaryPath);
      final modified = (await file.stat()).modified;
      await file.writeAsString('User edited this.');
      await file.setLastModified(
        modified,
      ); // Same timestamp must still conflict.
      expect(
        await second.record('Would overwrite edit.'),
        contains('not saved'),
      );
      expect(await file.readAsString(), 'User edited this.');
      final restarted = await session();
      expect(
        await restarted.record('Would overwrite old edit.'),
        contains('ownership is unknown'),
      );
      expect(await file.readAsString(), 'User edited this.');
    },
  );

  test(
    'existing unowned notes and unsupported checkpoints are never overwritten',
    () async {
      final file = note('bots/bot-one/summary.md');
      await file.parent.create(recursive: true);
      await file.writeAsString('Handwritten note.');
      final journal = await session();
      expect(await journal.record('New summary.'), contains('not saved'));
      expect(await file.readAsString(), 'Handwritten note.');
      await checkpoints.file.parent.create(recursive: true);
      await checkpoints.file.writeAsString('{"version":99,"hashes":{}}');
      expect(
        await BotJournalSession.open(
          paths: paths,
          permissions: VaultPermissions.defaults,
          botId: 'two',
          checkpoints: checkpoints,
        ),
        isNull,
      );
      expect(
        await checkpoints.file.readAsString(),
        '{"version":99,"hashes":{}}',
      );
    },
  );

  test(
    'own journal bypasses prompts; every other destination needs explicit approval',
    () async {
      final journal = await session();
      final gate = _Gate();
      final registry = ToolRegistry(
        tools: journal.tools(),
        platform: ToolPlatform.macOS,
        permissionGate: gate,
      );
      final own = await registry.execute(
        const ToolCall(
          toolName: 'vault_record_summary',
          arguments: {'summary': 'Local facts.'},
        ),
      );
      expect(own.output, startsWith('Saved'));
      expect(gate.requests, 0);
      const elsewhere = ToolCall(
        toolName: 'vault_write_note',
        arguments: {
          'relativePath': 'bots/bot-two/summary.md',
          'summary': 'Other project note.',
        },
      );
      final denied = await registry.execute(elsewhere);
      expect(denied.status, ToolExecutionStatus.denied);
      expect(await note('bots/bot-two/summary.md').exists(), isFalse);
      gate.allow = true;
      expect((await registry.execute(elsewhere)).output, startsWith('Saved'));
      expect(gate.requests, 2);
      expect((await registry.execute(elsewhere)).output, contains('not saved'));
      final outside = await registry.execute(
        const ToolCall(
          toolName: 'vault_write_note',
          arguments: {'relativePath': '../../outside.md', 'summary': 'Denied.'},
        ),
      );
      expect(outside.output, contains('not saved'));
      expect(await File('${root.parent.path}/outside.md').exists(), isFalse);
    },
  );

  test(
    'revoked permissions and child symlinks cannot redirect writes',
    () async {
      VaultPermissions? live = VaultPermissions.defaults;
      final journal = await session(live: () => live);
      live = null;
      expect(
        await journal.record('Do not write.'),
        contains('permissions changed'),
      );
      expect(await note(journal.summaryPath).exists(), isFalse);
      final other = Directory('${root.path}/Other')..createSync();
      final link = Link('${paths.projectDir}/bots');
      await link.parent.create(recursive: true);
      await link.create(other.path);
      expect(
        await BotJournalSession.open(
          paths: paths,
          permissions: VaultPermissions.defaults,
          botId: 'one',
          checkpoints: checkpoints,
        ),
        isNull,
      );
      expect(await other.list().isEmpty, isTrue);
    },
  );

  test(
    'corrupt ownership is preserved before recovery; failed checkpoint writes block later updates',
    () async {
      await checkpoints.file.parent.create(recursive: true);
      await checkpoints.file.writeAsString('broken ownership');
      final journal = await session();
      expect(
        await journal.record('A concise project fact.'),
        startsWith('Saved'),
      );
      final preserved = checkpoints.file.parent
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.preserved-'))
          .single;
      expect(preserved.readAsStringSync(), 'broken ownership');
      expect(
        checkpoints.file.readAsStringSync(),
        isNot(contains('A concise project fact.')),
      );
      final blocker = Directory('${checkpoints.file.path}.tmp')..createSync();
      expect(
        await journal.record('Updated project fact.'),
        contains('ownership could not be saved'),
      );
      final file = note(journal.summaryPath);
      expect(await file.readAsString(), 'Updated project fact.\n');
      blocker.deleteSync();
      expect(
        await journal.record('Would lose the previous update.'),
        contains('not saved'),
      );
      expect(await file.readAsString(), 'Updated project fact.\n');
    },
  );

  test(
    'concurrent conditional writes accept one and preserve the winner',
    () async {
      const notes = VaultNotesService();
      final outcomes = await Future.wait([
        notes.writeNote(
          paths: paths,
          permissions: VaultPermissions.defaults,
          relativePath: 'same.md',
          content: 'one',
          createOnly: true,
        ),
        notes.writeNote(
          paths: paths,
          permissions: VaultPermissions.defaults,
          relativePath: 'same.md',
          content: 'two',
          createOnly: true,
        ),
      ]);
      expect(outcomes.where((e) => e == null), hasLength(1));
      expect(outcomes.where((e) => e == VaultNoteError.conflict), hasLength(1));
      expect(await note('same.md').readAsString(), anyOf('one', 'two'));
    },
  );
}
