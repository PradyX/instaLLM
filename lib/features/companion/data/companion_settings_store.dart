import 'dart:io';

import 'package:installm/core/data/versioned_json_document.dart';
import 'package:installm/features/companion/domain/companion_settings.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Persistent, offline Companion settings.
///
/// Storage format (version 1):
///
/// ```json
/// {
///   "version": 1,
///   "name": "Ada",
///   "enabled": false,
///   "wakeSensitivity": 0.6,
///   "silenceTimeoutMs": 1500
/// }
/// ```
///
/// The rules are the app's shared versioned-document ones: a payload that
/// cannot be read is copied aside before the first rewrite, and a file written
/// by a newer build is left untouched and makes the screen read-only. A missing
/// file means an untouched install: Companion off, called Ada.
class CompanionSettingsStore {
  CompanionSettingsStore(File file)
    : _document = VersionedJsonDocument(
        file: file,
        currentVersion: currentVersion,
        label: 'CompanionSettingsStore',
      );

  static const int currentVersion = 1;

  /// Opens the settings file inside the app support directory.
  static Future<CompanionSettingsStore> open() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return CompanionSettingsStore(
      File(p.join(supportDirectory.path, 'companion', 'settings.json')),
    );
  }

  final VersionedJsonDocument _document;

  /// Absolute path of the settings file (used by diagnostics and tests).
  String get filePath => _document.filePath;

  /// True when the file belongs to a newer build and must not be rewritten.
  bool get isReadOnly => _document.isReadOnly;

  CompanionSettings load() {
    final decoded = _document.read();
    if (decoded == null) return const CompanionSettings();
    return CompanionSettings.fromJson(decoded);
  }

  /// Writes [settings]. Returns false when the store is read-only.
  bool save(CompanionSettings settings) {
    return _document.write({
      'version': currentVersion,
      ...settings.normalized().toJson(),
    });
  }
}
