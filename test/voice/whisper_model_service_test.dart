import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:installm/core/services/model_storage_service.dart';
import 'package:installm/features/voice/data/whisper_model_service.dart';
import 'package:installm/features/voice/domain/whisper_model_option.dart';

/// Storage that writes into a temporary directory instead of the app's model
/// directory, so the file rules can be exercised without a device.
///
/// Downloads write exactly the bytes the catalog expects, because the service
/// decides what is installed from the size on disk.
class _TempModelStorage extends ModelStorageService {
  _TempModelStorage(this.directory);

  final Directory directory;

  /// File names a download should leave short, mimicking a connection that
  /// dropped mid-file.
  final Set<String> truncatedFiles = <String>{};

  /// File names a download should leave with progress metadata next to them,
  /// which is what an interrupted download looks like on disk.
  final Set<String> unfinishedFiles = <String>{};

  final List<String> downloadedUrls = <String>[];

  @override
  Future<String> getLocalFilePath(String fileName) async {
    return p.join(directory.path, fileName);
  }

  @override
  Future<void> downloadModel(
    String url,
    String fileName, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    downloadedUrls.add(url);
    final bytes = _expectedBytes(fileName);
    final written = truncatedFiles.contains(fileName) ? bytes ~/ 4 : bytes;
    final file = File(p.join(directory.path, fileName));
    await file.writeAsBytes(List<int>.filled(written, 0));
    onProgress?.call(written, bytes);
    if (unfinishedFiles.contains(fileName)) {
      await File('${file.path}.json').writeAsString('{"totalSize": $bytes}');
    }
  }

  @override
  Future<void> deleteModel(String fileName) async {
    final file = File(p.join(directory.path, fileName));
    if (file.existsSync()) await file.delete();
    final sidecar = File('${file.path}.json');
    if (sidecar.existsSync()) await sidecar.delete();
  }

  /// Size the catalog says [fileName] should be.
  static int _expectedBytes(String fileName) {
    for (final model in WhisperModelCatalog.models) {
      for (final file in model.files) {
        if (file.fileName == fileName) return file.bytes;
      }
    }
    return 1024;
  }
}

void main() {
  late Directory tempDir;
  late _TempModelStorage storage;
  late WhisperModelService service;

  final tiny = WhisperModelCatalog.models[0];
  final base = WhisperModelCatalog.models[1];
  final small = WhisperModelCatalog.models[2];

  Future<void> writeModelFiles(
    WhisperModelOption option, {
    bool withSidecar = false,
    bool truncate = false,
  }) async {
    for (final file in option.files) {
      final written = truncate ? file.bytes ~/ 4 : file.bytes;
      final target = File(p.join(tempDir.path, file.fileName));
      await target.writeAsBytes(List<int>.filled(written, 0));
      if (withSidecar) {
        await File('${target.path}.json').writeAsString('{"totalSize": 5}');
      }
    }
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('installm_whisper');
    storage = _TempModelStorage(tempDir);
    service = WhisperModelService(storage);
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('starts with no models installed', () async {
    expect(await service.installed(), isEmpty);
    expect(await service.isInstalled(tiny), isFalse);
    expect(await service.resolve(tiny.id), isNull);
  });

  test('a model is installed only when all three files are complete', () async {
    await writeModelFiles(tiny);

    final installed = await service.installed();
    expect(installed.map((model) => model.option.id), [tiny.id]);
    expect(
      installed.single.encoderPath,
      p.join(tempDir.path, tiny.encoder.fileName),
    );
    expect(
      installed.single.decoderPath,
      p.join(tempDir.path, tiny.decoder.fileName),
    );
    expect(
      installed.single.tokensPath,
      p.join(tempDir.path, tiny.tokens.fileName),
    );

    // One file missing is a model that cannot run: the engine needs all three.
    await File(p.join(tempDir.path, tiny.decoder.fileName)).delete();
    expect(await service.isInstalled(tiny), isFalse);
  });

  test('an unfinished or truncated file is not an installed model', () async {
    await writeModelFiles(base, withSidecar: true);
    expect(await service.isInstalled(base), isFalse);

    await writeModelFiles(small, truncate: true);
    expect(await service.isInstalled(small), isFalse);
  });

  test('lists installed models smallest first', () async {
    await writeModelFiles(small);
    await writeModelFiles(tiny);

    final installed = await service.installed();
    expect(installed.map((model) => model.option.id), [tiny.id, small.id]);
  });

  test('resolution prefers the chosen model', () async {
    await writeModelFiles(tiny);
    await writeModelFiles(small);

    expect((await service.resolve(small.id))?.option.id, small.id);
  });

  test('resolution falls back to the smallest installed model', () async {
    await writeModelFiles(tiny);
    await writeModelFiles(small);

    // Never downloaded, and removed since: both keep transcription working
    // with what the device actually has.
    expect((await service.resolve(base.id))?.option.id, tiny.id);
    expect((await service.resolve(null))?.option.id, tiny.id);
  });

  test(
    'downloads every file of a model and reports one progress total',
    () async {
      final received = <int>[];
      final totals = <int>[];
      await service.download(
        tiny,
        onProgress: (got, total) {
          received.add(got);
          totals.add(total);
        },
      );

      expect(storage.downloadedUrls, [
        tiny.encoder.url,
        tiny.decoder.url,
        tiny.tokens.url,
      ]);
      expect(await service.isInstalled(tiny), isTrue);
      // Progress never goes backwards and ends at the whole model.
      expect(received, orderedEquals(<int>[...received]..sort()));
      expect(received.last, tiny.approximateBytes);
      expect(totals, everyElement(tiny.approximateBytes));
    },
  );

  test('a download that stops early does not count as installed', () async {
    storage.truncatedFiles.add(tiny.decoder.fileName);

    await expectLater(
      service.download(tiny),
      throwsA(
        predicate(
          (error) => error.toString().contains('did not finish'),
          'mentions that the download did not finish',
        ),
      ),
    );
    expect(await service.isInstalled(tiny), isFalse);
    expect(await service.resolve(tiny.id), isNull);
  });

  test('a resumable download skips the files it already finished', () async {
    // What a cancelled download leaves behind: the encoder is complete and
    // recorded, the other two never arrived.
    await File(
      p.join(tempDir.path, tiny.encoder.fileName),
    ).writeAsBytes(List<int>.filled(tiny.encoder.bytes, 0));

    await service.download(tiny);

    expect(storage.downloadedUrls, [tiny.decoder.url, tiny.tokens.url]);
    expect(await service.isInstalled(tiny), isTrue);
  });

  test('removing a model deletes every file and download progress', () async {
    await writeModelFiles(tiny, withSidecar: true);

    await service.remove(tiny);

    for (final file in tiny.files) {
      expect(
        File(p.join(tempDir.path, file.fileName)).existsSync(),
        isFalse,
        reason: file.fileName,
      );
      expect(
        File(p.join(tempDir.path, '${file.fileName}.json')).existsSync(),
        isFalse,
        reason: file.fileName,
      );
    }
  });

  test('removing refuses files this catalog does not own', () async {
    const stranger = WhisperModelOption(
      id: 'someone-elses-model',
      name: 'Stranger',
      detail: 'not ours',
      encoder: WhisperModelFile(
        fileName: 'stranger-encoder.onnx',
        url: 'https://example.invalid/encoder.onnx',
        bytes: 1024,
      ),
      decoder: WhisperModelFile(
        fileName: 'stranger-decoder.onnx',
        url: 'https://example.invalid/decoder.onnx',
        bytes: 1024,
      ),
      tokens: WhisperModelFile(
        fileName: 'stranger-tokens.txt',
        url: 'https://example.invalid/tokens.txt',
        bytes: 1024,
      ),
    );
    for (final file in stranger.files) {
      await File(
        p.join(tempDir.path, file.fileName),
      ).writeAsBytes(List<int>.filled(1024, 0));
    }

    await service.remove(stranger);

    for (final file in stranger.files) {
      expect(
        File(p.join(tempDir.path, file.fileName)).existsSync(),
        isTrue,
        reason: file.fileName,
      );
    }
  });
}
