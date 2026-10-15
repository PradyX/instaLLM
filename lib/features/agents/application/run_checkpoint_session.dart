import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/utils/logger.dart';
import 'package:installm/features/agents/data/run_checkpoint_store.dart';
import 'package:installm/features/agents/domain/run_checkpoint.dart';

/// Checkpoint file, opened once per session.
final runCheckpointStoreProvider = FutureProvider<RunCheckpointStore>(
  (ref) => RunCheckpointStore.open(),
);

/// Records what one agent run writes, so the run can be put back
/// (Road Map 3 Phase 3.3.3).
///
/// The recorder is told about a file *before* a write and again after it. A
/// run that writes nothing never appears in the store: only a write that
/// really happened creates an entry, so `/rewind` never offers to undo
/// something that did not occur. The first write to a file keeps the content
/// from before the run; the last write decides the fingerprint a rewind checks
/// the file against.
class RunCheckpointSession {
  RunCheckpointSession({
    required RunCheckpointStore store,
    required this.contextKey,
    required this.label,
    String? id,
    DateTime? startedAt,
  }) : _store = store,
       id = id ?? 'run-${(startedAt ?? DateTime.now()).microsecondsSinceEpoch}',
       startedAt = startedAt ?? DateTime.now();

  final RunCheckpointStore _store;
  final String id;

  /// The chat or room this run belongs to.
  final String contextKey;

  /// Who ran it, shown in the rewind listing.
  final String label;

  final DateTime startedAt;

  /// Content each file held before this run first wrote it, by absolute path.
  /// A null value means the file did not exist.
  final Map<String, String?> _before = {};

  /// Relative path of each touched file, by absolute path.
  final Map<String, String> _relative = {};

  RunCheckpointsSnapshot? _snapshot;
  bool _recorded = false;

  /// True once the store refused a write, so this run no longer records.
  bool _unusable = false;

  bool get isUsable => !_unusable;

  /// True once a write has been recorded, so the run exists in the store.
  bool get hasRecordedWrites => _recorded;

  /// Remembers what [path] holds before the run writes it. Once per file, so a
  /// second write in the same run keeps the original version.
  void recordBefore({
    required String path,
    required String relativePath,
    required String? content,
  }) {
    if (_before.containsKey(path)) return;
    _before[path] = content;
    _relative[path] = relativePath;
  }

  /// Records a write that happened, creating the run on the first one.
  ///
  /// [content] is what the run wrote; the file is read back by the caller when
  /// it needs the exact text, but the fingerprint here is the run's own intent,
  /// which is what makes a later edit detectable.
  Future<void> recordAfter({
    required String path,
    required String relativePath,
    required String content,
  }) async {
    if (_unusable) return;
    _recorded = true;
    _before.putIfAbsent(path, () => null);
    _relative[path] = relativePath;
    final beforeContent = _before[path];
    final entry = RunCheckpointEntry(
      relativePath: relativePath,
      path: path,
      beforeExists: beforeContent != null,
      beforeContent: beforeContent,
      beforeHash: beforeContent == null
          ? runCheckpointHash('')
          : runCheckpointHash(beforeContent),
      afterHash: runCheckpointHash(content),
      writtenAt: DateTime.now(),
      blocked: _blockedReason(
        beforeContent: beforeContent,
        isNewEntry: !(_snapshot?.byId(id)?.hasPath(path) ?? false),
      ),
    );
    final snapshot = await _loadOnce();
    final run =
        snapshot.byId(id) ??
        RunCheckpoint(
          id: id,
          contextKey: contextKey,
          label: label,
          startedAt: startedAt,
          entries: const [],
        );
    final updated = snapshot.upsert(run.withEntry(entry)).bounded();
    _snapshot = updated;
    if (!_store.save(updated)) {
      _unusable = true;
      AppLogger.warning(
        'Run checkpoints could not be saved, so this run cannot be rewound.',
      );
    }
  }

  /// Why this file cannot be put back, when a snapshot was not kept.
  String? _blockedReason({
    required String? beforeContent,
    required bool isNewEntry,
  }) {
    if (isNewEntry && _before.length > RunCheckpointLimits.maxEntriesPerRun) {
      return 'this run wrote more than '
          '${RunCheckpointLimits.maxEntriesPerRun} files, so it cannot be '
          'rewound as a whole.';
    }
    if (beforeContent != null &&
        beforeContent.length > RunCheckpointLimits.maxContentBytes) {
      return 'the file held more than '
          '${RunCheckpointLimits.maxContentBytes ~/ 1024} KB before this run, '
          'which is not kept.';
    }
    return null;
  }

  Future<RunCheckpointsSnapshot> _loadOnce() async =>
      _snapshot ??= _store.load().bounded();
}
