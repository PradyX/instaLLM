import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/settings/presentation/hugging_face_token_section.dart';
import 'package:installm/core/services/hugging_face_auth_service.dart';

/// Keeps the token in memory instead of the platform's encrypted storage.
class _MemoryTokenStore implements HuggingFaceTokenStore {
  String? value;
  int writes = 0;
  int deletes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async {
    value = token;
    writes++;
  }

  @override
  Future<void> delete() async {
    value = null;
    deletes++;
  }
}

/// Answers the account lookup and records what each request carried.
class _FakeAccountApi implements HttpClientAdapter {
  _FakeAccountApi({this.statusCode = 200, this.name = 'prady'});

  final int statusCode;
  final String name;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (statusCode != 200) {
      return ResponseBody.fromString('{}', statusCode);
    }
    return ResponseBody.fromString(
      jsonEncode({'name': name, 'plan': 'pro'}),
      200,
      headers: const {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

HuggingFaceAuthService _service({
  required _MemoryTokenStore store,
  _FakeAccountApi? api,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://huggingface.co'))
    ..httpClientAdapter = api ?? _FakeAccountApi();
  return HuggingFaceAuthService(store: store, dio: dio);
}

void main() {
  test('no saved token leaves requests anonymous', () async {
    final store = _MemoryTokenStore();
    final service = _service(store: store);

    expect(await service.token(), isNull);
    expect(await service.hasToken(), isFalse);
  });

  test('a saved token is trimmed and read back', () async {
    final store = _MemoryTokenStore();
    final service = _service(store: store);

    await service.saveToken('  hf_abc123\n');

    expect(store.value, 'hf_abc123');
    expect(await service.token(), 'hf_abc123');
    expect(await service.hasToken(), isTrue);
  });

  test('an empty or multi-line token is refused before storage', () async {
    final store = _MemoryTokenStore();
    final service = _service(store: store);

    await expectLater(
      service.saveToken('   '),
      throwsA(isA<HuggingFaceTokenException>()),
    );
    await expectLater(
      service.saveToken('hf_one hf_two'),
      throwsA(
        isA<HuggingFaceTokenException>().having(
          (error) => error.message,
          'message',
          contains('no spaces'),
        ),
      ),
    );
    expect(store.writes, 0);
  });

  test('clearing forgets the token', () async {
    final store = _MemoryTokenStore()..value = 'hf_abc123';
    final service = _service(store: store);

    await service.clear();

    expect(store.deletes, 1);
    expect(await service.token(), isNull);
  });

  test('checking the token reports the account it belongs to', () async {
    final store = _MemoryTokenStore()..value = 'hf_abc123';
    final api = _FakeAccountApi(name: 'prady');
    final service = _service(store: store, api: api);

    final identity = await service.verify();

    expect(identity.name, 'prady');
    expect(identity.isPro, isTrue);
    expect(api.requests.single.headers['Authorization'], 'Bearer hf_abc123');
  });

  test('a refused token is reported as rejected', () async {
    final store = _MemoryTokenStore()..value = 'hf_revoked';
    final service = _service(
      store: store,
      api: _FakeAccountApi(statusCode: 401),
    );

    await expectLater(
      service.verify(),
      throwsA(
        isA<HuggingFaceTokenException>().having(
          (error) => error.rejected,
          'rejected',
          isTrue,
        ),
      ),
    );
  });

  test('an unreachable Hugging Face is not reported as a bad token', () async {
    final store = _MemoryTokenStore()..value = 'hf_abc123';
    final service = _service(
      store: store,
      api: _FakeAccountApi(statusCode: 503),
    );

    await expectLater(
      service.verify(),
      throwsA(
        isA<HuggingFaceTokenException>().having(
          (error) => error.rejected,
          'rejected',
          isFalse,
        ),
      ),
    );
  });

  test('the interceptor signs Hugging Face requests only', () async {
    final store = _MemoryTokenStore()..value = 'hf_abc123';
    final auth = _service(store: store);
    final api = _FakeAccountApi();
    final dio = Dio(BaseOptions(baseUrl: 'https://huggingface.co'))
      ..httpClientAdapter = api
      ..interceptors.add(auth.requestInterceptor);

    await dio.get<dynamic>('/api/models');
    await dio.get<dynamic>(
      'https://example.com/model.gguf',
      options: Options(responseType: ResponseType.plain),
    );

    expect(api.requests[0].headers['Authorization'], 'Bearer hf_abc123');
    expect(api.requests[1].headers.containsKey('Authorization'), isFalse);
  });

  testWidgets('the settings row explains the anonymous limit', (tester) async {
    final service = _service(store: _MemoryTokenStore());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HuggingFaceTokenSection(auth: service)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hugging Face token'), findsOneWidget);
    expect(find.textContaining('anonymous rate limit'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Add'), findsOneWidget);
  });

  test('a cleared token stops signing requests', () async {
    final store = _MemoryTokenStore()..value = 'hf_abc123';
    final auth = _service(store: store);
    final api = _FakeAccountApi();
    final dio = Dio(BaseOptions(baseUrl: 'https://huggingface.co'))
      ..httpClientAdapter = api
      ..interceptors.add(auth.requestInterceptor);

    await auth.clear();
    await dio.get<dynamic>('/api/models');

    expect(api.requests.single.headers.containsKey('Authorization'), isFalse);
  });
}
