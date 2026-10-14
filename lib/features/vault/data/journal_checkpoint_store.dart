import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final journalCheckpointStoreProvider = FutureProvider<JournalCheckpointStore>(
  (ref) => JournalCheckpointStore.open(),
);

/// Last app-written content hashes, never note text. Unknown ownership means
/// an existing note belongs to the user and must not be overwritten.
class JournalCheckpointStore {
  JournalCheckpointStore(this.file);
  final File file;
  bool _preserve = false;
  static Future<JournalCheckpointStore> open() async => JournalCheckpointStore(
    File(
      p.join(
        (await getApplicationSupportDirectory()).path,
        'vault',
        'journal-checkpoints.json',
      ),
    ),
  );

  Map<String, String> _read() {
    if (!file.existsSync()) return {};
    Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException {
      _preserve = true;
      return {};
    }
    if (decoded is! Map) {
      _preserve = true;
      return {};
    }
    if (decoded['version'] != 1) {
      throw const FileSystemException(
        'Journal ownership version is unsupported.',
      );
    }
    if (decoded.keys.any((key) => key != 'version' && key != 'hashes')) {
      _preserve = true;
    }
    final raw = decoded['hashes'];
    if (raw is! Map) {
      _preserve = true;
      return {};
    }
    final result = <String, String>{};
    for (final entry in raw.entries) {
      if (entry.key is String &&
          entry.value is String &&
          RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.value)) {
        result[entry.key as String] = entry.value as String;
      } else {
        _preserve = true;
      }
    }
    return result;
  }

  String? hashFor(String key) => _read()[key];

  bool saveHash(String key, String hash) {
    final temporary = File('${file.path}.tmp');
    try {
      final hashes = _read();
      if (_preserve && file.existsSync()) {
        file.copySync(
          '${file.path}.preserved-${DateTime.now().microsecondsSinceEpoch}',
        );
      }
      hashes[key] = hash;
      file.parent.createSync(recursive: true);
      temporary.writeAsStringSync(
        jsonEncode({'version': 1, 'hashes': hashes}),
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
        } catch (_) {
          /* Preserve the current store. */
        }
      }
    }
  }
}
