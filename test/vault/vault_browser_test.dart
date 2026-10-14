import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/vault/application/vault_browser_service.dart';
import 'package:installm/features/vault/application/vault_browser_controller.dart';
import 'package:installm/features/vault/application/vault_notes_service.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';
import 'package:installm/features/vault/domain/vault_paths.dart';

class _DelayedBrowser extends VaultBrowserService {
  final pending = Completer<(VaultFileListing?, VaultNoteError?)>();
  @override
  Future<(VaultFileListing?, VaultNoteError?)> list(
    VaultPaths paths,
    String folder,
  ) => paths.vaultRoot.endsWith('slow')
      ? pending.future
      : super.list(paths, folder);
}

void main() {
  late Directory root;
  late VaultRegistration vault;
  late VaultBrowserController controller;
  var registered = true;
  setUp(() {
    root = Directory.systemTemp.createTempSync('vault-browser-');
    vault = VaultRegistration.create(
      id: 'v',
      name: 'Notes',
      rootPath: root.path,
    );
    registered = true;
    controller = VaultBrowserController(
      service: const VaultBrowserService(),
      isRegistered: (_) => registered,
    );
  });
  tearDown(() {
    controller.dispose();
    root.deleteSync(recursive: true);
  });
  File write(String path, String content) {
    final file = File('${root.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  test(
    'lazy listing and filename search exclude links, non-Markdown and hidden folders',
    () async {
      write('Research/result.MD', '# Local research');
      write('Project.md', '# Project');
      write('private.bin', 'Do not read');
      write('.hidden/secret.md', 'Do not read');
      final outside = Directory.systemTemp.createTempSync('outside-vault-');
      addTearDown(() => outside.deleteSync(recursive: true));
      File('${outside.path}/secret.md').writeAsStringSync('Outside');
      Link('${root.path}/linked').createSync(outside.path);
      await controller.selectVault(vault);
      expect(controller.state.folders.keys, ['.']);
      expect(controller.state.folders['.']!.entries.map((e) => e.name), [
        'Research',
        'Project.md',
      ]);
      await controller.toggleFolder('Research');
      expect(
        controller.state.folders['Research']!.entries.single.path,
        'Research/result.MD',
      );
      await controller.search('RESULT');
      expect(
        controller.state.results!.entries.single.path,
        'Research/result.MD',
      );
      expect(
        (await const VaultBrowserService().list(
          VaultPaths(vaultRoot: root.path, projectPath: ''),
          'linked',
        )).$2,
        VaultNoteError.outsideProject,
      );
    },
  );

  test(
    'user edits persist verbatim, preserve other notes, and do not change bot ownership',
    () async {
      final file = write('summary.md', '# Initial\n\nOriginal.');
      final other = write('other.md', 'Keep this.');
      await controller.selectVault(vault);
      await controller.openNote('summary.md');
      expect(
        await controller.save('# User edit\n\nExact whitespace.\n'),
        isTrue,
      );
      expect(file.readAsStringSync(), '# User edit\n\nExact whitespace.\n');
      expect(other.readAsStringSync(), 'Keep this.');
      final reload = VaultBrowserController(
        service: const VaultBrowserService(),
        isRegistered: (_) => true,
      );
      addTearDown(reload.dispose);
      await reload.selectVault(vault);
      await reload.openNote('summary.md');
      expect(reload.state.note?.content, file.readAsStringSync());
      expect(await controller.delete(), isTrue);
      expect(file.existsSync(), isFalse);
      expect(other.existsSync(), isTrue);
      expect(controller.state.note, isNull);
      expect(controller.state.folders['.']!.entries.map((e) => e.path), [
        'other.md',
      ]);
    },
  );

  test('UTF-8 BOM notes can be edited and deleted conditionally', () async {
    final file = write('bom.md', '\ufeff# Original');
    await controller.selectVault(vault);
    await controller.openNote('bom.md');
    expect(await controller.save('# Edited'), isTrue);
    expect(file.readAsStringSync(), '# Edited');
    file.writeAsStringSync('\ufeff# Another');
    await controller.refresh();
    expect(await controller.delete(), isTrue);
    expect(file.existsSync(), isFalse);
  });

  test(
    'edits and deletes reject concurrent file changes even with the same timestamp',
    () async {
      final file = write('summary.md', 'Initial');
      await controller.selectVault(vault);
      await controller.openNote('summary.md');
      final at = file.statSync().modified;
      file.writeAsStringSync('Changed');
      file.setLastModifiedSync(at);
      expect(await controller.save('My draft'), isFalse);
      expect(controller.state.error, VaultNoteError.conflict);
      expect(controller.state.note?.content, 'Initial');
      expect(await controller.delete(), isFalse);
      expect(file.readAsStringSync(), 'Changed');
      await controller.refresh();
      expect(await controller.save('My draft'), isTrue);
      expect(file.readAsStringSync(), 'My draft');
    },
  );

  test(
    'unregistered roots, child links, missing and oversized notes are safe',
    () async {
      write('large.md', 'x' * (VaultBrowserController.maxNoteBytes + 1));
      final file = write('small.md', 'Keep');
      await controller.selectVault(vault);
      await controller.openNote('large.md');
      expect(controller.state.error, VaultNoteError.tooLarge);
      await controller.openNote('missing.md');
      expect(controller.state.error, VaultNoteError.notFound);
      await controller.openNote('small.md');
      registered = false;
      expect(await controller.save('Would overwrite'), isFalse);
      expect(await controller.delete(), isFalse);
      expect(file.readAsStringSync(), 'Keep');
      registered = true;
      file.deleteSync();
      Link(file.path).createSync('${root.path}/large.md');
      expect(await controller.delete(), isFalse);
      expect(controller.state.error, VaultNoteError.outsideProject);
      expect(
        File('${root.path}/large.md').lengthSync(),
        VaultBrowserController.maxNoteBytes + 1,
      );
    },
  );

  test(
    'folder/search limits and cancellation do not read arbitrary large trees',
    () async {
      for (var i = 0; i < VaultBrowserService.maxEntries + 1; i++) {
        write('$i.md', 'note');
      }
      final paths = VaultPaths(vaultRoot: root.path, projectPath: '');
      final (listing, error) = await const VaultBrowserService().list(
        paths,
        '.',
      );
      expect(error, isNull);
      expect(listing!.entries, hasLength(VaultBrowserService.maxEntries));
      expect(listing.truncated, isTrue);
      final (results, _) = await const VaultBrowserService().search(
        paths,
        '.md',
      );
      expect(results!.entries, hasLength(VaultBrowserService.maxEntries));
      expect(results.truncated, isTrue);
      expect(
        (await const VaultBrowserService().search(
          paths,
          'note',
          cancelled: () => true,
        )).$1,
        isNull,
      );
    },
  );

  test('late folder reads cannot replace the newly selected vault', () async {
    controller.dispose();
    final service = _DelayedBrowser();
    controller = VaultBrowserController(
      service: service,
      isRegistered: (_) => true,
    );
    final old = vault.copyWith(rootPath: '${root.path}/slow');
    final pending = controller.selectVault(old);
    await controller.selectVault(vault);
    service.pending.complete((
      const VaultFileListing([
        VaultFileEntry(path: 'old.md', isDirectory: false),
      ]),
      null,
    ));
    await pending;
    expect(controller.state.vault?.rootPath, root.path);
    expect(controller.state.folders['.']!.entries, isEmpty);
  });
}
