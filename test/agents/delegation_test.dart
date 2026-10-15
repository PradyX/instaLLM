import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/agents/application/agent_loop_service.dart';
import 'package:installm/features/agents/application/delegation_service.dart';
import 'package:installm/features/agents/application/delegation_tools.dart';
import 'package:installm/features/agents/domain/agent_run.dart';
import 'package:installm/features/agents/domain/delegation.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/context/domain/context_budget.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/tools/application/tool_registry.dart';
import 'package:installm/features/tools/domain/tool_call.dart';
import 'package:installm/features/tools/domain/tool_definition.dart';
import 'package:installm/features/vault/domain/vault_paths.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';

import 'scripted_agent_runtime.dart';

const LlmModel _model = LlmModel(
  id: 'm',
  name: 'Local',
  parameterSize: '1B',
  description: 'test',
  isDownloaded: true,
  capabilities: [ModelCapability.tools],
);

Bot _bot(String id, String name, {String soul = ''}) =>
    Bot.create(id: id, name: name, soul: soul);

ToolEntry _tool(String name, ToolRiskLevel risk) => ToolEntry(
  definition: ToolDefinition(
    name: name,
    description: 'Test tool $name.',
    parameters: const [],
    risk: risk,
  ),
  handler: (arguments) async => '$name ran',
);

void main() {
  group('the child envelope', () {
    late ToolRegistry parent;

    setUp(() {
      parent = ToolRegistry(
        tools: [
          _tool('calculator', ToolRiskLevel.safe),
          _tool('search_chat_history', ToolRiskLevel.readOnly),
          _tool('vault_write_note', ToolRiskLevel.sensitive),
          _tool('vault_record_summary', ToolRiskLevel.scopedWrite),
          _tool(delegationToolName, ToolRiskLevel.readOnly),
        ],
        platform: ToolPlatform.linux,
      );
    });

    test('reads but never writes, and can never delegate again', () {
      final child = parent.readOnlyOnly().without(const [delegationToolName]);

      expect(
        child.definitions.map((definition) => definition.name),
        containsAll(<String>['calculator', 'search_chat_history']),
      );
      expect(child.definitionFor('vault_write_note'), isNull);
      expect(child.definitionFor('vault_record_summary'), isNull);
      expect(child.definitionFor(delegationToolName), isNull);
    });

    test('narrowing is one way: a child registry cannot be widened back', () {
      final child = parent.readOnlyOnly();

      final regrown = child.extendedWith([
        _tool('vault_write_note', ToolRiskLevel.sensitive),
      ]);

      expect(
        regrown.definitionFor('vault_write_note'),
        isNotNull,
        reason: 'only the caller decides what a child gets',
      );
      expect(child.definitionFor('vault_write_note'), isNull);
    });
  });

  group('targets', () {
    final members = [_bot('bot-one', 'One'), _bot('two', 'Research bot')];

    test('a bot is found by id or by the name the model used', () {
      expect(
        delegatedTarget(members: members, requested: 'One')?.id,
        'bot-one',
      );
      expect(
        delegatedTarget(members: members, requested: 'bot-one')?.name,
        'One',
        reason: 'ids are accepted too',
      );
      expect(
        delegatedTarget(members: members, requested: 'research bot')?.id,
        'two',
      );
      expect(
        delegatedTarget(members: members, requested: '  RESEARCH BOT ')?.id,
        'two',
      );
    });

    test('an unknown or empty name matches nothing', () {
      expect(delegatedTarget(members: members, requested: 'nobody'), isNull);
      expect(delegatedTarget(members: members, requested: '   '), isNull);
      expect(delegatedTarget(members: const [], requested: 'one'), isNull);
    });
  });

  group('the child prompt', () {
    const runner = DelegationRunner();

    test('carries the child soul, the task and the named files only', () {
      final prompt = runner.promptFor(
        target: _bot('two', 'Research bot', soul: 'You research documents.'),
        task: 'List the widgets in the notes.',
        parentName: 'One',
        fileSlice: '--- notes/a.md\nWidgets are listed here.',
      );

      expect(prompt, contains('You research documents.'));
      expect(prompt, contains('Delegated by: One'));
      expect(prompt, contains('List the widgets in the notes.'));
      expect(prompt, contains('Widgets are listed here.'));
      expect(prompt, contains('not shared with it'));
    });

    test('has no place for a chat transcript', () {
      final prompt = runner.promptFor(
        target: _bot('two', 'Research bot'),
        task: 'Answer the question.',
      );

      expect(prompt, isNot(contains('Track implementation')));
      expect(prompt, isNot(contains('Message the room')));
    });
  });

  group('reading a slice', () {
    late Directory root;
    late VaultPaths paths;

    setUp(() {
      root = Directory.systemTemp.createTempSync('delegation-slice-');
      paths = VaultPaths(vaultRoot: root.path, projectPath: 'Project');
      Directory('${root.path}/Project/notes').createSync(recursive: true);
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('reads the named notes and says which ones it could not', () async {
      File('${root.path}/Project/notes/a.md').writeAsStringSync('Widget list.');
      File(
        '${root.path}/Project/notes/long.md',
      ).writeAsStringSync('x' * (DelegationLimits.maxFileCharacters + 500));

      final slice = await const DelegationRunner().readSlice(
        paths: paths,
        permissions: VaultPermissions.defaults,
        requested: 'notes/a.md, notes/missing.md, notes/long.md',
      );

      expect(slice, contains('Widget list.'));
      expect(slice, contains('notes/missing.md: unavailable'));
      expect(slice, contains('(shortened)'));
      expect(
        slice.length,
        lessThan(DelegationLimits.maxSliceCharacters + 200),
        reason: 'the slice stays inside its own cap',
      );
    });

    test('never reaches outside the project folder', () async {
      File('${root.path}/outside.md').writeAsStringSync('secret');

      final slice = await const DelegationRunner().readSlice(
        paths: paths,
        permissions: VaultPermissions.defaults,
        requested: '../outside.md',
      );

      expect(slice, contains('unavailable'));
      expect(slice, isNot(contains('secret')));
    });

    test('takes at most three files', () async {
      for (var index = 0; index < 5; index++) {
        File(
          '${root.path}/Project/notes/$index.md',
        ).writeAsStringSync('file $index');
      }

      final slice = await const DelegationRunner().readSlice(
        paths: paths,
        permissions: VaultPermissions.defaults,
        requested: 'notes/0.md, notes/1.md, notes/2.md, notes/3.md, notes/4.md',
      );

      expect(slice, contains('file 2'));
      expect(slice, isNot(contains('file 3')));
    });
  });

  group('running the child', () {
    test(
      'hands the parent the answer and the numbers, not the context',
      () async {
        final runtime = ScriptedAgentRuntime(
          script: ['Widgets are in notes/a.'],
        );
        final runner = DelegationRunner(
          loop: AgentLoopServiceForTest(runtime).loop,
        );

        final delegation = await runner.run(
          target: _bot('two', 'Research bot'),
          task: 'Where are the widgets?',
          model: _model,
          registry: ToolRegistry(
            tools: [_tool('calculator', ToolRiskLevel.safe)],
            platform: ToolPlatform.linux,
          ),
          budget: ContextBudget.auto,
          systemPrompt: 'CHILD PROMPT with the child soul',
        );

        expect(delegation.status, AgentRunStatus.completed);
        expect(delegation.answer, 'Widgets are in notes/a.');
        expect(runtime.prompts.single, contains('CHILD PROMPT'));

        final observation = delegation.toObservation();
        expect(observation, contains('Research bot'));
        expect(observation, contains('Widgets are in notes/a.'));
        expect(
          observation,
          isNot(contains('CHILD PROMPT')),
          reason: 'the parent never receives the child’s prompt',
        );
      },
    );

    test('caps the child at the delegation iteration limit', () async {
      final runtime = ScriptedAgentRuntime(
        script: List<String>.filled(
          12,
          '{"type":"tool_call","tool":"calculator","arguments":{}}',
        ),
      );
      final runner = DelegationRunner(
        loop: AgentLoopServiceForTest(runtime).loop,
      );

      final delegation = await runner.run(
        target: _bot('two', 'Research bot'),
        task: 'Keep counting.',
        model: _model,
        registry: ToolRegistry(
          tools: [_tool('calculator', ToolRiskLevel.safe)],
          platform: ToolPlatform.linux,
        ),
        budget: ContextBudget.auto,
        systemPrompt: 'child',
        maxIterations: 99,
      );

      expect(
        runtime.generateCalls,
        lessThanOrEqualTo(DelegationLimits.maxIterations),
        reason: 'a caller cannot raise the ceiling',
      );
      expect(delegation.iterations, lessThanOrEqualTo(4));
    });

    test('an empty task is refused rather than run', () async {
      final runtime = ScriptedAgentRuntime();
      final runner = DelegationRunner(
        loop: AgentLoopServiceForTest(runtime).loop,
      );

      final delegation = await runner.run(
        target: _bot('two', 'Research bot'),
        task: '   ',
        model: _model,
        registry: ToolRegistry(tools: [], platform: ToolPlatform.linux),
        budget: ContextBudget.auto,
        systemPrompt: 'child',
      );

      expect(delegation.status, AgentRunStatus.failed);
      expect(delegation.errorMessage, contains('no task'));
      expect(runtime.generateCalls, 0);
    });

    test('a failing child is reported, not thrown at the parent', () async {
      final runtime = ScriptedAgentRuntime(
        failingModelPaths: const ['/test.gguf'],
      );
      final runner = DelegationRunner(
        loop: AgentLoopServiceForTest(runtime).loop,
      );

      final delegation = await runner.run(
        target: _bot('two', 'Research bot'),
        task: 'Find the widgets.',
        model: _model,
        registry: ToolRegistry(tools: [], platform: ToolPlatform.linux),
        budget: ContextBudget.auto,
        systemPrompt: 'child',
      );

      expect(delegation.status, AgentRunStatus.failed);
      expect(delegation.toObservation(), contains('could not answer'));
    });
  });

  group('the tool itself', () {
    test(
      'runs the child on its own soul and returns only its answer',
      () async {
        final runtime = ScriptedAgentRuntime(
          script: ['The widgets are in notes/a.md.'],
        );
        final parentRegistry = ToolRegistry(
          tools: [
            _tool('calculator', ToolRiskLevel.safe),
            _tool('vault_write_note', ToolRiskLevel.sensitive),
          ],
          platform: ToolPlatform.linux,
        );
        final parent = _bot('one', 'One', soul: 'PARENT SOUL: plan the work.');
        final child = _bot(
          'two',
          'Research bot',
          soul: 'CHILD SOUL: read notes.',
        );
        final tool = buildDelegationTool(
          actor: parent,
          members: [child],
          model: _model,
          budget: ContextBudget.auto,
          registry: parentRegistry,
          runner: DelegationRunner(loop: AgentLoopServiceForTest(runtime).loop),
          readSlice: (requested) async =>
              '--- notes/a.md\nWidgets live in a.md.',
        );

        final result = await tool.handler(const {
          'bot': 'Research bot',
          'task': 'Which note lists the widgets?',
          'files': 'notes/a.md',
        });

        expect(result, contains('The widgets are in notes/a.md.'));
        expect(result, contains('Research bot'));
        final childPrompt = runtime.prompts.single;
        expect(childPrompt, contains('CHILD SOUL: read notes.'));
        expect(childPrompt, contains('Which note lists the widgets?'));
        expect(childPrompt, contains('Widgets live in a.md.'));
        expect(
          childPrompt,
          isNot(contains('PARENT SOUL')),
          reason: 'the child is told its own soul, not the asking bot’s',
        );
      },
    );

    test('names the bots that do exist when the target does not', () async {
      final runtime = ScriptedAgentRuntime();
      final tool = buildDelegationTool(
        actor: _bot('one', 'One'),
        members: [_bot('two', 'Research bot')],
        model: _model,
        budget: ContextBudget.auto,
        registry: ToolRegistry(tools: [], platform: ToolPlatform.linux),
        runner: DelegationRunner(loop: AgentLoopServiceForTest(runtime).loop),
        readSlice: (requested) async => '',
      );

      final result = await tool.handler(const {
        'bot': 'Nobody',
        'task': 'Find something.',
      });

      expect(result, contains('No bot in this chat is called “Nobody”'));
      expect(result, contains('Research bot'));
      expect(runtime.generateCalls, 0);
    });

    test('refuses to delegate to itself', () async {
      final runtime = ScriptedAgentRuntime();
      final actor = _bot('one', 'One');
      final tool = buildDelegationTool(
        actor: actor,
        members: [actor, _bot('two', 'Research bot')],
        model: _model,
        budget: ContextBudget.auto,
        registry: ToolRegistry(tools: [], platform: ToolPlatform.linux),
        runner: DelegationRunner(loop: AgentLoopServiceForTest(runtime).loop),
        readSlice: (requested) async => '',
      );
      final call = ToolCall(
        toolName: delegationToolName,
        arguments: const {'bot': 'One', 'task': 'Find something.'},
      );

      final result = await tool.handler(call.arguments);

      expect(result, contains('cannot delegate to yourself'));
      expect(runtime.generateCalls, 0);
    });
  });
}

/// Builds the loop the tests drive, so delegation is exercised through the real
/// agent loop rather than a hand-written stand-in.
class AgentLoopServiceForTest {
  AgentLoopServiceForTest(AgentRuntime runtime)
    : loop = AgentLoopService(
        runtime: runtime,
        resolveModelPath: (_) async => '/test.gguf',
        isFileReady: (_) async => true,
      );

  final AgentLoopService loop;
}
