import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:installm/features/memory/domain/memory_fact.dart';

/// Local-only facts. Existing conversation summaries are never migrated into
/// facts: a summary is not evidence that the user asked to remember something.
class MemoryStore {
  MemoryStore(this.file);

  static const int currentVersion = 2;
  final File file;
  bool _readOnly = false;
  bool _needsBackup = false;
  Map<String, String> _conversationWorkspaces = const {};

  bool get isReadOnly => _readOnly;
  Map<String, String> get conversationWorkspaces => _conversationWorkspaces;

  static Future<MemoryStore> open() async {
    final support = await getApplicationSupportDirectory();
    return MemoryStore(File(p.join(support.path, 'memory', 'facts.json')));
  }

  /// Reads v1/v2 or an unversioned fact list (v0). Version 2 adds stable
  /// workspace bindings for ordinary chats; facts and consent are unchanged.
  /// Invalid entries are skipped
  /// for recall, with the original payload backed up before any rewrite.
  List<MemoryFact> load() {
    _needsBackup = false;
    _readOnly = false;
    _conversationWorkspaces = const {};
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
    final bindings = decoded['conversationWorkspaces'];
    final usableBindings = <String, String>{};
    if (bindings is Map) {
      for (final entry in bindings.entries) {
        if (entry.key is String &&
            (entry.key as String).trim().isNotEmpty &&
            entry.value is String &&
            (entry.value as String).trim().isNotEmpty) {
          usableBindings[entry.key as String] = entry.value as String;
        } else {
          _needsBackup = true;
        }
      }
    } else if (bindings != null || version == currentVersion) {
      _needsBackup = true;
    }
    _conversationWorkspaces = Map.unmodifiable(usableBindings);
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
  bool save(
    List<MemoryFact> facts, {
    Map<String, String>? conversationWorkspaces,
  }) {
    File? temporary;
    try {
      load();
      if (_readOnly) return false;
      if (facts.map((fact) => fact.id).toSet().length != facts.length) {
        return false;
      }
      if (conversationWorkspaces != null &&
          conversationWorkspaces.entries.any(
            (entry) => entry.key.trim().isEmpty || entry.value.trim().isEmpty,
          )) {
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
          'conversationWorkspaces':
              conversationWorkspaces ?? _conversationWorkspaces,
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
