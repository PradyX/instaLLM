import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Explicit desktop migration into a new app identity. The original stays
/// intact, including malformed files, external references and credentials.
/// No runtime store schemas change and no model weights are duplicated.
class AppIdentityMigration {
  static const schemaVersion = 1;
  static const manifestName = 'identity_migration.v1.json';

  static Future<void> copySupportDirectory({
    required Directory source,
    required Directory destination,
  }) async {
    if (!await source.exists()) {
      throw const FileSystemException(
        'Source support directory does not exist.',
      );
    }
    final sourcePath = await source.resolveSymbolicLinks();
    await destination.parent.create(recursive: true);
    final destinationPath = p.join(
      await destination.parent.resolveSymbolicLinks(),
      p.basename(destination.path),
    );
    if (p.equals(sourcePath, destinationPath) ||
        p.isWithin(sourcePath, destinationPath) ||
        p.isWithin(destinationPath, sourcePath)) {
      throw const FileSystemException(
        'Source and destination must not overlap.',
      );
    }
    if (await FileSystemEntity.type(destinationPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FileSystemException(
        'Destination already exists. Migration never overwrites existing data.',
      );
    }

    final staging = await destination.parent.createTemp('.installm-migration-');
    try {
      var copiedFiles = 0;
      await for (final entity in Directory(
        sourcePath,
      ).list(recursive: true, followLinks: false)) {
        final relative = p.relative(entity.path, from: sourcePath);
        final target = p.join(staging.path, relative);
        if (entity is Directory) {
          await Directory(target).create(recursive: true);
        } else if (entity is File) {
          await File(target).parent.create(recursive: true);
          await entity.copy(target);
          copiedFiles++;
        } else if (entity is Link) {
          await File(target).parent.create(recursive: true);
          // Relative links retain their original meaning, never redirect them
          // silently into a different app directory.
          final linkTarget = await entity.target();
          await Link(target).create(
            p.isAbsolute(linkTarget)
                ? linkTarget
                : p.normalize(p.join(p.dirname(entity.path), linkTarget)),
          );
        }
      }

      // The Linux compatibility store's filename followed the app brand.
      // Only this dedicated directory is considered; ambiguous stores fail
      // without publishing a partial destination or touching the original.
      final compatibility = Directory(
        p.join(staging.path, 'compat_secure_storage'),
      );
      if (await compatibility.exists()) {
        final stores = await compatibility
            .list()
            .where(
              (entry) => entry is File && p.extension(entry.path) == '.json',
            )
            .toList();
        if (stores.length > 1) {
          throw const FileSystemException(
            'Multiple compatibility stores found. Resolve them before migration.',
          );
        }
        if (stores.length == 1) {
          await (stores.single as File).rename(
            p.join(compatibility.path, 'installm_secure_store.json'),
          );
        }
      }
      final manifest = File(p.join(staging.path, manifestName));
      if (await manifest.exists()) {
        throw const FileSystemException(
          'Source already contains an identity migration record.',
        );
      }
      await manifest.writeAsString(
        jsonEncode({
          'schemaVersion': schemaVersion,
          'app': 'InstaLLM',
          'copiedFiles': copiedFiles,
          'sourcePreserved': true,
        }),
        flush: true,
      );
      if (await FileSystemEntity.type(destinationPath, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FileSystemException(
          'Destination appeared during migration.',
        );
      }
      await staging.rename(destinationPath);
    } finally {
      // Only the temporary directory this invocation created is removed.
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }
}
