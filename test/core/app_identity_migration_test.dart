import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/data/app_identity_migration.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory source;
  late Directory destination;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('installm_identity_test');
    source = await Directory(p.join(root.path, 'previous')).create();
    destination = Directory(p.join(root.path, 'installm'));
  });

  tearDown(() async => root.delete(recursive: true));

  Future<void> migrate() => AppIdentityMigration.copySupportDirectory(
    source: source,
    destination: destination,
  );

  Future<File> sourceFile(String name, String content) async {
    final file = File(p.join(source.path, name));
    await file.parent.create(recursive: true);
    return file.writeAsString(content);
  }

  test(
    'copies nested and corrupt data exactly and preserves original',
    () async {
      final original = await sourceFile('conversations/a.json', '{broken');
      await sourceFile('appearance/settings.json', '{"version":2}');
      await migrate();
      expect(await original.readAsString(), '{broken');
      expect(
        await File(
          p.join(destination.path, 'conversations/a.json'),
        ).readAsString(),
        '{broken',
      );
      expect(
        await File(
          p.join(destination.path, 'appearance/settings.json'),
        ).readAsString(),
        '{"version":2}',
      );
      final manifest =
          jsonDecode(
                await File(
                  p.join(destination.path, AppIdentityMigration.manifestName),
                ).readAsString(),
              )
              as Map;
      expect(manifest['schemaVersion'], 1);
      expect(manifest['copiedFiles'], 2);
      expect(manifest['sourcePreserved'], isTrue);
      await expectLater(migrate(), throwsA(isA<FileSystemException>()));
      expect(await original.readAsString(), '{broken');
    },
  );

  test('partial stores and empty source remain usable', () async {
    await Directory(p.join(source.path, 'conversations')).create();
    await migrate();
    expect(
      await Directory(p.join(destination.path, 'conversations')).exists(),
      isTrue,
    );
    expect(await source.exists(), isTrue);
  });

  test(
    'renames Linux compatibility file without interpreting contents',
    () async {
      final original = await sourceFile(
        'compat_secure_storage/old.json',
        '{bad',
      );
      await migrate();
      expect(
        await File(
          p.join(
            destination.path,
            'compat_secure_storage/installm_secure_store.json',
          ),
        ).readAsString(),
        '{bad',
      );
      expect(await original.readAsString(), '{bad');
    },
  );

  test('ambiguous compatibility files do not publish partial data', () async {
    await sourceFile('compat_secure_storage/one.json', '{}');
    await sourceFile('compat_secure_storage/two.json', '{}');
    await expectLater(migrate(), throwsA(isA<FileSystemException>()));
    expect(await destination.exists(), isFalse);
    expect(
      await source.list(recursive: true).where((e) => e is File).length,
      2,
    );
    expect(await root.list().length, 1);
  });

  test('refuses missing source without creating destination', () async {
    await source.delete();
    await expectLater(migrate(), throwsA(isA<FileSystemException>()));
    expect(await destination.exists(), isFalse);
  });

  test('refuses existing destination without changing either store', () async {
    await destination.create();
    final existing = await File(
      p.join(destination.path, 'keep'),
    ).writeAsString('x');
    await sourceFile('old', 'y');
    await expectLater(migrate(), throwsA(isA<FileSystemException>()));
    expect(await existing.readAsString(), 'x');
    expect(await File(p.join(source.path, 'old')).readAsString(), 'y');
  });

  test('refuses overlapping directories before copying', () async {
    await expectLater(
      AppIdentityMigration.copySupportDirectory(
        source: source,
        destination: Directory(p.join(source.path, 'nested')),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await source.list().length, 0);
  });

  test('refuses dangling destination links without replacing them', () async {
    final link = await Link(destination.path).create('missing');
    await expectLater(migrate(), throwsA(isA<FileSystemException>()));
    expect(await link.target(), 'missing');
  });

  test(
    'preserves links to originals without traversing model weights',
    () async {
      final models = await Directory(p.join(root.path, 'models')).create();
      await File(
        p.join(models.path, 'model.gguf'),
      ).writeAsString('model bytes');
      await Link(p.join(source.path, 'models')).create('../models');
      await migrate();
      final copied = Link(p.join(destination.path, 'models'));
      expect(await copied.target(), await models.resolveSymbolicLinks());
      expect(
        await File(p.join(copied.path, 'model.gguf')).readAsString(),
        'model bytes',
      );
      expect(await Link(p.join(source.path, 'models')).target(), '../models');
    },
  );
}
