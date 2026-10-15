import 'dart:convert';
import 'dart:io';

import 'package:installm/features/agents/domain/background_run.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Versioned store of the supervised runs this device started.
///
/// Records are the app's own bookkeeping, so the same discipline as the other
/// agent stores applies: a file this build cannot fully read is kept before it
/// is rewritten, an entry the decoder drops makes the next save keep the
/// original, a newer schema turns the store read-only, and writes go through a
/// temporary file. A run that was still marked running when the app closed is
/// read back as it was — the supervisor decides what that means, the store
/// never rewrites history.
class BackgroundRunStore {
  BackgroundRunStore(this.file);

  final File file;
  static const int currentVersion = 1;

  static const List<int> readableVersions = [currentVersion];

  bool _readOnly = false;
  bool _preserve = false;

  bool get isReadOnly => _readOnly;
  String get filePath => file.path;

  static Future<BackgroundRunStore> open() async => BackgroundRunStore(
    File(
      p.join(
        (await getApplicationSupportDirectory()).path,
        'agents',
        'runs.json',
      ),
    ),
  );

  BackgroundRunsSnapshot load() {
    if (!file.existsSync()) return BackgroundRunsSnapshot.empty;
    try {
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map<String, dynamic>) {
        _preserve = true;
        return BackgroundRunsSnapshot.empty;
      }
      final version = raw['version'];
      if (version is! int || !readableVersions.contains(version)) {
        _readOnly = true;
        return BackgroundRunsSnapshot.empty;
      }
      final snapshot = BackgroundRunsSnapshot.fromJson(raw);
      _preserve =
          version != currentVersion ||
          raw['runs'] is! List ||
          jsonEncode(raw['runs']) !=
              jsonEncode(snapshot.runs.map((run) => run.toJson()).toList()) ||
          raw.keys.any((key) => !const {'version', 'runs'}.contains(key));
      return snapshot;
    } on FormatException {
      _preserve = true;
      return BackgroundRunsSnapshot.empty;
    }
  }

  bool save(BackgroundRunsSnapshot snapshot) {
    final temporary = File('${file.path}.tmp');
    try {
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
class BackgroundRunsSnapshot {
  const BackgroundRunsSnapshot({required this.runs});

  static const BackgroundRunsSnapshot empty = BackgroundRunsSnapshot(runs: []);

  final List<BackgroundRun> runs;

  BackgroundRun? byId(String runId) {
    for (final run in runs) {
      if (run.id == runId) return run;
    }
    return null;
  }

  /// The run still going in [chatId], if any: one supervised run per chat,
  /// because the app runs one model at a time and two tasks in one room would
  /// take turns at it.
  BackgroundRun? runningIn(String chatId) {
    for (final run in runs) {
      if (run.chatId == chatId && run.isRunning) return run;
    }
    return null;
  }

  BackgroundRun? get running {
    for (final run in runs) {
      if (run.isRunning) return run;
    }
    return null;
  }

  BackgroundRunsSnapshot upsert(BackgroundRun run) => BackgroundRunsSnapshot(
    runs: [run, ...runs.where((existing) => existing.id != run.id)],
  );

  /// Keeps the newest runs and gives up the oldest whole.
  BackgroundRunsSnapshot bounded() => BackgroundRunsSnapshot(
    runs: runs.take(BackgroundRunLimits.maxRecords).toList(),
  );

  static BackgroundRunsSnapshot fromJson(Map<String, dynamic> json) {
    final raw = json['runs'];
    final runs = <BackgroundRun>[];
    if (raw is List) {
      for (final value in raw) {
        if (value is! Map) continue;
        final run = BackgroundRun.fromJson(Map<String, dynamic>.from(value));
        if (run != null) runs.add(run);
      }
    }
    return BackgroundRunsSnapshot(runs: runs);
  }
}
