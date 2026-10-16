import 'dart:convert';
import 'dart:io';

import 'package:installm/features/reminders/domain/scheduled_task.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Versioned store of scheduled tasks (Road Map 3 Phase 3.6).
///
/// Tasks are user data with the same protection as the other local stores: a
/// file this build cannot fully understand is backed up before it is
/// rewritten, and a file from a newer build turns the store read-only.
class ScheduledTaskStore {
  ScheduledTaskStore(this.file);

  final File file;
  static const int currentVersion = 1;
  static const List<int> readableVersions = [currentVersion];

  bool _readOnly = false;
  bool _preserve = false;

  bool get isReadOnly => _readOnly;

  static Future<ScheduledTaskStore> open() async => ScheduledTaskStore(
    File(
      p.join(
        (await getApplicationSupportDirectory()).path,
        'reminders',
        'scheduled_tasks.json',
      ),
    ),
  );

  List<ScheduledTask> load() {
    if (!file.existsSync()) return const [];
    try {
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map<String, dynamic>) {
        _preserve = true;
        return const [];
      }
      final version = raw['version'];
      if (version is! int || !readableVersions.contains(version)) {
        _readOnly = true;
        return const [];
      }
      final tasks = <ScheduledTask>[];
      final list = raw['tasks'];
      if (list is List) {
        for (final entry in list) {
          final map = entry is Map<String, dynamic>
              ? entry
              : entry is Map
              ? Map<String, dynamic>.from(entry)
              : null;
          if (map == null) continue;
          final task = ScheduledTask.fromJson(map);
          if (task != null) tasks.add(task);
          if (tasks.length >= ScheduledTaskLimits.maxTasks) break;
        }
      }
      _preserve =
          version != currentVersion ||
          list is! List ||
          raw.keys.any((key) => !const {'version', 'tasks'}.contains(key));
      tasks.sort((a, b) => a.nextRunAt.compareTo(b.nextRunAt));
      return tasks;
    } on FormatException {
      _preserve = true;
      return const [];
    }
  }

  bool save(List<ScheduledTask> tasks) {
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
          'tasks': tasks
              .take(ScheduledTaskLimits.maxTasks)
              .map((task) => task.toJson())
              .toList(),
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
