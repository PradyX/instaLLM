import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:installm/core/services/app_storage_service.dart';
import 'package:installm/core/services/model_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory documents;
  late AppStorageService storage;
  setUp(() {
    documents = Directory.systemTemp.createTempSync('installm-storage-');
    storage = AppStorageService(documentsDirectory: documents, mobile: false);
  });
  tearDown(() => documents.deleteSync(recursive: true));

  File write(String relative, String contents) {
    final file = File(p.join(documents.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
    return file;
  }

  test(
    'desktop creates the named root; mobile uses private documents',
    () async {
      final root = await storage.root;
      expect(root.path, p.join(documents.path, 'InstaLLM'));
      for (final name in ['models', 'attachments', 'vault']) {
        expect(await Directory(p.join(root.path, name)).exists(), isTrue);
      }
      for (final ios in [false, true]) {
        final privateDocuments = Directory(
          p.join(documents.path, 'mobile-$ios'),
        );
        final mobile = AppStorageService(
          documentsDirectory: privateDocuments,
          mobile: true,
          ios: ios,
        );
        expect((await mobile.root).path, privateDocuments.path);
        expect(
          await Directory(p.join(privateDocuments.path, 'vault')).exists(),
          isTrue,
        );
        expect(
          await Directory(p.join(privateDocuments.path, 'InstaLLM')).exists(),
          isFalse,
        );
      }
    },
  );

  test(
    'moves managed files and partial downloads; leaves unrelated files',
    () async {
      write('models/one.gguf', 'GGUFmodel');
      write('models/one.gguf.json', '{"received":4}');
      write('attachments/c1/image.jpg', 'image');
      final external = write('external/model.gguf', 'external');
      final unrelated = write('appConfig.json', 'not ours');
      final service = ModelStorageService(appStorage: storage);
      expect(
        await File(
          p.join(await service.getModelDir(), 'one.gguf'),
        ).readAsString(),
        'GGUFmodel',
      );
      expect(
        await File(
          p.join(await service.getModelDir(), 'one.gguf.json'),
        ).readAsString(),
        '{"received":4}',
      );
      expect(
        await storage.resolveAttachmentPath(
          p.join(documents.path, 'attachments/c1/image.jpg'),
        ),
        p.join(await service.getAttachmentsDir(), 'c1/image.jpg'),
      );
      expect(
        await Directory(p.join(documents.path, 'models')).exists(),
        isFalse,
      );
      expect(await external.readAsString(), 'external');
      expect(await unrelated.readAsString(), 'not ours');
    },
  );

  test(
    'resumes mixed source/destination after interruption and verifies copies',
    () async {
      write('InstaLLM/models/already.gguf', 'done');
      write('models/one.gguf', 'GGUF${'x' * 200000}');
      write('attachments/c1/a.jpg', 'photo');
      var fail = true;
      storage = AppStorageService(
        documentsDirectory: documents,
        mobile: false,
        renameFile: (source, target) async {
          if (fail && source.path.endsWith('a.jpg')) {
            throw const FileSystemException('simulated interruption');
          }
          throw const FileSystemException(
            'cross volume',
            '',
            OSError('EXDEV', 18),
          );
        },
      );
      await expectLater(storage.root, throwsA(isA<FileSystemException>()));
      expect(
        await File(p.join(documents.path, 'InstaLLM/models/one.gguf')).length(),
        200004,
      );
      expect(
        await File(
          p.join(documents.path, 'attachments/c1/a.jpg'),
        ).readAsString(),
        'photo',
      );
      fail = false;
      final root = await storage.root;
      expect(
        await File(p.join(root.path, 'attachments/c1/a.jpg')).readAsString(),
        'photo',
      );
      expect(
        await Directory(p.join(documents.path, 'attachments')).exists(),
        isFalse,
      );
      // Fresh service is idempotent, and concurrent instances serialize by root.
      await Future.wait([
        AppStorageService(documentsDirectory: documents, mobile: false).root,
        AppStorageService(documentsDirectory: documents, mobile: false).root,
      ]);
      expect(
        await File(p.join(root.path, 'models/already.gguf')).readAsString(),
        'done',
      );
    },
  );

  test(
    'conflicting names preserve both files; identical duplicates resume',
    () async {
      final source = write('models/a.gguf', 'original');
      final destination = write('InstaLLM/models/a.gguf', 'different');
      await expectLater(storage.root, throwsA(isA<FileSystemException>()));
      expect(await source.readAsString(), 'original');
      expect(await destination.readAsString(), 'different');
      expect(await storage.modelPath('a.gguf'), source.path);
      await destination.writeAsString('original');
      await storage.root;
      expect(await source.exists(), isFalse);
      expect(await destination.readAsString(), 'original');
    },
  );

  test(
    'partial migration keeps model reads usable and refuses new writes',
    () async {
      write('models/a.gguf', 'GGUFmodel');
      final photo = write('attachments/c1/a.jpg', 'original');
      write('InstaLLM/attachments/c1/a.jpg', 'different');
      final service = ModelStorageService(appStorage: storage);
      expect(await service.isModelDownloaded('a.gguf'), isTrue);
      expect(
        await File(await service.getLocalFilePath('a.gguf')).readAsString(),
        'GGUFmodel',
      );
      expect(await storage.resolveAttachmentPath(photo.path), photo.path);
      await expectLater(
        service.getAttachmentsDir(),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test('links never move or mutate external sources', () async {
    final external = write('external/a.gguf', 'external');
    final link = Link(p.join(documents.path, 'models/a.gguf'));
    await link.parent.create(recursive: true);
    await link.create(external.path);
    await expectLater(storage.root, throwsA(isA<FileSystemException>()));
    expect(await link.exists(), isTrue);
    expect(await external.readAsString(), 'external');
  });

  test(
    'external model records inside the legacy folder remain in place',
    () async {
      final external = write('models/external.gguf', 'external');
      final projector = write('models/nested/projector.gguf', 'projector');
      write('models/managed.gguf', 'managed');
      storage = AppStorageService(
        documentsDirectory: documents,
        mobile: false,
        externalModelPaths: {external.path, projector.path},
      );
      final root = await storage.root;
      expect(await external.readAsString(), 'external');
      expect(await projector.readAsString(), 'projector');
      expect(
        await File(p.join(root.path, 'models/managed.gguf')).readAsString(),
        'managed',
      );
      expect(
        await File(p.join(root.path, 'models/external.gguf')).exists(),
        isFalse,
      );
      await AppStorageService(
        documentsDirectory: documents,
        mobile: false,
        externalModelPaths: {external.path, projector.path},
      ).root;
      expect(await external.exists(), isTrue);
    },
  );

  test(
    'real registry lookup protects external records and refuses corrupt ownership',
    () async {
      final external = write('models/reference.gguf', 'external');
      write('models/managed.gguf', 'managed');
      String raw = jsonEncode({
        'models': [
          {'externalPath': external.path},
        ],
      });
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => documents.path,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (_) async => raw,
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
      });
      await AppStorageService(mobile: false).root;
      expect(await external.readAsString(), 'external');
      final remaining = write('models/new.gguf', 'GGUFnew');
      raw = 'invalid registry';
      storage = AppStorageService(mobile: false);
      await expectLater(storage.root, throwsA(isA<FileSystemException>()));
      expect(await remaining.readAsString(), 'GGUFnew');
      expect(await storage.modelPath('new.gguf'), remaining.path);
    },
  );

  test(
    'restart removes only the scratch file recorded by its copy journal',
    () async {
      write('models/a.gguf', 'GGUForiginal');
      final target = p.join(documents.path, 'InstaLLM/models/a.gguf');
      final temporary = write(
        'InstaLLM/models/a.gguf.migration-123.tmp',
        'partial',
      );
      final unrecorded = write('InstaLLM/models/other.tmp', 'not ours');
      write(
        'InstaLLM/.storage-migration.json',
        jsonEncode({
          'version': 1,
          'complete': false,
          'pendingCopy': {'target': target, 'temporary': temporary.path},
        }),
      );
      await storage.root;
      expect(await temporary.exists(), isFalse);
      expect(await unrecorded.readAsString(), 'not ours');
      expect(await File(target).readAsString(), 'GGUForiginal');
    },
  );

  test(
    'marker corruption is preserved; future versions refuse migration',
    () async {
      final marker = write('InstaLLM/.storage-migration.json', 'broken');
      await storage.root;
      expect(await marker.readAsString(), contains('"version":1'));
      final preserved = marker.parent.listSync().whereType<File>().where(
        (f) => f.path.contains('.preserved-'),
      );
      expect(preserved, hasLength(1));
      expect(preserved.single.readAsStringSync(), 'broken');
      marker.writeAsStringSync(jsonEncode({'version': 99}));
      final source = write('models/a.gguf', 'original');
      await expectLater(
        AppStorageService(documentsDirectory: documents, mobile: false).root,
        throwsA(isA<FileSystemException>()),
      );
      expect(await source.readAsString(), 'original');
      expect(await marker.readAsString(), '{"version":99}');
    },
  );

  test(
    'attachment resolution retains chat ownership and external paths',
    () async {
      write('attachments/c1/shared.jpg', 'one');
      write('attachments/c2/shared.jpg', 'two');
      await storage.root;
      final missing = p.join(documents.path, 'external/shared.jpg');
      expect(await storage.resolveAttachmentPath(missing), missing);
      final missingChat = p.join(documents.path, 'attachments/c3/shared.jpg');
      expect(await storage.resolveAttachmentPath(missingChat), missingChat);
      final resolved = await storage.resolveAttachmentPath(
        p.join(documents.path, 'attachments/c2/shared.jpg'),
      );
      expect(await File(resolved).readAsString(), 'two');
    },
  );

  test(
    'iOS resolves restored sandbox paths, desktop does not adopt them',
    () async {
      const old =
          '/private/var/mobile/Containers/Data/Application/OLD/Documents/attachments/c1/a.jpg';
      write('attachments/c1/a.jpg', 'restored');
      final ios = AppStorageService(
        documentsDirectory: documents,
        mobile: true,
        ios: true,
      );
      expect(
        await ios.resolveAttachmentPath(old),
        p.join(documents.path, 'attachments/c1/a.jpg'),
      );
      expect(await storage.resolveAttachmentPath(old), old);
    },
  );
}
