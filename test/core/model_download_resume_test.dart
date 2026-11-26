import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/services/app_storage_service.dart';
import 'package:installm/core/services/model_storage_service.dart';
import 'package:installm/features/model_selection/presentation/download_progress_provider.dart';
import 'package:path/path.dart' as p;

/// A chunked download reserves the whole file up front, so on a resumed model
/// the file length says "complete" while most of the bytes are still missing.
/// These pin the difference between "reserved" and "received", which is what a
/// progress bar and the free-space check must use.
void main() {
  late Directory temp;
  late ModelStorageService storage;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('installm_model_test');
    storage = ModelStorageService(
      appStorage: AppStorageService(documentsDirectory: temp, mobile: true),
    );
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  /// Writes a reserved model file plus its chunk metadata.
  Future<File> reservedModel(
    String name, {
    required int totalSize,
    required List<int> received,
  }) async {
    final dir = Directory(p.join(temp.path, 'models'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(List.filled(totalSize, 0));

    final chunkSize = (totalSize / received.length).ceil();
    final chunks = [
      for (var i = 0; i < received.length; i++)
        {
          'start': i * chunkSize,
          'end': i == received.length - 1 ? totalSize - 1 : (i + 1) * chunkSize,
          'received': received[i],
          'isFinished': false,
        },
    ];
    await File(
      '${file.path}.json',
    ).writeAsString(jsonEncode({'totalSize': totalSize, 'chunks': chunks}));
    return file;
  }

  test(
    'a resumed download counts received bytes, not the reservation',
    () async {
      await reservedModel('tiny.gguf', totalSize: 1000, received: [250, 250]);

      expect(await storage.getLocalFileSize('tiny.gguf'), 1000);
      expect(await storage.getDownloadedBytes('tiny.gguf'), 500);
      // The reservation must never read as an installed model.
      expect(await storage.isModelDownloaded('tiny.gguf'), isFalse);
    },
  );

  test('a finished download reports its file length', () async {
    final dir = Directory(p.join(temp.path, 'models'));
    await dir.create(recursive: true);
    await File(
      p.join(dir.path, 'done.gguf'),
    ).writeAsBytes([0x47, 0x47, 0x55, 0x46, ...List.filled(96, 0)]);

    expect(await storage.getDownloadedBytes('done.gguf'), 100);
    expect(await storage.isModelDownloaded('done.gguf'), isTrue);
  });

  test(
    'unreadable metadata reports nothing received and is not installed',
    () async {
      final dir = Directory(p.join(temp.path, 'models'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'broken.gguf'));
      await file.writeAsBytes(List.filled(800, 0));
      await File('${file.path}.json').writeAsString('{ not json');

      expect(await storage.getDownloadedBytes('broken.gguf'), 0);
      expect(await storage.isModelDownloaded('broken.gguf'), isFalse);
    },
  );

  test('progress never runs past its end', () {
    const over = DownloadProgress(received: 1200, total: 1000);
    const part = DownloadProgress(received: 250, total: 1000);
    const unknown = DownloadProgress(received: 250, total: 0);

    expect(over.progress, 1.0);
    expect(part.progress, 0.25);
    expect(unknown.progress, 0);
  });

  test('verifyDownloadedModel keeps GGUF check by default', () async {
    final dir = Directory(p.join(temp.path, 'models'));
    await dir.create(recursive: true);

    final validGguf = File(p.join(dir.path, 'valid.gguf'));
    await validGguf.writeAsBytes([0x47, 0x47, 0x55, 0x46, 1, 2, 3, 4]);
    await expectLater(
      storage.verifyDownloadedModel(
        validGguf.path,
        '${validGguf.path}.json',
        8,
      ),
      completes,
    );
    expect(validGguf.existsSync(), isTrue);

    final notGguf = File(p.join(dir.path, 'bad.gguf'));
    await notGguf.writeAsBytes([0x08, 0x01, 0x12, 0x00, 1, 2, 3, 4]);
    await expectLater(
      storage.verifyDownloadedModel(notGguf.path, '${notGguf.path}.json', 8),
      throwsStateError,
    );
    expect(notGguf.existsSync(), isFalse);
  });

  test(
    'verifyDownloadedModel accepts non-GGUF assets when verifyGguf is false',
    () async {
      final dir = Directory(p.join(temp.path, 'models'));
      await dir.create(recursive: true);

      final onnx = File(p.join(dir.path, 'whisper-tiny-encoder.int8.onnx'));
      await onnx.writeAsBytes([0x08, 0x01, 0x12, 0x00, 1, 2, 3, 4]);
      await expectLater(
        storage.verifyDownloadedModel(
          onnx.path,
          '${onnx.path}.json',
          8,
          verifyGguf: false,
        ),
        completes,
      );
      expect(onnx.existsSync(), isTrue);

      final truncated = File(p.join(dir.path, 'truncated.onnx'));
      await truncated.writeAsBytes([0x08, 0x01]);
      await expectLater(
        storage.verifyDownloadedModel(
          truncated.path,
          '${truncated.path}.json',
          8,
          verifyGguf: false,
        ),
        throwsStateError,
      );
      expect(truncated.existsSync(), isFalse);

      final empty = File(p.join(dir.path, 'empty.txt'));
      await empty.writeAsBytes(const <int>[]);
      await expectLater(
        storage.verifyDownloadedModel(
          empty.path,
          '${empty.path}.json',
          null,
          verifyGguf: false,
        ),
        throwsStateError,
      );
      expect(empty.existsSync(), isFalse);
    },
  );
}
