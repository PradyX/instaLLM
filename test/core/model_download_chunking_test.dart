import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/services/app_storage_service.dart';
import 'package:installm/core/services/model_storage_service.dart';
import 'package:path/path.dart' as p;

/// Downloads against a loopback server so the chunked writer, the short-read
/// check and the resumable sidecar are exercised for real, without a device and
/// without the network.
///
/// The widgets binding is deliberately not initialised here: it replaces every
/// HttpClient with one that answers 400, which would make these tests pass or
/// fail for the wrong reason.
void main() {
  late Directory root;
  late HttpServer server;
  late ModelStorageService service;

  /// Bytes that differ from their own offsets, so a misplaced block of writes
  /// shows up as a mismatch rather than as a plausible file.
  List<int> payload(int length) =>
      List<int>.generate(length, (index) => (index * 7 + index ~/ 251) % 256);

  /// Answers HEAD with the length and each ranged GET with that slice, in
  /// 8 KB pieces as a real server would. [shortBy] cuts every body short, the
  /// way a server that closes early leaves a client with less than it asked for.
  Future<void> serve(List<int> bytes, {int? shortBy}) async {
    await for (final request in server) {
      if (request.method == 'HEAD') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentLength = bytes.length;
        await request.response.close();
        continue;
      }

      final range = request.headers.value('range');
      final match = range == null
          ? null
          : RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range);
      final start = match == null ? 0 : int.parse(match.group(1)!);
      final requestedEnd = match == null
          ? bytes.length - 1
          : int.parse(match.group(2)!);
      final end = requestedEnd >= bytes.length
          ? bytes.length - 1
          : requestedEnd;
      final slice = bytes.sublist(start, end + 1);
      final send = shortBy == null || shortBy > slice.length
          ? slice
          : slice.sublist(0, slice.length - shortBy);

      request.response
        ..statusCode = match == null ? HttpStatus.ok : HttpStatus.partialContent
        ..headers.set('content-range', 'bytes $start-$end/${bytes.length}');
      // No content length, so a short body still ends as a valid response and
      // the downloader's own byte check is what has to notice.
      request.response.headers.chunkedTransferEncoding = true;
      for (var offset = 0; offset < send.length; offset += 8192) {
        final pieceEnd = (offset + 8192) > send.length
            ? send.length
            : offset + 8192;
        request.response.add(send.sublist(offset, pieceEnd));
        await request.response.flush();
      }
      await request.response.close();
    }
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('installm-download-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    service = ModelStorageService(
      appStorage: AppStorageService(
        documentsDirectory: root,
        mobile: false,
        ios: false,
      ),
    );
  });

  tearDown(() async {
    await server.close(force: true);
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('a chunked download writes exactly the served bytes', () async {
    final bytes = payload(2 * 1024 * 1024);
    // Not awaited as a teardown: the serving loop ends when the server closes.
    final served = serve(bytes);
    served.catchError((_) {});

    final reported = <int>[];
    await service.downloadModel(
      'http://127.0.0.1:${server.port}/model.gguf',
      'chunked.gguf',
      onProgress: (received, total) => reported.add(received),
    );

    final file = File(p.join(await service.getModelDir(), 'chunked.gguf'));
    expect(await file.length(), bytes.length);
    expect(await file.readAsBytes(), bytes);
    // Finishing removes the sidecar that marks a download as resumable.
    expect(File('${file.path}.json').existsSync(), isFalse);
    expect(reported, isNotEmpty);
    expect(reported.last, bytes.length);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a body that ends early fails instead of counting as complete', () async {
    final bytes = payload(400000);
    final served = serve(bytes, shortBy: 50000);
    served.catchError((_) {});

    await expectLater(
      service.downloadModel(
        'http://127.0.0.1:${server.port}/short.gguf',
        'short.gguf',
      ),
      throwsA(
        isA<DioException>().having(
          (error) => error.error.toString(),
          'error',
          contains('ended early'),
        ),
      ),
    );

    // What did arrive stays with its metadata, so the next attempt resumes
    // instead of starting the model over.
    final file = File(p.join(await service.getModelDir(), 'short.gguf'));
    expect(File('${file.path}.json').existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
