import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/agents/domain/agent_hook.dart';
import 'package:installm/features/conversations/domain/message_tool_activity.dart';
import 'package:installm/features/tools/application/tool_activity_mapping.dart';
import 'package:installm/features/tools/application/tool_registry.dart';
import 'package:installm/features/tools/domain/tool_call.dart';
import 'package:installm/features/tools/domain/tool_definition.dart';
import 'package:installm/features/tools/domain/tool_execution_result.dart';
import 'package:installm/features/vault/application/bot_journal_service.dart';
import 'package:installm/features/vault/data/journal_checkpoint_store.dart';
import 'package:installm/features/vault/domain/vault_paths.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';

/// Gate that records what it was asked and answers with a fixed decision.
class _AnsweringGate implements ToolPermissionGate {
  _AnsweringGate({this.approved = true});

  final bool approved;
  final List<ToolApprovalRequest> requests = [];

  @override
  Future<bool> requestApproval(ToolApprovalRequest request) async {
    requests.add(request);
    return approved;
  }
}

void main() {
  late Directory root;
  late File note;
  late ToolRegistry Function(HookPolicy hooks, ToolPermissionGate gate)
  registry;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('hook-enforce-');
    note = File('${root.path}/Project/notes/ok.md');
    final session = (await BotJournalSession.open(
      paths: VaultPaths(vaultRoot: root.path, projectPath: 'Project'),
      permissions: VaultPermissions.defaults,
      botId: 'one',
      checkpoints: JournalCheckpointStore(File('${root.path}/points.json')),
    ))!;
    final entries = session.tools();
    registry = (hooks, gate) => ToolRegistry(
      tools: entries,
      platform: ToolPlatform.linux,
      permissionGate: gate,
      hooks: hooks,
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<ToolExecutionResult> write(
    ToolRegistry target, {
    required String path,
    String summary = 'Kept these facts.',
  }) => target.execute(
    ToolCall(
      toolName: 'vault_write_note',
      arguments: {'relativePath': path, 'summary': summary},
    ),
  );

  test(
    'a hook refuses a write to a protected path before anything runs',
    () async {
      final gate = _AnsweringGate();
      final target = registry(
        HookPolicy(
          hooks: [
            AgentHook.create(
              id: 'hook-1',
              name: 'Protect secrets',
              resourcePattern: 'secrets/**',
            ),
          ],
        ),
        gate,
      );

      final result = await write(target, path: 'secrets/keys.md');

      expect(result.status, ToolExecutionStatus.denied);
      expect(result.output, contains('Protect secrets'));
      expect(result.output, contains('secrets/keys.md'));
      expect(
        File('${root.path}/Project/secrets/keys.md').existsSync(),
        isFalse,
      );
      // A refusal the user wrote is final, so no permission question was asked.
      expect(gate.requests, isEmpty);
    },
  );

  test(
    'the refusal is what the turn records and what the model is told',
    () async {
      final target = registry(
        HookPolicy(
          hooks: [
            AgentHook.create(
              id: 'hook-1',
              name: 'Protect secrets',
              resourcePattern: 'secrets/**',
            ),
          ],
        ),
        _AnsweringGate(),
      );
      const call = ToolCall(
        toolName: 'vault_write_note',
        arguments: {'relativePath': 'secrets/keys.md'},
      );

      final result = await write(target, path: 'secrets/keys.md');
      final activity = messageToolActivityFrom(call: call, result: result);

      expect(activity.status, MessageToolActivityStatus.denied);
      expect(activity.output, contains('Protect secrets'));
      expect(result.toModelText(), contains('Status: denied'));
      expect(result.toModelText(), contains('Protect secrets'));
    },
  );

  test('an untouched path is written exactly as before', () async {
    final gate = _AnsweringGate();
    final target = registry(
      HookPolicy(
        hooks: [
          AgentHook.create(
            id: 'hook-1',
            name: 'Protect secrets',
            resourcePattern: 'secrets/**',
          ),
        ],
      ),
      gate,
    );

    final result = await write(target, path: 'notes/ok.md');

    expect(result.isSuccess, isTrue, reason: result.output);
    expect(note.existsSync(), isTrue);
    expect(gate.requests.single.summary, contains('notes/ok.md'));
  });

  test('a disabled rule lets the same write through again', () async {
    final target = registry(
      HookPolicy(
        hooks: [
          AgentHook.create(
            id: 'hook-1',
            name: 'Protect secrets',
            resourcePattern: 'secrets/**',
            enabled: false,
          ),
        ],
      ),
      _AnsweringGate(),
    );

    final result = await write(target, path: 'notes/ok.md');

    expect(result.isSuccess, isTrue, reason: result.output);
  });

  test('the built-in floor refuses a write into git internals', () async {
    final target = registry(
      HookPolicy(hooks: BuiltInHooks.all),
      _AnsweringGate(),
    );

    final result = await write(target, path: '.git/config.md');

    expect(result.status, ToolExecutionStatus.denied);
    expect(result.output, contains('Git internals'));
    expect(File('${root.path}/Project/.git/config.md').existsSync(), isFalse);
  });

  test(
    'an ask rule adds the permission question to a tool that asks none',
    () async {
      final gate = _AnsweringGate();
      final target = registry(
        HookPolicy(
          hooks: [
            AgentHook.create(
              id: 'hook-1',
              name: 'Check summaries',
              toolPattern: 'vault_record_summary',
              level: HookLevel.ask,
            ),
          ],
        ),
        gate,
      );

      final result = await target.execute(
        const ToolCall(
          toolName: 'vault_record_summary',
          arguments: {'summary': 'The project uses Dart.'},
        ),
      );

      expect(result.isSuccess, isTrue, reason: result.output);
      expect(gate.requests.single.summary, contains('vault_record_summary'));
      expect(
        File('${root.path}/Project/bots/bot-one/summary.md').existsSync(),
        isTrue,
      );
    },
  );

  test('a refused question keeps the reason the hook gave', () async {
    final target = registry(
      HookPolicy(
        hooks: [
          AgentHook.create(
            id: 'hook-1',
            name: 'Check summaries',
            toolPattern: 'vault_record_summary',
            level: HookLevel.ask,
          ),
        ],
      ),
      _AnsweringGate(approved: false),
    );

    final result = await target.execute(
      const ToolCall(
        toolName: 'vault_record_summary',
        arguments: {'summary': 'The project uses Dart.'},
      ),
    );

    expect(result.status, ToolExecutionStatus.denied);
    expect(result.output, contains('Check summaries'));
    expect(
      File('${root.path}/Project/bots/bot-one/summary.md').existsSync(),
      isFalse,
    );
  });

  test('a rule that protects paths leaves a pathless call alone', () async {
    final target = registry(
      HookPolicy(
        hooks: [
          AgentHook.create(
            id: 'hook-1',
            name: 'Protect everything named',
            resourcePattern: '**/*',
          ),
        ],
      ),
      _AnsweringGate(),
    );

    final result = await target.execute(
      const ToolCall(
        toolName: 'vault_record_summary',
        arguments: {'summary': 'The project uses Dart.'},
      ),
    );

    expect(result.isSuccess, isTrue, reason: result.output);
  });
}
