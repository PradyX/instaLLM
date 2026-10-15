import 'package:installm/features/agents/domain/agent_run.dart';

/// Limits that keep a delegated run smaller than the run that asked for it
/// (Road Map 3 Phase 3.3.1).
///
/// A delegation is a hand-off, not a second opinion: the child gets its own
/// soul, the task and a bounded slice of files, it can read but never write,
/// and it cannot delegate again.
abstract final class DelegationLimits {
  /// How deep a delegation may go. One: a child never delegates.
  static const int maxDepth = 1;

  /// Model turns the child may use.
  static const int maxIterations = 3;

  /// Longest task accepted, so a delegation cannot smuggle a transcript in.
  static const int maxTaskCharacters = 2000;

  /// Files a delegation may name.
  static const int maxFiles = 3;

  /// Characters kept from each named file.
  static const int maxFileCharacters = 8000;

  /// Characters of file text kept in total.
  static const int maxSliceCharacters = 20000;

  /// Characters of the child's answer handed back to the parent.
  static const int maxAnswerCharacters = 4000;

  /// Longest a delegated run may take before the tool call is stopped.
  static const Duration timeout = Duration(minutes: 10);
}

/// One completed hand-off, and the only thing the parent sees of it.
///
/// The child's prompt, its steps and its tool results stay inside the
/// delegation: what comes back is [answer] and the numbers that bound it.
class AgentDelegation {
  const AgentDelegation({
    required this.targetBotId,
    required this.targetName,
    required this.task,
    required this.status,
    required this.answer,
    required this.iterations,
    required this.toolCallCount,
    required this.promptCharacters,
    required this.startedAt,
    this.finishedAt,
    this.errorMessage,
    this.truncated = false,
  });

  final String targetBotId;
  final String targetName;
  final String task;
  final AgentRunStatus status;

  /// The child's own answer, capped at [DelegationLimits.maxAnswerCharacters].
  final String answer;

  final int iterations;
  final int toolCallCount;

  /// Characters of prompt the child was given — a number, never the text.
  final int promptCharacters;

  final DateTime startedAt;
  final DateTime? finishedAt;
  final String? errorMessage;

  /// True when the answer was longer than the limit and was shortened.
  final bool truncated;

  /// What the parent's tool call returns: the answer and how it was reached,
  /// never the child's prompt, steps or context.
  String toObservation() {
    final buffer = StringBuffer()
      ..writeln(
        'Delegated to $targetName · ${status.label} · $iterations '
        'step${iterations == 1 ? '' : 's'} · $toolCallCount tool '
        'call${toolCallCount == 1 ? '' : 's'}',
      );
    if (errorMessage != null) {
      buffer.writeln('The delegated run could not answer: $errorMessage');
    }
    if (answer.trim().isNotEmpty) {
      buffer
        ..writeln('Answer from $targetName:')
        ..write(answer.trim());
      if (truncated) {
        buffer.write(
          '\n(shortened to '
          '${DelegationLimits.maxAnswerCharacters} characters)',
        );
      }
    } else {
      buffer.write('$targetName returned no answer.');
    }
    return buffer.toString().trimRight();
  }
}
