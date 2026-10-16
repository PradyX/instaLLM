import 'dart:convert';
import 'dart:io';

import 'package:installm/features/documents/domain/network_policy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Versioned store of the opt-in network policy (Road Map 3 Phase 3.4).
///
/// The policy is user data with the closed posture as its default: a file
/// this build cannot fully understand is backed up before it is rewritten, an
/// entry the decoder drops makes the next save keep the original, and a file
/// written by a newer build turns the store read-only instead of being
/// rewritten from what this build happens to know.
///
/// Nothing syncs except through the user's own vault sync: this file lives
/// under application support beside the other local stores.
class NetworkPolicyStore {
  NetworkPolicyStore(this.file);

  final File file;
  static const int currentVersion = 1;

  /// Every schema this build can read.
  static const List<int> readableVersions = [currentVersion];

  bool _readOnly = false;
  bool _preserve = false;

  bool get isReadOnly => _readOnly;
  String get filePath => file.path;

  static Future<NetworkPolicyStore> open() async => NetworkPolicyStore(
    File(
      p.join(
        (await getApplicationSupportDirectory()).path,
        'documents',
        'network_policy.json',
      ),
    ),
  );

  NetworkPolicySnapshot load() {
    if (!file.existsSync()) return NetworkPolicySnapshot.empty;
    try {
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map<String, dynamic>) {
        _preserve = true;
        return NetworkPolicySnapshot.empty;
      }
      final version = raw['version'];
      if (version is! int || !readableVersions.contains(version)) {
        _readOnly = true;
        return NetworkPolicySnapshot.empty;
      }
      final snapshot = NetworkPolicySnapshot.fromJson(raw);
      final policies = raw['policies'];
      _preserve =
          version != currentVersion ||
          policies is! Map ||
          jsonEncode(policies) !=
              jsonEncode(
                snapshot._policies.map(
                  (key, value) => MapEntry(key, value.toJson()),
                ),
              ) ||
          raw.keys.any((key) => !const {'version', 'policies'}.contains(key));
      return snapshot;
    } on FormatException {
      _preserve = true;
      return NetworkPolicySnapshot.empty;
    }
  }

  bool save(NetworkPolicySnapshot snapshot) {
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
          'policies': snapshot._policies.map(
            (key, value) => MapEntry(key, value.toJson()),
          ),
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

/// The per-workspace policies one file holds.
///
/// Absent means closed: a workspace without an entry answers with
/// [NetworkPolicy.closed], which is what keeps a store from before the policy
/// existed behaving exactly as it always has.
class NetworkPolicySnapshot {
  const NetworkPolicySnapshot([Map<String, NetworkPolicy> policies = const {}])
    : _policies = policies;

  static const NetworkPolicySnapshot empty = NetworkPolicySnapshot();

  final Map<String, NetworkPolicy> _policies;

  /// Policy in force for [workspaceId], or the closed default.
  NetworkPolicy forWorkspace(String workspaceId) =>
      _policies[workspaceId] ?? NetworkPolicy.closed;

  /// Every workspace with an explicit entry, for the settings screen.
  Map<String, NetworkPolicy> get policies => Map.unmodifiable(_policies);

  NetworkPolicySnapshot setWorkspace(String workspaceId, NetworkPolicy policy) {
    final id = workspaceId.trim();
    if (id.isEmpty) return this;
    final bounded = id.length <= NetworkPolicyLimits.maxWorkspaceIdLength
        ? id
        : id.substring(0, NetworkPolicyLimits.maxWorkspaceIdLength);
    final next = Map<String, NetworkPolicy>.from(_policies);
    next[bounded] = policy.normalized();
    while (next.length > NetworkPolicyLimits.maxWorkspaces) {
      next.remove(next.keys.first);
    }
    return NetworkPolicySnapshot(Map.unmodifiable(next));
  }

  NetworkPolicySnapshot removeWorkspace(String workspaceId) {
    if (!_policies.containsKey(workspaceId)) return this;
    final next = Map<String, NetworkPolicy>.from(_policies);
    next.remove(workspaceId);
    return NetworkPolicySnapshot(Map.unmodifiable(next));
  }

  static NetworkPolicySnapshot fromJson(Map<String, dynamic> json) {
    final raw = json['policies'];
    if (raw is! Map) return NetworkPolicySnapshot.empty;
    final policies = <String, NetworkPolicy>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String || key.trim().isEmpty) continue;
      if (key.length > NetworkPolicyLimits.maxWorkspaceIdLength) continue;
      // A corrupt entry is dropped from the live view but preserved on disk
      // by the store's `_preserve` flag, never silently rewritten away.
      policies[key] = NetworkPolicy.fromJson(entry.value);
      if (policies.length >= NetworkPolicyLimits.maxWorkspaces) break;
    }
    return NetworkPolicySnapshot(Map.unmodifiable(policies));
  }
}
