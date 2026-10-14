import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:installm/storage/secure_storage.dart';

/// Locations of app-owned resources, independent of model/inference services.
/// Desktop uses Documents/InstaLLM; mobile uses its private Documents directly.
/// Only the two legacy managed directories migrate. External references and
/// unrelated Documents entries are never searched, moved or removed.
class AppStorageService {
  AppStorageService({
    Directory? documentsDirectory,
    bool? mobile,
    bool? ios,
    Set<String>? externalModelPaths,
    this.renameFile,
  }) : _documents = documentsDirectory,
       _mobile = mobile ?? (Platform.isAndroid || Platform.isIOS),
       _ios = ios ?? Platform.isIOS,
       _providedExternalPaths = externalModelPaths;

  final Directory? _documents;
  final bool _mobile;
  final bool _ios;
  final Set<String>? _providedExternalPaths;

  /// Allows tests to exercise cross-volume and interrupted moves.
  final Future<void> Function(File source, String target)? renameFile;
  static final Map<String, Future<void>> _queues = {};
  Future<Directory>? _ready;
  File? _migrationMarker;

  Future<Directory> get root => _ready ??= _initialize().catchError((Object e) {
    _ready = null;
    throw e;
  });

  Future<Directory> _initialize() async {
    final documents = _documents ?? await getApplicationDocumentsDirectory();
    final directory = Directory(
      _mobile ? documents.path : p.join(documents.path, 'InstaLLM'),
    );
    final key = p.normalize(directory.absolute.path);
    final previous = _queues[key] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) async {
      await _requireDirectory(directory);
      final marker = File(p.join(directory.path, '.storage-migration.json'));
      _migrationMarker = marker;
      if (await marker.exists()) {
        final raw = await marker.readAsString();
        Object? decoded;
        try {
          decoded = jsonDecode(raw);
        } on FormatException {
          // Preserve the original before repairing an interrupted/corrupt marker.
        }
        if (decoded is Map && decoded['version'] != 1) {
          throw const FileSystemException(
            'Storage migration version is unsupported. Use a newer app.',
          );
        }
        if (decoded is! Map) {
          await marker.copy(
            '${marker.path}.preserved-${DateTime.now().microsecondsSinceEpoch}',
          );
        } else if (decoded['pendingCopy'] is Map) {
          final pending = decoded['pendingCopy'] as Map;
          final target = pending['target'];
          final temporary = pending['temporary'];
          if (target is! String ||
              temporary is! String ||
              !['models', 'attachments'].any(
                (name) => p.isWithin(p.join(directory.path, name), target),
              ) ||
              !temporary.startsWith('$target.migration-') ||
              !temporary.endsWith('.tmp')) {
            throw const FileSystemException(
              'Storage copy journal is invalid. Restore it before retrying.',
            );
          }
          var parent = p.dirname(temporary);
          while (p.isWithin(directory.path, parent)) {
            if (await FileSystemEntity.type(parent, followLinks: false) ==
                FileSystemEntityType.link) {
              throw const FileSystemException(
                'Storage copy folder is a link. Restore it before retrying.',
              );
            }
            parent = p.dirname(parent);
          }
          final type = await FileSystemEntity.type(
            temporary,
            followLinks: false,
          );
          if (type == FileSystemEntityType.file) {
            await File(temporary).delete();
          } else if (type != FileSystemEntityType.notFound) {
            throw const FileSystemException(
              'Storage copy scratch path has changed. Restore it before retrying.',
            );
          }
        }
      }
      if (!_mobile) {
        final hasLegacyModels =
            await FileSystemEntity.type(
              p.join(documents.path, 'models'),
              followLinks: false,
            ) !=
            FileSystemEntityType.notFound;
        final external =
            _providedExternalPaths ??
            (_documents == null && hasLegacyModels
                ? await _externalReferences()
                : <String>{});
        for (final name in ['models', 'attachments']) {
          await _moveDirectory(
            Directory(p.join(documents.path, name)),
            Directory(p.join(directory.path, name)),
            preserved: name == 'models' ? external : const {},
          );
        }
      }
      for (final name in ['models', 'attachments', 'vault']) {
        await _requireDirectory(Directory(p.join(directory.path, name)));
      }
      await _writeMarker({'version': 1, 'complete': true});
    });
    _queues[key] = next;
    try {
      await next;
    } finally {
      if (identical(_queues[key], next)) _queues.remove(key);
    }
    return directory;
  }

  Future<void> _writeMarker(Map<String, Object?> payload) async {
    final marker = _migrationMarker!;
    final temporary = File('${marker.path}.tmp');
    await temporary.writeAsString(jsonEncode(payload), flush: true);
    await temporary.rename(marker.path);
  }

  Future<void> _requireDirectory(Directory directory) async {
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.link ||
        (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.directory)) {
      throw const FileSystemException(
        'An app storage folder is a link or file. Restore the folder and retry.',
      );
    }
    await directory.create(recursive: true);
  }

  Future<void> _moveDirectory(
    Directory source,
    Directory target, {
    Set<String> preserved = const {},
  }) async {
    final sourceType = await FileSystemEntity.type(
      source.path,
      followLinks: false,
    );
    if (sourceType == FileSystemEntityType.notFound) return;
    if (sourceType != FileSystemEntityType.directory) {
      throw const FileSystemException(
        'Legacy app storage is a link or file. Restore the folder and retry.',
      );
    }
    // Refuse links before a whole-directory rename can carry external roots.
    await for (final entry in source.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is Link) {
        throw const FileSystemException(
          'Legacy app storage contains a link. Remove the link and retry; '
          'its source has been left untouched.',
        );
      }
    }
    final targetType = await FileSystemEntity.type(
      target.path,
      followLinks: false,
    );
    final hasExternal = preserved.any(
      (path) => p.equals(source.path, path) || p.isWithin(source.path, path),
    );
    if (targetType == FileSystemEntityType.notFound &&
        renameFile == null &&
        !hasExternal) {
      try {
        await source.rename(target.path);
        return;
      } on FileSystemException {
        // Cross-volume moves fall back to per-file verified copying.
      }
    }
    await _requireDirectory(target);
    await for (final entry in source.list(followLinks: false)) {
      if (preserved.any((path) => p.equals(path, entry.path))) continue;
      final destination = p.join(target.path, p.basename(entry.path));
      if (entry is Directory) {
        await _moveDirectory(
          entry,
          Directory(destination),
          preserved: preserved,
        );
      } else if (entry is File) {
        await _moveFile(entry, File(destination));
      } else {
        throw const FileSystemException('Unsupported legacy storage entry.');
      }
    }
    // No recursive deletion: a concurrently added file makes this fail safely.
    if (!hasExternal) await source.delete();
  }

  /// Inspect only the model registry's external references. A corrupt registry
  /// blocks movement instead of guessing which files the app owns.
  Future<Set<String>> _externalReferences() async {
    final String? raw;
    final Object? decoded;
    try {
      raw = await SecureStorage.instance.readPrimitive('custom_models_v1');
      decoded = raw == null ? null : jsonDecode(raw);
    } catch (_) {
      throw const FileSystemException(
        'Cannot verify external model ownership. Restore access to the model registry and retry.',
      );
    }
    if (raw == null) return {};
    if (decoded is! Map || decoded['models'] is! List) {
      throw const FileSystemException(
        'The model registry cannot be read safely. Restore it before moving storage.',
      );
    }
    final paths = <String>{};
    for (final model in decoded['models'] as List) {
      if (model is! Map) {
        throw const FileSystemException(
          'The model registry contains invalid records. Restore it before moving storage.',
        );
      }
      for (final key in ['externalPath', 'externalMmprojPath']) {
        final value = model[key];
        if (value != null && value is! String) {
          throw const FileSystemException(
            'The model registry contains invalid external references. Restore it before moving storage.',
          );
        }
        if (value is String && value.trim().isNotEmpty) {
          paths.add(p.normalize(value));
        }
      }
    }
    return paths;
  }

  Future<void> _moveFile(File source, File target) async {
    final type = await FileSystemEntity.type(target.path, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      if (type != FileSystemEntityType.file ||
          !await _sameBytes(source, target)) {
        throw const FileSystemException(
          'Storage migration found different files at the same destination. '
          'Both are preserved. Resolve the conflict and retry.',
        );
      }
      await source.delete();
      return;
    }
    try {
      if (renameFile != null) {
        await renameFile!(source, target.path);
      } else {
        await source.rename(target.path);
      }
      return;
    } on FileSystemException catch (error) {
      // EXDEV only: permission/space/errors must not trigger a large copy.
      if (error.osError?.errorCode != 18 &&
          !(Platform.isWindows && error.osError?.errorCode == 17)) {
        rethrow;
      }
    }
    // Unique scratch file; a interrupted copy is never mistaken for a model.
    final temporary = File(
      '${target.path}.migration-${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    if (await FileSystemEntity.type(temporary.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FileSystemException(
        'Storage copy scratch file already exists. Retry migration.',
      );
    }
    await _writeMarker({
      'version': 1,
      'complete': false,
      'pendingCopy': {'target': target.path, 'temporary': temporary.path},
    });
    try {
      await source.copy(temporary.path);
      if (!await _sameBytes(source, temporary)) {
        throw const FileSystemException(
          'Storage copy verification failed. Original file is preserved.',
        );
      }
      await temporary.rename(target.path);
      await source.delete();
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  /// Streaming byte comparison (stronger than a sampled hash), bounded to
  /// 128 KiB regardless of model size. Also resolves interrupted-copy duplicates.
  Future<bool> _sameBytes(File a, File b) async {
    if (await a.length() != await b.length()) return false;
    final left = await a.open();
    final right = await b.open();
    try {
      while (true) {
        final x = await left.read(64 * 1024);
        final y = await right.read(64 * 1024);
        if (x.length != y.length) return false;
        if (x.isEmpty) return true;
        for (var i = 0; i < x.length; i++) {
          if (x[i] != y[i]) return false;
        }
      }
    } finally {
      await left.close();
      await right.close();
    }
  }

  Future<String> directory(String name) async =>
      p.join((await root).path, name);

  /// Reads remain usable during partial migration; writes use [directory] and
  /// are refused until migration succeeds. Prefer the legacy source on conflict.
  Future<String> modelPath(String fileName) async {
    try {
      return p.join(await directory('models'), fileName);
    } on FileSystemException {
      final documents = _documents ?? await getApplicationDocumentsDirectory();
      final legacy = p.join(documents.path, 'models', fileName);
      if (await File(legacy).exists()) return legacy;
      return p.join(
        _mobile ? documents.path : p.join(documents.path, 'InstaLLM'),
        'models',
        fileName,
      );
    }
  }

  /// Resolve only known managed attachment layouts, retaining the full relative
  /// path. Never bind an external/missing file by basename to another chat.
  Future<String> resolveAttachmentPath(String path) async {
    if (path.isEmpty) return path;
    try {
      await root;
    } on FileSystemException {
      // Completed moves and untouched sources still support reads. Resource
      // writes surface the actionable migration error through directory().
    }
    if (await File(path).exists()) return path;
    final documents = _documents ?? await getApplicationDocumentsDirectory();
    final normalized = p.normalize(path);
    String? relative;
    for (final base in [
      p.join(documents.path, 'attachments'),
      p.join(documents.path, 'InstaLLM', 'attachments'),
    ]) {
      if (p.isWithin(base, normalized)) {
        relative = p.relative(normalized, from: base);
      }
    }
    if (relative == null && _ios) {
      final match = RegExp(
        r'^/.*?/Containers/Data/Application/[^/]+/Documents/(?:InstaLLM/)?attachments/(.+)$',
      ).firstMatch(normalized);
      relative = match?.group(1);
    }
    if (relative == null) return path;
    final base = p.join(
      _mobile ? documents.path : p.join(documents.path, 'InstaLLM'),
      'attachments',
    );
    final candidate = p.normalize(p.join(base, relative));
    if (!p.isWithin(base, candidate)) return path;
    return await File(candidate).exists() ? candidate : path;
  }
}
