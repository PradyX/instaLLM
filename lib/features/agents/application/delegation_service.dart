import 'package:installm/features/agents/application/agent_loop_service.dart';
import 'package:installm/features/agents/domain/agent_run.dart';
import 'package:installm/features/agents/domain/delegation.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/bots/domain/bot_prompt.dart';
import 'package:installm/features/context/domain/context_budget.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/tools/application/tool_registry.dart';
import 'package:installm/features/vault/application/vault_notes_service.dart';
import 'package:installm/features/vault/domain/vault_paths.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';

/// Runs one delegated task on another bot and returns only its answer.
///
/// The child gets a prompt built from its *own* soul, the task and the files
/// the parent named — never the room's conversation, the parent's prompt or its
/// tool results. What comes back is [AgentDelegation.toObservation]: the answer
/// and the numbers that bound the run, so a caller can show what happened
/// without handing the parent a context it never had.
class DelegationRunner {
  const DelegationRunner({this.loop, this.notes = const VaultNotesService()});

  /// The loop a child runs on. Null in a unit test that only builds a prompt.
  final AgentLoopService? loop;

  final VaultNotesService notes;

  /// The instruction a delegated child works under.
  ///
  /// Deliberately blunt about the boundary: the child is asked to answer, and
  /// told that reasoning and tool output are not returned.
  static const String childInstruction =
      'You are answering one task that another bot in this chat delegated to '
      'you. Only your final answer is returned to the bot that asked; your '
      'reasoning, your tool calls and this prompt are not shared with it. Use '
      'the facts you can find here, never invent a result, and say plainly '
      'when something could not be found. Answer in the fewest lines that '
      'carry the facts.';

  /// Builds the child's system prompt: its soul, the instruction, the named
  /// files.
  String promptFor({
    required Bot target,
    required String task,
    String parentName = '',
    String fileSlice = '',
  }) {
    final parts = <String>[
      BotPrompt.assemble(bot: target),
      if (parentName.trim().isNotEmpty) 'Delegated by: ${parentName.trim()}',
      childInstruction,
    ];
    final slice = fileSlice.trim();
    if (slice.isNotEmpty) {
      parts.add('Files that were passed with the task:\n$slice');
    }
    parts.add(BotPrompt.taskSection(task));
    return parts.where((part) => part.trim().isNotEmpty).join('\n\n');
  }

  /// Reads the files a delegation named, bounded and never outside the folder.
  ///
  /// Every path goes through the same vault service the editor uses, so a task
  /// cannot talk a child into reading something the workspace link does not
  /// cover. A file that cannot be read is reported as a line in the slice
  /// rather than failing the delegation.
  Future<String> readSlice({
    required VaultPaths paths,
    required VaultPermissions permissions,
    required String requested,
  }) async {
    final wanted = requested
        .split(',')
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .take(DelegationLimits.maxFiles)
        .toList();
    final parts = <String>[];
    var budget = DelegationLimits.maxSliceCharacters;
    for (final path in wanted) {
      if (budget <= 0) break;
      final (note, error) = await notes.readNote(
        paths: paths,
        permissions: permissions,
        relativePath: path,
      );
      if (error != null || note == null) {
        parts.add('--- $path: unavailable (${error?.message ?? 'empty'})');
        continue;
      }
      var content = note.content;
      if (content.length > DelegationLimits.maxFileCharacters) {
        content =
            '${content.substring(0, DelegationLimits.maxFileCharacters)}\n'
            '(shortened)';
      }
      if (content.length > budget) {
        content = '${content.substring(0, budget)}\n(shortened)';
      }
      budget -= content.length;
      parts.add('--- $path\n$content');
    }
    return parts.join('\n\n');
  }

  /// Runs the child and returns what it answered.
  ///
  /// [registry] is the child's own envelope, already narrowed by the caller;
  /// [maxIterations] can only lower the ceiling, never raise it.
  Future<AgentDelegation> run({
    required Bot target,
    required String task,
    required LlmModel model,
    required ToolRegistry registry,
    required ContextBudget budget,
    required String systemPrompt,
    String assistantPrefill = '',
    int maxIterations = DelegationLimits.maxIterations,
    String parentName = '',
    DateTime? startedAt,
  }) async {
    final started = startedAt ?? DateTime.now();
    final trimmedTask = task.trim();
    if (trimmedTask.isEmpty) {
      return AgentDelegation(
        targetBotId: target.id,
        targetName: target.name,
        task: trimmedTask,
        status: AgentRunStatus.failed,
        answer: '',
        iterations: 0,
        toolCallCount: 0,
        promptCharacters: systemPrompt.length,
        startedAt: started,
        finishedAt: DateTime.now(),
        errorMessage: 'there was no task to delegate.',
      );
    }
    final loop = this.loop;
    if (loop == null) {
      throw StateError('A delegated run needs the agent loop.');
    }
    // The child is told how to call the read-only tools it was given, and only
    // those: the contract comes from its own narrowed registry, so the tool it
    // must never use is not even named.
    final contract = registry.describeForPrompt();
    final effectivePrompt = contract.isEmpty
        ? systemPrompt
        : '$systemPrompt\n\n$contract';
    AgentRun run;
    try {
      run = await loop.run(
        model: model,
        goal: trimmedTask,
        registry: registry,
        maxIterations: maxIterations.clamp(1, DelegationLimits.maxIterations),
        budget: budget,
        systemPrompt: effectivePrompt,
        assistantPrefill: assistantPrefill,
      );
    } catch (error) {
      return AgentDelegation(
        targetBotId: target.id,
        targetName: target.name,
        task: trimmedTask,
        status: AgentRunStatus.failed,
        answer: '',
        iterations: 0,
        toolCallCount: 0,
        promptCharacters: systemPrompt.length,
        startedAt: started,
        finishedAt: DateTime.now(),
        errorMessage: '$error',
      );
    }
    var answer = run.answer.trim();
    var truncated = false;
    if (answer.length > DelegationLimits.maxAnswerCharacters) {
      answer = answer.substring(0, DelegationLimits.maxAnswerCharacters);
      truncated = true;
    }
    return AgentDelegation(
      targetBotId: target.id,
      targetName: target.name,
      task: trimmedTask,
      status: run.status,
      answer: answer,
      iterations: run.iterations,
      toolCallCount: run.toolCallCount,
      promptCharacters: effectivePrompt.length,
      startedAt: started,
      finishedAt: run.finishedAt ?? DateTime.now(),
      errorMessage: run.errorMessage,
      truncated: truncated,
    );
  }
}

/// Finds the bot a delegation names, by id or by name as it is written.
///
/// Returns null when nothing matches, so the caller can list the bots that do
/// instead of guessing which one was meant.
Bot? delegatedTarget({required List<Bot> members, required String requested}) {
  final wanted = requested.trim().toLowerCase();
  if (wanted.isEmpty) return null;
  for (final bot in members) {
    if (bot.id.toLowerCase() == wanted) return bot;
  }
  for (final bot in members) {
    if (bot.name.toLowerCase() == wanted) return bot;
  }
  return null;
}
