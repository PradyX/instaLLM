import 'dart:io';

import 'package:installm/features/vault/application/vault_notes_service.dart';
import 'package:installm/features/vault/domain/vault_paths.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';
import 'package:path/path.dart' as p;

/// Scan-to-note (Road Map 3 Phase 3.7).
///
/// Camera/page capture becomes an editable Markdown note in the vault folder:
/// the image is copied beside the note and referenced with a relative link,
/// plus a title the user can change. The note is editable from the moment it
/// lands — the scan is a starting point, not a finished artifact.
class ScanNoteService {
  const ScanNoteService({VaultNotesService? notes}) : _notes = notes;

  final VaultNotesService? _notes;

  /// Stages [imagePath] into the vault project and writes a note for it.
  ///
  /// Returns the note's relative path, or null when the image is missing or
  /// the write was refused (permissions, conflicts). Originals are never
  /// modified: the image is copied, never moved.
  Future<String?> scanToNote({
    required VaultPaths paths,
    required String imagePath,
    required String title,
    required VaultPermissions permissions,
  }) async {
    final source = File(imagePath);
    if (!source.existsSync()) return null;
    final safeTitle = title.trim().isEmpty ? 'Scan' : title.trim();
    final slug = safeTitle
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final base = slug.isEmpty ? 'scan' : slug;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final extension = p.extension(imagePath).toLowerCase();
    final imageName = '$base-$stamp${extension.isEmpty ? '.jpg' : extension}';
    final noteName = '$base-$stamp.md';

    final imageTarget = paths.projectFile(imageName);
    if (imageTarget == null) return null;
    try {
      await Directory(paths.projectDir).create(recursive: true);
      await source.copy(imageTarget);
    } catch (_) {
      return null;
    }

    final notes = _notes ?? const VaultNotesService();
    final error = await notes.writeNote(
      paths: paths,
      permissions: permissions,
      relativePath: noteName,
      content:
          '# $safeTitle\n\n![$safeTitle]($imageName)\n\n'
          '_Captured ${DateTime.now().toIso8601String()}. Edit this note freely._\n',
    );
    if (error != null) {
      try {
        await File(imageTarget).delete();
      } catch (_) {}
      return null;
    }
    return noteName;
  }
}
