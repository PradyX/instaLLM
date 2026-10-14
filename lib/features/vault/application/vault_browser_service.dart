import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:installm/features/vault/application/vault_notes_service.dart';
import 'package:installm/features/vault/domain/vault_paths.dart';

class VaultFileEntry {
  const VaultFileEntry({required this.path, required this.isDirectory});
  final String path;
  final bool isDirectory;
  String get name => p.basename(path);
}

class VaultFileListing {
  const VaultFileListing(this.entries, {this.truncated = false});
  final List<VaultFileEntry> entries;
  final bool truncated;
}

/// Lazy directory browsing and bounded filename search. Never reads note text
/// to enumerate a tree, follows child links, or touches unregistered folders.
class VaultBrowserService {
  const VaultBrowserService();
  static const _notes = VaultNotesService();
  static const maxEntries = 500;
  static const maxSearchVisits = 2500;

  Future<(VaultFileListing?, VaultNoteError?)> list(
    VaultPaths paths,
    String folder,
  ) async {
    try {
      if (!await _notes.isSafePath(paths, folder)) {
        return (null, VaultNoteError.outsideProject);
      }
      final directory = Directory(paths.projectFile(folder)!);
      if (!await directory.exists()) return (null, VaultNoteError.notFound);
      final entries = <VaultFileEntry>[];
      var visited = 0;
      var truncated = false;
      await for (final entity in directory.list(followLinks: false)) {
        if (++visited > maxSearchVisits || entries.length >= maxEntries) {
          truncated = true;
          break;
        }
        if (entity is Link) continue;
        if (entity is Directory && p.basename(entity.path).startsWith('.')) {
          continue;
        }
        if (entity is! Directory &&
            (entity is! File || !entity.path.toLowerCase().endsWith('.md'))) {
          continue;
        }
        final relative = paths.relativeToProject(entity.path);
        if (relative != null) {
          entries.add(
            VaultFileEntry(path: relative, isDirectory: entity is Directory),
          );
        }
      }
      entries.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return (VaultFileListing(entries, truncated: truncated), null);
    } catch (_) {
      return (null, VaultNoteError.io);
    }
  }

  Future<(VaultFileListing?, VaultNoteError?)> search(
    VaultPaths paths,
    String query, {
    bool Function()? cancelled,
  }) async {
    final matches = <VaultFileEntry>[];
    final pending = <String>['.'];
    var visited = 0;
    try {
      while (pending.isNotEmpty) {
        if (cancelled?.call() == true) return (null, null);
        final folder = pending.removeLast();
        if (!await _notes.isSafePath(paths, folder)) continue;
        final directory = Directory(paths.projectFile(folder)!);
        if (!await directory.exists()) return (null, VaultNoteError.notFound);
        await for (final entry in directory.list(followLinks: false)) {
          if (cancelled?.call() == true) return (null, null);
          if (++visited > maxSearchVisits || matches.length >= maxEntries) {
            return (VaultFileListing(matches, truncated: true), null);
          }
          final relative = paths.relativeToProject(entry.path);
          if (relative == null || entry is Link) continue;
          if (entry is Directory && !p.basename(entry.path).startsWith('.')) {
            pending.add(relative);
          }
          if (entry is File &&
              entry.path.toLowerCase().endsWith('.md') &&
              relative.toLowerCase().contains(query.toLowerCase())) {
            matches.add(VaultFileEntry(path: relative, isDirectory: false));
          }
        }
      }
      matches.sort(
        (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
      );
      return (VaultFileListing(matches), null);
    } catch (_) {
      return (null, VaultNoteError.io);
    }
  }
}
