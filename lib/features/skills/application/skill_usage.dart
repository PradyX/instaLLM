import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/skills/application/skill_session.dart';

/// Estimates for the last prompt actually sent, not a persisted content log.
class SkillUsage {
  const SkillUsage({
    required this.instructions,
    required this.resources,
    required this.scriptResults,
    required this.inputTokens,
    required this.reservedOutput,
    required this.window,
  });
  factory SkillUsage.capture(
    SkillSession? session, {
    required int input,
    required int reserved,
    required int window,
  }) => SkillUsage(
    instructions: session?.bodyTokens ?? 0,
    resources: session?.resourceTokens ?? 0,
    scriptResults: session?.scriptTokens ?? 0,
    inputTokens: input,
    reservedOutput: reserved,
    window: window,
  );
  final int instructions;
  final int resources;
  final int scriptResults;
  final int inputTokens;
  final int reservedOutput;
  final int window;
  int get skills => instructions + resources + scriptResults;
  int get otherInput => math.max(0, inputTokens - skills);
}

final skillUsageProvider =
    NotifierProvider<SkillUsageNotifier, Map<String, SkillUsage>>(
      SkillUsageNotifier.new,
    );

/// The last prompt's token split, keyed by conversation or room.
///
/// Recorded after a turn is assembled so the Context screen can show what the
/// skills share of the prompt actually cost.
class SkillUsageNotifier extends Notifier<Map<String, SkillUsage>> {
  @override
  Map<String, SkillUsage> build() => const {};

  void replace(Map<String, SkillUsage> usage) => state = usage;
}
