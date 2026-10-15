import 'package:installm/features/agents/domain/run_checkpoint.dart';
import 'package:installm/features/vault/application/vault_notes_service.dart';
import 'package:installm/features/vault/domain/vault_paths.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';

/// What one rewind did, and the sentence the chat shows for it.
class RewindOutcome {
  const RewindOutcome({
    required this.restored,
    required this.message,
    this.restoredPaths = const [],
  });

  /// True only when every file of the run was put back.
  final bool restored;

  final String message;

  final List<String> restoredPaths;
}

/// What a rewind may do, as the person typing `/rewind` rather than as a bot.
///
/// The stored workspace-link permissions say what bots may do — they keep
/// `canDelete` false so an agent cannot remove the user's notes. A rewind is
/// the user's own action, exactly like deleting a note in the Vault screen, so
/// it uses the same set that screen does. Containment and conflict checks are
/// unchanged: only the run's own files, and only while each still holds what
/// the run wrote.
const VaultPermissions rewindPermissions = VaultPermissions(canDelete: true);

/// Puts the files one agent run wrote back the way they were.
///
/// Every write goes through [VaultNotesService], the same service the editor
/// and the bots use, so containment, the workspace link's permissions and the
/// conflict checks are the same ones — a rewind is not a second, unchecked way
/// into the folder. Nothing else is touched: only the paths this run wrote, and
/// only when each still holds exactly what the run left.
class RewindService {
  const RewindService();

  static const VaultNotesService _notes = VaultNotesService();

  Future<RewindOutcome> rewind({
    required RunCheckpoint run,
    required VaultPaths paths,
    VaultPermissions permissions = rewindPermissions,
  }) async {
    if (run.entries.isEmpty) {
      return const RewindOutcome(
        restored: false,
        message: 'This run wrote no files, so there is nothing to rewind.',
      );
    }
    final contents = <String, String?>{};
    final unreadable = <String>[];
    for (final entry in run.entries) {
      final (note, error) = await _notes.readNote(
        paths: paths,
        permissions: permissions,
        relativePath: entry.relativePath,
      );
      if (error == VaultNoteError.notFound) {
        contents[entry.path] = null;
        continue;
      }
      if (error != null) {
        unreadable.add('${entry.relativePath}: ${error.message}');
        continue;
      }
      contents[entry.path] = note?.content;
    }
    if (unreadable.isNotEmpty) {
      return RewindOutcome(
        restored: false,
        message:
            'Rewind changed nothing:\n'
            '${unreadable.map((line) => '- $line').join('\n')}',
      );
    }

    final plan = RewindPlanner.plan(
      run: run,
      currentContent: (entry) => contents[entry.path],
    );
    if (!plan.canRun) {
      return RewindOutcome(
        restored: false,
        message:
            'Rewind kept every file as it is:\n'
            '${plan.refusals.map((line) => '- $line').join('\n')}',
      );
    }

    final restored = <String>[];
    final failed = <String>[];
    for (final step in plan.steps) {
      final error = step.remove
          ? await _notes.deleteNote(
              paths: paths,
              permissions: permissions,
              relativePath: step.entry.relativePath,
              expectedContent: contents[step.entry.path],
            )
          : await _notes.writeNote(
              paths: paths,
              permissions: permissions,
              relativePath: step.entry.relativePath,
              content: step.entry.beforeContent ?? '',
              expectedContent: contents[step.entry.path],
            );
      if (error == null) {
        restored.add(
          step.remove
              ? '${step.entry.relativePath} (removed)'
              : step.entry.relativePath,
        );
        continue;
      }
      failed.add(
        step.remove && error == VaultNoteError.denied
            ? '${step.entry.relativePath}: this run created that file, so '
                  'removing it needs Delete permission for this workspace link.'
            : '${step.entry.relativePath}: ${error.message}',
      );
    }

    if (failed.isNotEmpty) {
      return RewindOutcome(
        restored: false,
        message:
            'Rewind stopped part-way:\n'
            '${failed.map((line) => '- $line').join('\n')}\n'
            'Put back so far: ${restored.isEmpty ? 'nothing' : restored.join(', ')}',
        restoredPaths: restored,
      );
    }

    return RewindOutcome(
      restored: true,
      message:
          'Rewind put back ${restored.length} '
          '${restored.length == 1 ? 'file' : 'files'} from the run '
          '“${run.label}”:\n'
          '${restored.map((path) => '- $path').join('\n')}\n'
          'The conversation is unchanged, and Git remains the durable undo.',
      restoredPaths: restored,
    );
  }
}
