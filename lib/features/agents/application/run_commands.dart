import 'package:installm/core/widgets/composer_command_picker.dart';
import 'package:installm/features/agents/domain/run_checkpoint.dart';

/// `/rewind` — undoing the files an agent run wrote (Road Map 3 Phase 3.3.3).
///
/// The command is deliberately two steps: listing shows the runs of this chat
/// and the exact command that puts one back, so a restore is never a guess
/// about which run the user meant. `last` is the one-word shortcut for the
/// newest run, because that is what people mean most of the time.
class RewindCommand {
  const RewindCommand({this.runId, this.list = false, this.message});

  /// Run to put back; null when [list] is true.
  final String? runId;

  /// True for `/rewind` and `/rewind list`.
  final bool list;

  /// Text to show instead of running anything (usage, or an unknown run).
  final String? message;

  static const String usage =
      'Rewind the files an agent run wrote:\n'
      '/rewind — list the runs of this chat with what each one wrote\n'
      '/rewind last — put back the newest run\n'
      '/rewind <run id> — put back that run\n'
      'Only files this app wrote are affected, nothing is touched that '
      'changed after the run, and the conversation stays.';

  /// The command for the composer's suggestion list.
  static ComposerCommand option() =>
      (command: '/rewind', description: 'Undo the files an agent run wrote');

  /// Parses [text] as a rewind command, or null when it is something else.
  static RewindCommand? parse(String text) {
    final trimmed = text.trim();
    final lower = trimmed.toLowerCase();
    if (lower != '/rewind' && !lower.startsWith('/rewind ')) return null;
    final rest = trimmed.length <= 7 ? '' : trimmed.substring(7).trim();
    if (rest.isEmpty || rest.toLowerCase() == 'list') {
      return const RewindCommand(list: true);
    }
    if (rest.contains(RegExp(r'\s'))) {
      return const RewindCommand(message: usage);
    }
    if (rest.toLowerCase() == 'last') {
      return const RewindCommand(runId: 'last');
    }
    return RewindCommand(runId: rest);
  }
}

/// The listing `/rewind` shows: what ran here, and how to put it back.
String rewindListing(List<RunCheckpoint> runs) {
  if (runs.isEmpty) {
    return 'No agent run in this chat has written a file yet. Snapshots start '
        'with the first write of a run and stay on this device.';
  }
  final buffer = StringBuffer(
    'Agent runs that wrote files here (newest first):',
  );
  for (final run in runs.take(10)) {
    buffer
      ..writeln()
      ..writeln(
        '- ${run.id} · ${run.label} · ${_clock(run.startedAt)} · '
        '${run.entries.length} file${run.entries.length == 1 ? '' : 's'}'
        '${run.isRestorable ? '' : ' · cannot be rewound as a whole'}',
      )
      ..writeln(
        '  ${run.entries.map((entry) => entry.relativePath).join(', ')}',
      )
      ..write('  /rewind ${run.id}');
  }
  return buffer.toString();
}

String _clock(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}
