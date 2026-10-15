import 'dart:convert';
import 'dart:io';

import 'package:installm/features/agents/domain/agent_hook.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Versioned store of the agent hooks in force.
///
/// Hooks are user data: a file this build cannot fully understand is backed up
/// before it is rewritten, an entry the decoder drops makes the next save keep
/// the original, and a file written by a newer build turns the store read-only
/// instead of being rewritten from what this build happens to know.
class HookStore {
  HookStore(this.file);

  final File file;
  static const int currentVersion = 1;

  /// Every schema this build can read.
  static const List<int> readableVersions = [currentVersion];

  bool _readOnly = false;
  bool _preserve = false;

  bool get isReadOnly => _readOnly;
  String get filePath => file.path;

  static Future<HookStore> open() async => HookStore(
    File(
      p.join(
        (await getApplicationSupportDirectory()).path,
        'agents',
        'hooks.json',
      ),
    ),
  );

  HooksSnapshot load() {
    if (!file.existsSync()) return HooksSnapshot.empty;
    try {
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map<String, dynamic>) {
        _preserve = true;
        return HooksSnapshot.empty;
      }
      final version = raw['version'];
      if (version is! int || !readableVersions.contains(version)) {
        _readOnly = true;
        return HooksSnapshot.empty;
      }
      final snapshot = HooksSnapshot.fromJson(raw);
      _preserve =
          version != currentVersion ||
          raw['hooks'] is! List ||
          jsonEncode(raw['hooks']) !=
              jsonEncode(
                snapshot.hooks.map((hook) => hook.toJson()).toList(),
              ) ||
          raw.keys.any((key) => !const {'version', 'hooks'}.contains(key));
      return snapshot;
    } on FormatException {
      _preserve = true;
      return HooksSnapshot.empty;
    }
  }

  bool save(HooksSnapshot snapshot) {
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
          'hooks': snapshot.hooks.map((hook) => hook.toJson()).toList(),
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

/// The hooks one file holds, in the order they are evaluated.
class HooksSnapshot {
  const HooksSnapshot({required this.hooks});

  static const HooksSnapshot empty = HooksSnapshot(hooks: []);

  final List<AgentHook> hooks;

  /// What the tool registry enforces: the stored rules, enabled or not, are
  /// kept intact and [HookPolicy] skips the disabled ones.
  HookPolicy get policy => HookPolicy(hooks: hooks);

  HooksSnapshot upsert(AgentHook hook) {
    final updated = <AgentHook>[];
    var replaced = false;
    for (final existing in hooks) {
      if (existing.id == hook.id) {
        updated.add(hook);
        replaced = true;
      } else {
        updated.add(existing);
      }
    }
    if (!replaced) updated.add(hook);
    return HooksSnapshot(hooks: updated);
  }

  HooksSnapshot remove(String hookId) => HooksSnapshot(
    hooks: [
      for (final hook in hooks)
        if (hook.id != hookId) hook,
    ],
  );

  static HooksSnapshot fromJson(Map<String, dynamic> json) {
    final raw = json['hooks'];
    final hooks = <AgentHook>[];
    if (raw is List) {
      for (final entry in raw) {
        final map = entry is Map<String, dynamic>
            ? entry
            : entry is Map
            ? Map<String, dynamic>.from(entry)
            : null;
        if (map == null) continue;
        final hook = AgentHook.fromJson(map);
        if (hook != null) hooks.add(hook);
      }
    }
    return HooksSnapshot(hooks: hooks);
  }
}
