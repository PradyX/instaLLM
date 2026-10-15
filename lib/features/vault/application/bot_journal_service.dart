import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:installm/features/agents/application/run_checkpoint_session.dart';
import 'package:installm/features/conversations/application/conversation_memory_service.dart';
import 'package:installm/features/vault/application/vault_notes_service.dart';
import 'package:installm/features/vault/domain/vault_paths.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';
import 'package:installm/features/tools/application/tool_registry.dart';
import 'package:installm/features/tools/domain/tool_definition.dart';
import 'package:installm/features/vault/data/journal_checkpoint_store.dart';

/// One bot run's pre-generation snapshots. The model supplies only a condensed
/// project summary; no transcript or raw tool output is copied by this service.
class BotJournalSession {
  BotJournalSession._(
    this.paths,
    this.permissions,
    this.summaryPath,
    this.decisionPath,
  );
  final VaultPaths paths;
  final VaultPermissions permissions;
  final String summaryPath;
  final String decisionPath;
  static const _notes = VaultNotesService();
  final Map<String, VaultNote?> _baseline = {};
  final Map<String, bool> _owned = {};
  late final JournalCheckpointStore _checkpoints;
  late final String _contextKey;
  VaultPermissions? Function()? _resolvePermissions;

  /// Records what this run writes, so `/rewind` can put it back. Null when the
  /// caller keeps no snapshots (a platform without the store, for example).
  RunCheckpointSession? _runCheckpoints;
  String _hash(String text) => sha256.convert(utf8.encode(text)).toString();

  static Future<BotJournalSession?> open({
    required VaultPaths paths,
    required VaultPermissions permissions,
    required String botId,
    DateTime? now,
    JournalCheckpointStore? checkpoints,
    RunCheckpointSession? runCheckpoints,
    String? contextKey,
    VaultPermissions? Function()? resolvePermissions,
  }) async {
    if (!permissions.canRead ||
        !permissions.canWrite ||
        !RegExp(r'^[a-zA-Z0-9._-]{1,100}$').hasMatch(botId)) {
      return null;
    }
    final date = (now ?? DateTime.now()).toIso8601String().substring(0, 10);
    final folder = 'bots/bot-$botId';
    final session = BotJournalSession._(
      paths,
      permissions,
      '$folder/summary.md',
      '$folder/decisions/$date.md',
    );
    session._checkpoints = checkpoints ?? await JournalCheckpointStore.open();
    session._contextKey =
        contextKey ?? '${paths.vaultRoot}|${paths.projectPath}';
    session._resolvePermissions = resolvePermissions;
    session._runCheckpoints = runCheckpoints;
    try {
      session._checkpoints.hashFor('${session._contextKey}|readiness');
    } catch (_) {
      return null;
    }
    for (final path in [session.summaryPath, session.decisionPath]) {
      final (note, error) = await _notes.readNote(
        paths: paths,
        permissions: permissions,
        relativePath: path,
      );
      if (error != null && error != VaultNoteError.notFound) return null;
      session._baseline[path] = note;
      try {
        session._owned[path] =
            note == null ||
            session._checkpoints.hashFor('${session._contextKey}|$path') ==
                session._hash(note.content);
      } catch (_) {
        return null;
      }
    }
    return session;
  }

  Future<String> record(String text, {bool decision = false}) async {
    final path = decision ? decisionPath : summaryPath;
    if (_owned[path] != true) {
      return 'Journal not saved: this note was edited by the user or its ownership is unknown. Keep it, or rename it before recording a new summary.';
    }
    return _write(
      path,
      text,
      baseline: _baseline[path],
      createOnly: _baseline[path] == null,
    );
  }

  Future<String> _write(
    String path,
    String text, {
    VaultNote? baseline,
    bool createOnly = true,
  }) async {
    final normalized = const ConversationMemoryService().normalize(text);
    if (normalized == null) {
      return 'No project summary was saved. Provide a brief factual summary without reasoning.';
    }
    final livePermissions = _resolvePermissions == null
        ? permissions
        : _resolvePermissions!();
    if (livePermissions == null) {
      return 'Note not saved: the workspace link or permissions changed.';
    }
    final content = '$normalized\n';
    // What the file held before this run is recorded once, before anything is
    // written; a write that fails leaves no entry behind.
    final absolute = paths.projectFile(path);
    if (absolute != null) {
      _runCheckpoints?.recordBefore(
        path: absolute,
        relativePath: path,
        content: baseline?.content,
      );
    }
    final error = await _notes.writeNote(
      paths: paths,
      permissions: livePermissions,
      relativePath: path,
      content: content,
      expectedModified: baseline?.modified,
      expectedContent: baseline?.content,
      createOnly: createOnly,
    );
    if (error != null) {
      return 'Note not saved: ${error.message} Resolve the edit conflict or permissions before retrying.';
    }
    if (absolute != null) {
      await _runCheckpoints?.recordAfter(
        path: absolute,
        relativePath: path,
        content: content,
      );
    }
    if (_baseline.containsKey(path)) {
      if (!_checkpoints.saveHash('$_contextKey|$path', _hash(content))) {
        return 'Note created, but journal ownership could not be saved. Further updates are blocked to preserve this note.';
      }
      final (note, _) = await _notes.readNote(
        paths: paths,
        permissions: permissions,
        relativePath: path,
      );
      _baseline[path] = note;
      _owned[path] = note != null && _hash(note.content) == _hash(content);
    }
    return 'Saved $path.';
  }

  /// Always permission-gated by the registry, even for another bot's folder.
  /// Snapshot captured by the caller before inference; existing unknown notes
  /// are create-only so a model cannot overwrite an edit it never observed.
  Future<String> writeElsewhere(String path, String text) async {
    if (!path.toLowerCase().endsWith('.md')) {
      return 'Note not saved: choose a Markdown (.md) path.';
    }
    return _write(path, text, createOnly: true);
  }

  List<ToolEntry> tools() => [
    ToolEntry(
      definition: const ToolDefinition(
        name: 'vault_record_summary',
        description:
            'Record a brief project summary or decision in your own bot journal. Use only condensed facts; never transcripts, raw tool output or hidden reasoning.',
        risk: ToolRiskLevel.scopedWrite,
        parameters: [
          ToolParameter(
            name: 'summary',
            type: ToolParameterType.string,
            description: 'Condensed project facts only.',
            maxLength: 12000,
          ),
          ToolParameter(
            name: 'kind',
            type: ToolParameterType.string,
            description: 'Summary or dated decision.',
            required: false,
            allowedValues: ['summary', 'decision'],
          ),
        ],
      ),
      handler: (args) => record(
        args['summary'] as String,
        decision: args['kind'] == 'decision',
      ),
    ),
    ToolEntry(
      definition: const ToolDefinition(
        name: 'vault_write_note',
        description:
            'Create a condensed project note elsewhere in the linked workspace. Always asks permission. Existing notes are preserved and report a conflict.',
        risk: ToolRiskLevel.sensitive,
        // The note path is what a hook protects: declaring it here is what
        // lets a rule refuse one folder without knowing this tool.
        resourceArguments: ['relativePath'],
        parameters: [
          ToolParameter(
            name: 'relativePath',
            type: ToolParameterType.string,
            description: 'Markdown path inside the linked workspace.',
            maxLength: 240,
          ),
          ToolParameter(
            name: 'summary',
            type: ToolParameterType.string,
            description:
                'Condensed project facts only; no transcripts or reasoning.',
            maxLength: 12000,
          ),
        ],
      ),
      handler: (args) => writeElsewhere(
        args['relativePath'] as String,
        args['summary'] as String,
      ),
    ),
  ];
}
