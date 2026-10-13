import 'dart:io';

import 'package:installm/core/data/app_identity_migration.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 4 ||
      arguments[0] != '--source' ||
      arguments[2] != '--destination') {
    stderr.writeln(
      'Quit both app installations first. Usage:\n'
      'dart run scripts/migrate_app_data.dart '
      '--source <previous-app-support-directory> '
      '--destination <new-app-support-directory>',
    );
    exitCode = 64;
    return;
  }
  try {
    await AppIdentityMigration.copySupportDirectory(
      source: Directory(arguments[1]),
      destination: Directory(arguments[3]),
    );
    stdout.writeln('Migration complete. Original data remains intact.');
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  }
}
