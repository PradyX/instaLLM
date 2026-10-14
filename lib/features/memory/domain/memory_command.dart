import 'package:installm/features/memory/domain/memory_fact.dart';

/// Only a standalone user command is handled, never model output, quoted
/// document text or a mention buried in a longer request. A colon makes a
/// scope override unambiguous; "remember global warming" is a local fact.
class MemoryCommand {
  const MemoryCommand({
    required this.forget,
    required this.scope,
    required this.text,
  });
  final bool forget;
  final MemoryScope scope;
  final String text;

  static MemoryCommand? parse(String input) {
    final match = RegExp(
      r'^(remember|forget)(?:\s+(in (?:this )?(?:workspace|chat)|globally)\s*:|\s*:|\s+)\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(input.trim());
    if (match == null) return null;
    final qualifier = match.group(2)?.toLowerCase();
    return MemoryCommand(
      forget: match.group(1)!.toLowerCase() == 'forget',
      scope: qualifier == 'globally'
          ? MemoryScope.global
          : qualifier?.contains('workspace') == true
          ? MemoryScope.workspace
          : MemoryScope.conversation,
      text: match.group(3)!.trim(),
    );
  }
}
