import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/services/hugging_face_repository_service.dart';

/// A Dio adapter that fails every request the way the network can fail.
class _FailingAdapter implements HttpClientAdapter {
  _FailingAdapter(this.failure);

  final DioException Function(RequestOptions options) failure;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw failure(options);
  }

  @override
  void close({bool force = false}) {}
}

DioException _withStatus(RequestOptions options, int status) {
  return DioException(
    requestOptions: options,
    response: Response<void>(requestOptions: options, statusCode: status),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  group('describeFailure names the real problem', () {
    DioException timeout(DioExceptionType type) => DioException(
      requestOptions: RequestOptions(path: '/api/models/a/b'),
      type: type,
    );

    test('a rate limit is not reported as a dead connection', () {
      final message = HuggingFaceRepositoryService.describeFailure(
        _withStatus(RequestOptions(path: '/x'), 429),
      );
      expect(message, contains('429'));
      expect(message, contains('rate-limiting'));
    });

    test('a server error says the host is having trouble', () {
      final message = HuggingFaceRepositoryService.describeFailure(
        _withStatus(RequestOptions(path: '/x'), 503),
      );
      expect(message, contains('503'));
      expect(message, contains('try again'));
    });

    test('another status keeps its number', () {
      final message = HuggingFaceRepositoryService.describeFailure(
        _withStatus(RequestOptions(path: '/x'), 400),
      );
      expect(message, contains('HTTP 400'));
    });

    test('timeouts say which way they timed out', () {
      expect(
        HuggingFaceRepositoryService.describeFailure(
          timeout(DioExceptionType.connectionTimeout),
        ),
        contains('timed out'),
      );
      expect(
        HuggingFaceRepositoryService.describeFailure(
          timeout(DioExceptionType.receiveTimeout),
        ),
        contains('stopped sending data'),
      );
    });

    test('a transport error keeps its cause', () {
      final message = HuggingFaceRepositoryService.describeFailure(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionError,
          error: 'SocketException: Connection reset by peer',
        ),
      );
      expect(message, contains('Connection reset by peer'));
    });

    test('a certificate failure is named as one', () {
      expect(
        HuggingFaceRepositoryService.describeFailure(
          timeout(DioExceptionType.badCertificate),
        ),
        contains('certificate'),
      );
    });
  });

  test('fetchRepository reports the status and the repository', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://huggingface.co'))
      ..httpClientAdapter = _FailingAdapter(
        (options) => _withStatus(options, 429),
      );
    final service = HuggingFaceRepositoryService(dio: dio);

    await expectLater(
      service.fetchRepository('bartowski/SmolLM2-135M-Instruct-GGUF'),
      throwsA(
        isA<HuggingFaceRepositoryException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('bartowski/SmolLM2-135M-Instruct-GGUF'),
            contains('429'),
          ),
        ),
      ),
    );
  });
}
