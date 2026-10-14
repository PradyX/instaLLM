import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:installm/features/memory/domain/memory_fact.dart';

/// Local-only facts. Existing conversation summaries are never migrated into
/// facts: a summary is not evidence that the user asked to remember something.
class MemoryStore {
  MemoryStore(this.file);

  static const int currentVersion = 1;
  final File file;
  bool _readOnly = false;
  bool _needsBackup = false;

  bool get isReadOnly => _readOnly;

  static Future<MemoryStore> open() async {
    final support = await getApplicationSupportDirectory();
    return MemoryStore(File(p.join(support.path, 'memory', 'facts.json')));
  }

  /// Reads v1 or an unversioned fact list (v0). Invalid entries are skipped
  /// for recall, with the original payload backed up before any rewrite.
  List<MemoryFact> load() {
    _needsBackup = false;
    _readOnly = false;
    final type = FileSystemEntity.typeSync(file.path);
    if (type == FileSystemEntityType.notFound) return const [];
    if (type != FileSystemEntityType.file) {
      throw FileSystemException(
        'Memory storage is not a regular file.',
        file.path,
      );
    }
    final raw = file.readAsStringSync();
    if (raw.trim().isEmpty) return const [];
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      _needsBackup = true;
      return const [];
    }
    if (decoded is! Map) {
      _needsBackup = true;
      return const [];
    }
    final version = decoded['version'];
    // A malformed version is not a license to downgrade the file.
    if (version != null &&
        (version is! int || version < 0 || version > currentVersion)) {
      _readOnly = true;
      return const [];
    }
    _needsBackup = version != currentVersion;
    final entries = decoded['facts'];
    if (entries is! List) {
      _needsBackup = true;
      return const [];
    }
    final facts = <MemoryFact>[];
    final ids = <String>{};
    for (final entry in entries) {
      final fact = MemoryFact.fromJson(entry);
      if (fact == null || !ids.add(fact.id)) {
        _needsBackup = true;
      } else {
        facts.add(fact);
      }
    }
    return List.unmodifiable(facts);
  }

  /// Writes atomically. A failed preservation copy stops the write. Re-read
  /// first so even save-before-load cannot overwrite a newer schema.
  bool save(List<MemoryFact> facts) {
    File? temporary;
    try {
      load();
      if (_readOnly) return false;
      if (facts.map((fact) => fact.id).toSet().length != facts.length) {
        return false;
      }
      file.parent.createSync(recursive: true);
      if (_needsBackup) {
        file.copySync(
          '${file.path}.preserved-${DateTime.now().microsecondsSinceEpoch}',
        );
      }
      temporary = File(
        '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
      );
      temporary.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'version': currentVersion,
          'facts': facts.map((fact) => fact.toJson()).toList(),
        }),
        flush: true,
      );
      temporary.renameSync(file.path);
      _needsBackup = false;
      return true;
    } on FileSystemException {
      return false;
    } finally {
      if (temporary != null && temporary.existsSync()) {
        try {
          temporary.deleteSync();
        } on FileSystemException {
          // An interrupted temporary write can remain for later recovery.
        }
      }
    }
  }
}
