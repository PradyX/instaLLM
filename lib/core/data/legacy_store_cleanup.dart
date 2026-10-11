import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One-shot cleanup for store files of removed features.
///
/// Workflows and the activity feed were deleted (the room turn loop keeps
/// agentic behavior in bots instead). Their files — `workflows/` and every
/// workspace's `activity.json` — are never read again, so this removes them
/// once at startup. Best-effort: a cleanup failure never blocks launch.
class LegacyStoreCleanup {
  LegacyStoreCleanup._();

  static bool _done = false;

  /// Deletes leftover workflow and activity files. Safe to call repeatedly;
  /// only the first call does work.
  static Future<void> run() async {
    if (_done) return;
    _done = true;
    try {
      final support = await getApplicationSupportDirectory();
      final workflowsDir = Directory(p.join(support.path, 'workflows'));
      if (await workflowsDir.exists()) {
        await workflowsDir.delete(recursive: true);
      }
      final workspacesDir = Directory(p.join(support.path, 'workspaces'));
      if (await workspacesDir.exists()) {
        await for (final entry in workspacesDir.list()) {
          if (entry is! Directory) continue;
          final activity = File(p.join(entry.path, 'activity.json'));
          if (await activity.exists()) {
            await activity.delete();
          }
        }
      }
    } catch (_) {}
  }
}
