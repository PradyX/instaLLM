import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/vault/data/vault_store.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';
import 'package:path/path.dart' as p;

/// The registry moved from `obsidian/vaults.json` to `vault/vaults.json` on
/// 2026-10-14. These tests are about that move only: a registered vault must
/// survive it, and a file this build already wrote must never be replaced by
/// an older one.
void main() {
  group('VaultStore.resolveFile', () {
    late Directory support;

    setUp(() {
      support = Directory.systemTemp.createTempSync('vault_store_test');
    });

    tearDown(() {
      if (support.existsSync()) support.deleteSync(recursive: true);
    });

    Directory legacyDirectory() =>
        Directory(p.join(support.path, 'obsidian'))
          ..createSync(recursive: true);

    File legacyFile() => File(p.join(legacyDirectory().path, 'vaults.json'));

    File targetFile() => File(p.join(support.path, 'vault', 'vaults.json'));

    test('creates the new location when nothing was stored before', () async {
      final resolved = await VaultStore.resolveFile(support);
      expect(resolved.path, targetFile().path);
      expect(VaultStore(resolved).load().vaults, isEmpty);
    });

    test('carries a registry written before the rename over', () async {
      final vault = VaultRegistration.create(
        name: 'Notes',
        rootPath: p.join(support.path, 'my-vault'),
      );
      expect(
        VaultStore(legacyFile()).save(VaultsSnapshot(vaults: [vault])),
        isTrue,
        reason: 'the fixture must be a real stored registry',
      );

      final resolved = await VaultStore.resolveFile(support);

      expect(resolved.path, targetFile().path);
      expect(resolved.existsSync(), isTrue);
      final carried = VaultStore(resolved).load();
      expect(carried.vaults.single.id, vault.id);
      expect(carried.vaults.single.rootPath, vault.rootPath);
    });

    test('leaves a registry this build already wrote alone', () async {
      final current = VaultRegistration.create(
        name: 'Current',
        rootPath: p.join(support.path, 'current'),
      );
      targetFile()
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'version': 1,
            'vaults': [current.toJson()],
            'bindings': const [],
          }),
        );
      final stale = VaultRegistration.create(
        name: 'Stale',
        rootPath: p.join(support.path, 'stale'),
      );
      expect(
        VaultStore(legacyFile()).save(VaultsSnapshot(vaults: [stale])),
        isTrue,
      );

      final resolved = await VaultStore.resolveFile(support);

      expect(VaultStore(resolved).load().vaults.single.id, current.id);
      // The older file is still where it was: nothing is deleted to migrate.
      expect(legacyFile().existsSync(), isTrue);
    });

    test(
      'starts empty rather than failing on an unreadable legacy file',
      () async {
        legacyFile().writeAsStringSync('{not json at all');

        final resolved = await VaultStore.resolveFile(support);

        expect(resolved.path, targetFile().path);
        expect(VaultStore(resolved).load().vaults, isEmpty);
      },
    );
  });
}
