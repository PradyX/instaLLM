import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Limits that keep one run's snapshots bounded (Road Map 3 Phase 3.3.3).
///
/// Snapshots are a convenience undo, not a backup: Git stays the durable one,
/// so the newest runs are kept whole and the oldest go first rather than the
/// store growing without limit.
abstract final class RunCheckpointLimits {
  /// Newest runs kept in the store.
  static const int maxRuns = 20;

  /// Files one run may snapshot; a run that touches more cannot be rewound.
  static const int maxEntriesPerRun = 40;

  /// Largest file content kept, in characters.
  static const int maxContentBytes = 256 * 1024;

  /// Total content the whole store keeps, in characters.
  static const int maxTotalBytes = 8 * 1024 * 1024;
}

/// SHA-256 of [text], the same fingerprint the journal ownership store uses.
String runCheckpointHash(String text) =>
    sha256.convert(utf8.encode(text)).toString();

/// First eight characters of a hash, for a message a person reads.
String shortRunCheckpointHash(String hash) =>
    hash.length <= 8 ? hash : hash.substring(0, 8);

/// What one run recorded about one file.
///
/// A snapshot is only useful with both halves: the content the file had before
/// the run wrote it and the fingerprint of what the run left behind, which is
/// what tells a rewind whether anyone touched the file since.
class RunCheckpointEntry {
  const RunCheckpointEntry({
    required this.relativePath,
    required this.path,
    required this.beforeExists,
    this.beforeContent,
    required this.beforeHash,
    required this.afterHash,
    required this.writtenAt,
    this.blocked,
  });

  /// Path inside the linked project folder — what a rewind writes through, so
  /// permissions and containment are checked the same way as any other note.
  final String relativePath;

  /// Absolute path the run wrote, for showing the user where the file is.
  final String path;

  /// False when the run created the file, so a rewind removes it.
  final bool beforeExists;

  /// The file's content before the run, or null when it did not exist (and when
  /// it existed but was too large to keep).
  final String? beforeContent;

  final String beforeHash;

  /// Fingerprint of what the run wrote last.
  final String afterHash;

  final DateTime writtenAt;

  /// Why this file cannot be put back, or null when it can.
  final String? blocked;

  /// True when this file carries a complete snapshot.
  bool get isRestorable =>
      blocked == null &&
      beforeHash.isNotEmpty &&
      afterHash.isNotEmpty &&
      (!beforeExists || beforeContent != null);

  /// True when the run created this file, so putting it back means removing it.
  bool get removesFile => !beforeExists;

  Map<String, Object?> toJson() {
    return {
      'relativePath': relativePath,
      'path': path,
      'beforeExists': beforeExists,
      'beforeContent': beforeContent,
      'beforeHash': beforeHash,
      'afterHash': afterHash,
      'writtenAt': writtenAt.toIso8601String(),
      'blocked': blocked,
    };
  }

  /// Reads one stored entry. Null when the entry cannot be an entry of this
  /// build, so the store keeps the original file instead of rewriting it away.
  static RunCheckpointEntry? fromJson(Map<String, dynamic> json) {
    final relativePath = json['relativePath'];
    final path = json['path'];
    if (relativePath is! String || relativePath.isEmpty || path is! String) {
      return null;
    }
    final beforeContent = json['beforeContent'];
    if (beforeContent != null && beforeContent is! String) return null;
    final writtenAt = json['writtenAt'];
    return RunCheckpointEntry(
      relativePath: relativePath,
      path: path,
      beforeExists: json['beforeExists'] is bool
          ? json['beforeExists'] as bool
          : false,
      beforeContent: beforeContent as String?,
      beforeHash: json['beforeHash'] is String
          ? json['beforeHash'] as String
          : '',
      afterHash: json['afterHash'] is String ? json['afterHash'] as String : '',
      writtenAt: writtenAt is String
          ? DateTime.tryParse(writtenAt) ??
                DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.fromMillisecondsSinceEpoch(0),
      blocked: json['blocked'] is String ? json['blocked'] as String : null,
    );
  }
}

/// The files one run wrote, and enough of their earlier state to put them back.
class RunCheckpoint {
  const RunCheckpoint({
    required this.id,
    required this.contextKey,
    required this.label,
    required this.startedAt,
    required this.entries,
  });

  /// Stable id the user types after `/rewind`.
  final String id;

  /// The chat or room this run belongs to, so a rewind only ever offers the
  /// runs of the conversation the user is looking at.
  final String contextKey;

  /// Who ran it, for the listing (`One · room Docs`).
  final String label;

  final DateTime startedAt;

  /// Files the run wrote, in the order it wrote them.
  final List<RunCheckpointEntry> entries;

  bool get isEmpty => entries.isEmpty;

  /// True when every file of this run carries a complete snapshot.
  bool get isRestorable =>
      entries.isNotEmpty && entries.every((entry) => entry.isRestorable);

  /// Characters this run keeps.
  int get contentBytes => entries.fold(
    0,
    (total, entry) => total + (entry.beforeContent?.length ?? 0),
  );

  /// True when this file is already recorded in this run.
  bool hasPath(String path) => entries.any((entry) => entry.path == path);

  /// Adds or replaces one file's record, keeping the order it was first seen.
  RunCheckpoint withEntry(RunCheckpointEntry entry) {
    final updated = <RunCheckpointEntry>[];
    var replaced = false;
    for (final existing in entries) {
      if (existing.path == entry.path) {
        updated.add(entry);
        replaced = true;
      } else {
        updated.add(existing);
      }
    }
    if (!replaced) updated.add(entry);
    return RunCheckpoint(
      id: id,
      contextKey: contextKey,
      label: label,
      startedAt: startedAt,
      entries: updated,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'contextKey': contextKey,
      'label': label,
      'startedAt': startedAt.toIso8601String(),
      'entries': entries.map((entry) => entry.toJson()).toList(),
    };
  }

  static RunCheckpoint? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final contextKey = json['contextKey'];
    if (id is! String || id.isEmpty || contextKey is! String) return null;
    final startedAt = json['startedAt'];
    final raw = json['entries'];
    final entries = <RunCheckpointEntry>[];
    if (raw is List) {
      for (final value in raw) {
        if (value is! Map) continue;
        final entry = RunCheckpointEntry.fromJson(
          Map<String, dynamic>.from(value),
        );
        if (entry != null) entries.add(entry);
      }
    }
    return RunCheckpoint(
      id: id,
      contextKey: contextKey,
      label: json['label'] is String ? json['label'] as String : '',
      startedAt: startedAt is String
          ? DateTime.tryParse(startedAt) ??
                DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.fromMillisecondsSinceEpoch(0),
      entries: entries,
    );
  }
}

/// One thing a rewind does to one file.
class RewindStep {
  const RewindStep.restore(this.entry) : remove = false;
  const RewindStep.remove(this.entry) : remove = true;

  final RunCheckpointEntry entry;

  /// True when putting the file back means removing it, because the run
  /// created it.
  final bool remove;
}

/// What a rewind would do, or why it will not run at all.
class RewindPlan {
  const RewindPlan({required this.steps, required this.refusals});

  /// Empty unless the whole run can be put back: a half-restored folder is
  /// worse than a refusal that names the files it could not touch.
  final List<RewindStep> steps;

  final List<String> refusals;

  bool get canRun => steps.isNotEmpty && refusals.isEmpty;
}

/// Decides a rewind before anything is written.
///
/// All-or-nothing on purpose: a run is put back only when every file still
/// holds exactly what the run wrote, so a file the user has edited since (or
/// deleted) is never overwritten or resurrected behind their back.
abstract final class RewindPlanner {
  static RewindPlan plan({
    required RunCheckpoint run,
    required String? Function(RunCheckpointEntry entry) currentContent,
  }) {
    if (run.entries.isEmpty) {
      return const RewindPlan(
        steps: [],
        refusals: ['This run wrote no files, so there is nothing to rewind.'],
      );
    }
    final refusals = <String>[];
    final steps = <RewindStep>[];
    for (final entry in run.entries) {
      if (entry.blocked != null) {
        refusals.add('${entry.relativePath}: ${entry.blocked}');
        continue;
      }
      if (entry.beforeExists && entry.beforeContent == null) {
        refusals.add(
          '${entry.relativePath}: the version from before this run was not '
          'kept, so it cannot be put back.',
        );
        continue;
      }
      final current = currentContent(entry);
      if (current == null) {
        refusals.add(
          '${entry.relativePath} is gone: it was removed after this run wrote '
          'it, and rewind keeps that.',
        );
        continue;
      }
      final hash = runCheckpointHash(current);
      if (hash != entry.afterHash) {
        refusals.add(
          '${entry.relativePath} changed after this run wrote it (this run '
          'wrote ${shortRunCheckpointHash(entry.afterHash)}, the file now '
          'reads ${shortRunCheckpointHash(hash)}), so rewind keeps the newer '
          'text.',
        );
        continue;
      }
      steps.add(
        entry.removesFile
            ? RewindStep.remove(entry)
            : RewindStep.restore(entry),
      );
    }
    if (refusals.isNotEmpty) {
      return RewindPlan(steps: const [], refusals: refusals);
    }
    return RewindPlan(steps: steps, refusals: const []);
  }
}
