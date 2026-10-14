import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:installm/core/data/versioned_json_document.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';

/// One workspace's vault binding: which vault, which folder, what is allowed.
class WorkspaceVaultBinding {
  const WorkspaceVaultBinding({
    required this.workspaceId,
    required this.vaultId,
    this.projectPath = '',
    this.permissions = VaultPermissions.defaults,
  });

  final String workspaceId;
  final String vaultId;

  /// Workspace-relative directory inside the vault.
  final String projectPath;
  final VaultPermissions permissions;

  WorkspaceVaultBinding copyWith({
    String? vaultId,
    String? projectPath,
    VaultPermissions? permissions,
  }) {
    return WorkspaceVaultBinding(
      workspaceId: workspaceId,
      vaultId: vaultId ?? this.vaultId,
      projectPath: projectPath ?? this.projectPath,
      permissions: permissions ?? this.permissions,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workspaceId': workspaceId,
      'vaultId': vaultId,
      'projectPath': projectPath,
      'permissions': permissions.toJson(),
    };
  }

  static WorkspaceVaultBinding? fromJson(Map<String, dynamic> json) {
    final workspaceId = json['workspaceId'];
    final vaultId = json['vaultId'];
    if (workspaceId is! String ||
        workspaceId.isEmpty ||
        vaultId is! String ||
        vaultId.isEmpty) {
      return null;
    }
    final projectPath = json['projectPath'] is String
        ? json['projectPath'] as String
        : '';
    var permissions = const VaultPermissions(
      canRead: false,
      canWrite: false,
      canCreate: false,
      canUpdate: false,
    );
    if (json['permissions'] is Map) {
      permissions = VaultPermissions.fromJson(
        Map<String, dynamic>.from(json['permissions'] as Map),
      );
    }
    return WorkspaceVaultBinding(
      workspaceId: workspaceId,
      vaultId: vaultId,
      projectPath: projectPath,
      permissions: permissions,
    );
  }
}

/// Persisted vault registrations plus workspace bindings.
///
/// Storage format (version 1):
/// ```json
/// {"version": 1, "vaults": [...], "bindings": [...]}
/// ```
/// Vault roots are device-specific paths; only registrations (never note
/// contents, never secrets) live here.
class VaultStore {
  VaultStore(File file)
    : _file = file,
      _document = VersionedJsonDocument(
        file: file,
        currentVersion: currentVersion,
        label: 'VaultStore',
      );

  static const int currentVersion = 2;

  /// Where the registry lives today.
  static const String directoryName = 'vault';
  static const String fileName = 'vaults.json';

  /// Directory the registry was written to before the 2026-10-14 rename,
  /// kept only so an existing file can be carried over.
  static const String legacyDirectoryName = 'obsidian';

  static Future<VaultStore> open() async {
    final support = await getApplicationSupportDirectory();
    return VaultStore(await resolveFile(support));
  }

  /// The registry file under [support], carrying a pre-rename file over once.
  ///
  /// Separate from [open] so the migration can be tested against a temporary
  /// directory instead of the real app support path.
  static Future<File> resolveFile(Directory support) async {
    final target = File(p.join(support.path, directoryName, fileName));
    if (target.existsSync()) return target;

    final legacy = File(p.join(support.path, legacyDirectoryName, fileName));
    // Carry the registry over only when nothing is at the new path, so a file
    // this build already wrote is never overwritten by an older one.
    if (legacy.existsSync()) {
      try {
        await target.parent.create(recursive: true);
        try {
          await legacy.rename(target.path);
        } on FileSystemException {
          // Another volume, or the rename was refused: copy instead and leave
          // the original where it is.
          await legacy.copy(target.path);
        }
      } catch (_) {
        // Unreadable or unmovable: the registry simply starts empty, which is
        // recoverable by registering the vault again.
      }
    }
    return target;
  }

  final VersionedJsonDocument _document;
  final File _file;
  bool _invalidVersion = false;

  String get filePath => _document.filePath;
  bool get isReadOnly => _document.isReadOnly || _invalidVersion;

  VaultsSnapshot load() {
    final decoded = _document.read();
    if (decoded == null) return VaultsSnapshot.empty;
    final version = decoded['version'];
    _invalidVersion = version != null && (version is! int || version < 1);
    if (_invalidVersion) return VaultsSnapshot.empty;
    return VaultsSnapshot.fromJson(decoded);
  }

  bool save(VaultsSnapshot snapshot) {
    // Check disk even for save-before-load or a newer writer during this run.
    final current = load();
    if (isReadOnly) return false;
    final payload = {
      'version': currentVersion,
      'vaults': snapshot.vaults.map((v) => v.toJson()).toList(),
      'bindings': snapshot.bindings.map((b) => b.toJson()).toList(),
    };
    final temporary = File('${_file.path}.tmp');
    try {
      if (_file.existsSync()) {
        final raw = _file.readAsStringSync();
        final canonicalCurrent = jsonEncode({
          'version': currentVersion,
          'vaults': current.vaults.map((v) => v.toJson()).toList(),
          'bindings': current.bindings.map((b) => b.toJson()).toList(),
        });
        Object? decoded;
        try {
          decoded = jsonDecode(raw);
        } on FormatException {
          /* Preserve below. */
        }
        // Preserve older, partial, corrupt or unknown data before rewriting.
        if (decoded == null ||
            jsonEncode(decoded) != canonicalCurrent ||
            current.vaults.map((v) => v.id).toSet().length !=
                current.vaults.length ||
            current.bindings.map((b) => b.workspaceId).toSet().length !=
                current.bindings.length) {
          _file.copySync(
            '${_file.path}.preserved-${DateTime.now().microsecondsSinceEpoch}',
          );
        }
      }
      _file.parent.createSync(recursive: true);
      temporary.writeAsStringSync(jsonEncode(payload), flush: true);
      temporary.renameSync(_file.path);
      return true;
    } catch (_) {
      return false;
    } finally {
      if (temporary.existsSync()) {
        try {
          temporary.deleteSync();
        } catch (_) {
          /* Keep the original. */
        }
      }
    }
  }
}

class VaultsSnapshot {
  const VaultsSnapshot({required this.vaults, this.bindings = const []});

  static const VaultsSnapshot empty = VaultsSnapshot(vaults: []);

  final List<VaultRegistration> vaults;
  final List<WorkspaceVaultBinding> bindings;

  WorkspaceVaultBinding? bindingFor(String workspaceId) {
    for (final binding in bindings) {
      if (binding.workspaceId == workspaceId) return binding;
    }
    return null;
  }

  VaultRegistration? vaultById(String vaultId) {
    for (final vault in vaults) {
      if (vault.id == vaultId) return vault;
    }
    return null;
  }

  VaultsSnapshot upsertVault(VaultRegistration vault) {
    final updated = <VaultRegistration>[];
    var replaced = false;
    for (final existing in vaults) {
      if (existing.id == vault.id) {
        updated.add(vault);
        replaced = true;
      } else {
        updated.add(existing);
      }
    }
    if (!replaced) updated.add(vault);
    return VaultsSnapshot(vaults: updated, bindings: bindings);
  }

  VaultsSnapshot removeVault(String vaultId) {
    return VaultsSnapshot(
      vaults: vaults.where((vault) => vault.id != vaultId).toList(),
      bindings: bindings
          .where((binding) => binding.vaultId != vaultId)
          .toList(),
    );
  }

  VaultsSnapshot upsertBinding(WorkspaceVaultBinding binding) {
    final updated = <WorkspaceVaultBinding>[];
    var replaced = false;
    for (final existing in bindings) {
      if (existing.workspaceId == binding.workspaceId) {
        updated.add(binding);
        replaced = true;
      } else {
        updated.add(existing);
      }
    }
    if (!replaced) updated.add(binding);
    return VaultsSnapshot(vaults: vaults, bindings: updated);
  }

  VaultsSnapshot removeBinding(String workspaceId) {
    return VaultsSnapshot(
      vaults: vaults,
      bindings: bindings
          .where((binding) => binding.workspaceId != workspaceId)
          .toList(),
    );
  }

  static VaultsSnapshot fromJson(Map<String, dynamic> json) {
    final vaults = <VaultRegistration>[];
    final rawVaults = json['vaults'];
    if (rawVaults is List) {
      for (final entry in rawVaults) {
        final map = entry is Map<String, dynamic>
            ? entry
            : entry is Map
            ? Map<String, dynamic>.from(entry)
            : null;
        if (map == null) continue;
        final vault = VaultRegistration.fromJson(map);
        if (vault != null) vaults.add(vault);
      }
    }
    final bindings = <WorkspaceVaultBinding>[];
    final rawBindings = json['bindings'];
    if (rawBindings is List) {
      for (final entry in rawBindings) {
        final map = entry is Map<String, dynamic>
            ? entry
            : entry is Map
            ? Map<String, dynamic>.from(entry)
            : null;
        if (map == null) continue;
        final binding = WorkspaceVaultBinding.fromJson(map);
        if (binding != null) bindings.add(binding);
      }
    }
    return VaultsSnapshot(vaults: vaults, bindings: bindings);
  }
}
