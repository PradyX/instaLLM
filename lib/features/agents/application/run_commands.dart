import 'package:installm/core/widgets/composer_command_picker.dart';
import 'package:installm/features/agents/domain/background_run.dart';
import 'package:installm/features/agents/domain/review_finding.dart';
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

/// `/background` — a task this chat's bot works on while the user is elsewhere.
///
/// Starting, listing and stopping are one command because they are one story:
/// a supervised run the user cannot see, list or stop would be exactly the
/// hidden automation the roadmap rules out.
class BackgroundCommand {
  const BackgroundCommand({
    this.task,
    this.list = false,
    this.stopId,
    this.stopCurrent = false,
    this.message,
  });

  /// Task to run in the background.
  final String? task;

  /// True for `/background` and `/background list`.
  final bool list;

  /// Run to stop, when the user named one.
  final String? stopId;

  /// True for `/background stop`: the run going in this chat.
  final bool stopCurrent;

  /// Text to show instead of running anything.
  final String? message;

  static const String usage =
      'Runs a task here while you are elsewhere:\n'
      '/background <task> — start one with this chat’s bot\n'
      '/background @Bot <task> — start one with a named bot\n'
      '/background list — what this chat has run\n'
      '/background stop [run id] — stop the run going here'
      '\nThe run is an ordinary turn of this chat: same tools, same questions, '
      'same rules. You get one notice when it finishes or needs you.';

  /// The commands for the composer's suggestion list.
  static List<ComposerCommand> options() => [
    (command: '/background', description: 'Run a task while you are elsewhere'),
  ];

  /// Parses [text] as a background-run command, or null for anything else.
  static BackgroundCommand? parse(String text) {
    final trimmed = text.trim();
    final lower = trimmed.toLowerCase();
    final isRun = lower == '/runs' || lower.startsWith('/runs ');
    final isBackground =
        lower == '/background' || lower.startsWith('/background ');
    if (!isRun && !isBackground) return null;
    final rest = isRun
        ? (trimmed.length <= 5 ? '' : trimmed.substring(5).trim())
        : (trimmed.length <= 11 ? '' : trimmed.substring(11).trim());
    if (rest.isEmpty || rest.toLowerCase() == 'list') {
      return const BackgroundCommand(list: true);
    }
    final words = rest.split(RegExp(r'\s+'));
    if (words.first.toLowerCase() == 'stop') {
      if (words.length == 1) return const BackgroundCommand(stopCurrent: true);
      if (words.length == 2) return BackgroundCommand(stopId: words[1]);
      return const BackgroundCommand(message: usage);
    }
    return BackgroundCommand(task: rest);
  }
}

/// The listing `/background` shows: what ran, and where each one stands.
String backgroundRunListing(List<BackgroundRun> runs) {
  if (runs.isEmpty) {
    return 'No supervised run has been started here yet. Start one with '
        '/background <task>.';
  }
  final buffer = StringBuffer('Runs started here (newest first):');
  for (final run in runs.take(10)) {
    buffer
      ..writeln()
      ..write(
        '- ${run.id} · ${run.status.label} · ${run.botName} · '
        '${_clock(run.startedAt)} · ${run.task}',
      );
    if (run.isRunning) {
      buffer.write('\n  /background stop ${run.id}');
    }
  }
  return buffer.toString();
}

/// `/review` — a reviewer's pass over the changes a room made, and the hand-off
/// that puts one finding in front of a bot (Road Map 3 Phase 3.3.4).
///
/// The pass is one ordinary turn of the room it is typed in — same model, same
/// tools, same permissions — so this is a command, not a second agent: what it
/// reviews is the room's own last run, read from the snapshots that run left.
class ReviewCommand {
  const ReviewCommand({
    this.list = false,
    this.fixIndex,
    this.botName,
    this.files = const [],
    this.message,
  });

  /// True for `/review list`: show the last review again.
  final bool list;

  /// Finding to hand to a bot, as numbered in the listing.
  final int? fixIndex;

  /// Bot named after `fix`, when the user chose one.
  final String? botName;

  /// Paths the user named to review, relative to the linked project folder.
  final List<String> files;

  /// Text to show instead of running anything.
  final String? message;

  static const String usage =
      'Reviews the changes this chat made:\n'
      '/review — the files this chat’s last run wrote\n'
      '/review <path> [path…] — files to review as they are now\n'
      '/review list — the last review of this chat\n'
      '/review fix <n> [@Bot] — hand finding n to a bot as a supervised run'
      '\nFindings come back with a severity; fixing one is an ordinary run of '
      'this chat, so it is recorded and cancellable like any other.';

  /// The command for the composer's suggestion list.
  static ComposerCommand option() =>
      (command: '/review', description: 'Review the changes this chat made');

  /// Parses [text] as a review command, or null for anything else.
  ///
  /// Anything carrying a skill flag (`--resource=…`) is left to the skill path:
  /// `/review` was the review skill before it was the review pass, and that
  /// choice still has to work.
  static ReviewCommand? parse(String text) {
    final trimmed = text.trim();
    final lower = trimmed.toLowerCase();
    if (lower != '/review' && !lower.startsWith('/review ')) return null;
    final rest = trimmed.length <= 7 ? '' : trimmed.substring(7).trim();
    if (rest.contains('--')) return null;
    if (rest.isEmpty) return const ReviewCommand();
    if (rest.toLowerCase() == 'list') return const ReviewCommand(list: true);
    final words = rest.split(RegExp(r'\s+'));
    if (words.first.toLowerCase() == 'fix') {
      if (words.length < 2) {
        return const ReviewCommand(message: 'Which finding? /review fix <n>.');
      }
      final index = int.tryParse(words[1].replaceAll(RegExp(r'[^0-9]'), ''));
      if (index == null || index < 1) {
        return ReviewCommand(
          message:
              '“${words[1]}” is not a finding number. ${usage.split('\n').first}',
        );
      }
      final named = words.length > 2 && words[2].startsWith('@')
          ? words[2].substring(1)
          : null;
      return ReviewCommand(fixIndex: index, botName: named);
    }
    if (words.length > ReviewLimits.maxFiles) {
      return ReviewCommand(
        message:
            'Review at most ${ReviewLimits.maxFiles} files at a time; a '
            'review is meant to be read.',
      );
    }
    return ReviewCommand(files: words);
  }
}

String _clock(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}
