import 'package:installm/features/agents/application/delegation_service.dart';
import 'package:installm/features/agents/domain/delegation.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/context/domain/context_budget.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/tools/application/tool_registry.dart';
import 'package:installm/features/tools/domain/tool_definition.dart';

/// The name the delegation tool is declared and removed under.
const String delegationToolName = 'delegate_task';

/// Lets a bot hand one task to another bot in the same chat.
///
/// Built per turn, because the envelope is per turn: [members] are the *other*
/// bots of the room, [registry] is the registry the asking bot runs with, and
/// the child gets a narrowed copy of it — read-only tools only, and the
/// delegation tool itself removed, so a child cannot delegate again. The task
/// and any files the asking bot names are the whole of what the child sees; the
/// room's conversation is never part of a delegation.
ToolEntry buildDelegationTool({
  required Bot actor,
  required List<Bot> members,
  required LlmModel model,
  required ContextBudget budget,
  required ToolRegistry registry,
  required DelegationRunner runner,
  required Future<String> Function(String requestedPaths) readSlice,
  String assistantPrefill = '',
}) {
  final names = members.map((bot) => bot.name).join(', ');
  return ToolEntry(
    definition: ToolDefinition(
      name: delegationToolName,
      description:
          'Ask one other bot in this chat to work on part of the task and '
          'return only its findings. The other bot sees the task you write and '
          'any files you name — never this chat’s conversation. Bots you can '
          'ask: $names.',
      risk: ToolRiskLevel.readOnly,
      // A delegated run is a model generation of its own, so the ordinary
      // tool timeout would cut it off mid-answer.
      timeout: DelegationLimits.timeout,
      parameters: [
        const ToolParameter(
          name: 'bot',
          type: ToolParameterType.string,
          description: 'Name or id of the bot to ask.',
          maxLength: 80,
        ),
        const ToolParameter(
          name: 'task',
          type: ToolParameterType.string,
          description:
              'Exactly what that bot should find out or work out, in one '
              'task. It cannot see your conversation, so state the facts it '
              'needs.',
          maxLength: DelegationLimits.maxTaskCharacters,
        ),
        const ToolParameter(
          name: 'files',
          type: ToolParameterType.string,
          description:
              'Optional. Up to three notes to pass along, as workspace paths '
              'separated by commas, e.g. notes/a.md, notes/b.md.',
          required: false,
          maxLength: 400,
        ),
      ],
    ),
    handler: (arguments) async {
      final requested = (arguments['bot'] as String).trim();
      final task = (arguments['task'] as String).trim();
      final target = delegatedTarget(members: members, requested: requested);
      if (target == null) {
        return members.isEmpty
            ? 'No other bot is a member of this chat, so there is nobody to '
                  'delegate to.'
            : 'No bot in this chat is called “$requested”. Members: $names.';
      }
      if (target.id == actor.id) {
        return 'You cannot delegate to yourself. Members you can ask: $names.';
      }
      if (task.isEmpty) {
        return 'Describe what ${target.name} should find out, in one task.';
      }
      final files = (arguments['files'] as String? ?? '').trim();
      final slice = files.isEmpty ? '' : await readSlice(files);
      final prompt = runner.promptFor(
        target: target,
        task: task,
        parentName: actor.name,
        fileSlice: slice,
      );
      final delegation = await runner.run(
        target: target,
        task: task,
        model: model,
        // The child's envelope: what reads, minus the power to delegate again.
        registry: registry.readOnlyOnly().without(const [delegationToolName]),
        budget: budget,
        systemPrompt: prompt,
        assistantPrefill: assistantPrefill,
        parentName: actor.name,
      );
      return delegation.toObservation();
    },
  );
}
