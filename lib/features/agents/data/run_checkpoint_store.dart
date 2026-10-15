import 'dart:convert';
import 'dart:io';

import 'package:installm/features/agents/domain/run_checkpoint.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Versioned store of what agent runs wrote (Road Map 3 Phase 3.3.3).
///
/// The same discipline as the other app-owned stores: a file this build cannot
/// fully understand is backed up before it is rewritten, an entry the decoder
/// drops makes the next save keep the original, a file written by a newer build
/// turns the store read-only instead of being rewritten from what this build
/// happens to know, and a write goes through a temporary file so a failure
/// never leaves a half-written manifest behind.
class RunCheckpointStore {
  RunCheckpointStore(this.file);

  final File file;
  static const int currentVersion = 1;

  /// Every schema this build can read.
  static const List<int> readableVersions = [currentVersion];

  bool _readOnly = false;
  bool _preserve = false;

  bool get isReadOnly => _readOnly;
  String get filePath => file.path;

  static Future<RunCheckpointStore> open() async => RunCheckpointStore(
    File(
      p.join(
        (await getApplicationSupportDirectory()).path,
        'agents',
        'checkpoints.json',
      ),
    ),
  );

  RunCheckpointsSnapshot load() {
    if (!file.existsSync()) return RunCheckpointsSnapshot.empty;
    try {
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map<String, dynamic>) {
        _preserve = true;
        return RunCheckpointsSnapshot.empty;
      }
      final version = raw['version'];
      if (version is! int || !readableVersions.contains(version)) {
        _readOnly = true;
        return RunCheckpointsSnapshot.empty;
      }
      final snapshot = RunCheckpointsSnapshot.fromJson(raw);
      _preserve =
          version != currentVersion ||
          raw['runs'] is! List ||
          jsonEncode(raw['runs']) !=
              jsonEncode(snapshot.runs.map((run) => run.toJson()).toList()) ||
          raw.keys.any((key) => !const {'version', 'runs'}.contains(key));
      return snapshot;
    } on FormatException {
      _preserve = true;
      return RunCheckpointsSnapshot.empty;
    }
  }

  bool save(RunCheckpointsSnapshot snapshot) {
    final temporary = File('${file.path}.tmp');
    try {
      // Re-read so a future-version file introduced after load stays protected.
      load();
      if (_readOnly) return false;
      if (_preserve && file.existsSync()) {
        file.copySync(
          '${file.path}.preserved-${DateTime.now().microsecondsSinceEpoch}',
        );
      }
      file.parent.createSync(recursive: true);
      temporary.writeAsStringSync(
        jsonEncode({
          'version': currentVersion,
          'runs': snapshot.bounded().runs.map((run) => run.toJson()).toList(),
        }),
        flush: true,
      );
      temporary.renameSync(file.path);
      _preserve = false;
      return true;
    } catch (_) {
      return false;
    } finally {
      if (temporary.existsSync()) {
        try {
          temporary.deleteSync();
        } catch (_) {}
      }
    }
  }
}

/// The runs one file holds, newest first.
class RunCheckpointsSnapshot {
  const RunCheckpointsSnapshot({required this.runs});

  static const RunCheckpointsSnapshot empty = RunCheckpointsSnapshot(runs: []);

  final List<RunCheckpoint> runs;

  RunCheckpoint? byId(String runId) {
    for (final run in runs) {
      if (run.id == runId) return run;
    }
    return null;
  }

  /// The runs of one chat or room, newest first.
  List<RunCheckpoint> forContext(String contextKey) => [
    for (final run in runs)
      if (run.contextKey == contextKey) run,
  ];

  /// Adds or replaces one run, keeping the newest first.
  RunCheckpointsSnapshot upsert(RunCheckpoint run) => RunCheckpointsSnapshot(
    runs: [run, ...runs.where((existing) => existing.id != run.id)],
  );

  /// Drops the oldest runs until the store is inside its limits.
  ///
  /// Snapshots are a quick undo, so the newest runs stay whole and the oldest
  /// are the ones given up, never part of a run.
  RunCheckpointsSnapshot bounded() {
    final kept = <RunCheckpoint>[];
    var bytes = 0;
    for (final run in runs) {
      if (kept.length >= RunCheckpointLimits.maxRuns) break;
      final size = run.contentBytes;
      if (kept.isNotEmpty && bytes + size > RunCheckpointLimits.maxTotalBytes) {
        break;
      }
      kept.add(run);
      bytes += size;
    }
    return RunCheckpointsSnapshot(runs: kept);
  }

  static RunCheckpointsSnapshot fromJson(Map<String, dynamic> json) {
    final raw = json['runs'];
    final runs = <RunCheckpoint>[];
    if (raw is List) {
      for (final value in raw) {
        if (value is! Map) continue;
        final run = RunCheckpoint.fromJson(Map<String, dynamic>.from(value));
        if (run != null) runs.add(run);
      }
    }
    return RunCheckpointsSnapshot(runs: runs);
  }
}
