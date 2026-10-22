import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/services/hugging_face_avatar_service.dart';

/// Serves canned `ResponseBody`s for the routes the avatar service asks for,
/// and counts every request heading out.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.routes);

  final Map<String, ResponseBody> routes;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    final body = routes[options.uri.toString()];
    if (body == null) {
      return ResponseBody.fromString('not found', 404);
    }
    return body;
  }

  @override
  void close({bool force = false}) {}
}

HuggingFaceAvatarService _service(
  _FakeAdapter adapter, {
  required Directory cacheDirectory,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://huggingface.co'));
  dio.httpClientAdapter = adapter;
  return HuggingFaceAvatarService(dio: dio, cacheDirectory: cacheDirectory);
}

ResponseBody _json(String body, [int status = 200]) {
  return ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: <String>['application/json; charset=utf-8'],
    },
  );
}

const _avatarBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR header start
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 0x1F, 0x15, 0xC4,
  0x89, 0, 0, 0, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C,
  0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D,
  0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  // padded well past the 32-byte minimum the service insists on
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
];

void main() {
  late Directory cache;
  setUp(() {
    cache = Directory.systemTemp.createTempSync('hf-avatars-test');
  });
  tearDown(() {
    cache.deleteSync(recursive: true);
  });

  group('publisherFromUrl', () {
    test('reads the publisher from resolve URLs and repo ids', () {
      expect(
        HuggingFaceAvatarService.publisherFromUrl(
          'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF'
          '/resolve/main/llama.gguf',
        ),
        'bartowski',
      );
      expect(
        HuggingFaceAvatarService.publisherFromUrl('lmstudio-community/repo'),
        'lmstudio-community',
      );
    });

    test('null for anything that is not a Hugging Face repository', () {
      expect(HuggingFaceAvatarService.publisherFromUrl(null), isNull);
      expect(
        HuggingFaceAvatarService.publisherFromUrl('https://example.com/a/b'),
        isNull,
      );
      expect(
        HuggingFaceAvatarService.publisherFromUrl('/Users/prady/models/m.gguf'),
        isNull,
      );
    });
  });

  group('creatorOrgFor', () {
    test('model families answer the creator organization, not the '
        'community account that quantized them', () {
      expect(HuggingFaceAvatarService.creatorOrgFor('Qwen 2.5 7B'), 'Qwen');
      expect(HuggingFaceAvatarService.creatorOrgFor('LFM2.5 230M'), 'LiquidAI');
      expect(
        HuggingFaceAvatarService.creatorOrgFor('LiquidAI LFM 1B'),
        'LiquidAI',
      );
      expect(
        HuggingFaceAvatarService.creatorOrgFor('SmolLM2 135M'),
        'HuggingFaceTB',
      );
      expect(
        HuggingFaceAvatarService.creatorOrgFor('TinyLlama 1.1B'),
        'TinyLlama',
      );
      expect(
        HuggingFaceAvatarService.creatorOrgFor('Llama 3.2 1B'),
        'meta-llama',
      );
      expect(HuggingFaceAvatarService.creatorOrgFor('Gemma 3 4B'), 'google');
      expect(HuggingFaceAvatarService.creatorOrgFor('Phi 3 mini'), 'microsoft');
      expect(HuggingFaceAvatarService.creatorOrgFor('Mistral 7B'), 'mistralai');
      expect(
        HuggingFaceAvatarService.creatorOrgFor('Mixtral 8x7B'),
        'mistralai',
      );
    });

    test('model families with no known organization stay unlabeled', () {
      expect(HuggingFaceAvatarService.creatorOrgFor('jinen v2 small'), isNull);
      expect(
        HuggingFaceAvatarService.creatorOrgFor('DeepSeek R1 Distill Qwen'),
        isNull,
      );
      expect(
        HuggingFaceAvatarService.creatorOrgFor('TinyStories GPT 0.1'),
        isNull,
      );
    });
  });

  group('avatarForPublisher', () {
    test('a personal publisher answers through the users endpoint', () async {
      final adapter = _FakeAdapter({
        'https://huggingface.co/api/users/bartowski/avatar': _json(
          '{"avatarUrl":"https://cdn-avatars.huggingface.co/x/b.jpeg"}',
        ),
        'https://cdn-avatars.huggingface.co/x/b.jpeg': ResponseBody.fromBytes(
          _avatarBytes,
          200,
          headers: {
            Headers.contentTypeHeader: <String>['image/jpeg'],
          },
        ),
      });
      final service = _service(adapter, cacheDirectory: cache);

      expect(await service.avatarForPublisher('bartowski'), isNotNull);
      // One look-up, one download: nothing else left the app.
      expect(adapter.requests, 2);
    });

    test(
      'an organization publisher falls through to the org endpoint',
      () async {
        final adapter = _FakeAdapter({
          'https://huggingface.co/api/users/qwen/avatar': _json(
            '{"error":"This user does not exist"}',
            404,
          ),
          'https://huggingface.co/api/organizations/qwen/avatar': _json(
            '{"avatarUrl":"https://cdn-avatars.huggingface.co/x/q.jpeg"}',
          ),
          'https://cdn-avatars.huggingface.co/x/q.jpeg': ResponseBody.fromBytes(
            _avatarBytes,
            200,
          ),
        });
        final service = _service(adapter, cacheDirectory: cache);

        expect(await service.avatarForPublisher('qwen'), isNotNull);
        expect(adapter.requests, 3);
      },
    );

    test(
      'the disk cache answers before the network is touched again',
      () async {
        final adapter = _FakeAdapter({
          'https://huggingface.co/api/users/bartowski/avatar': _json(
            '{"avatarUrl":"https://cdn-avatars.huggingface.co/x/b.jpeg"}',
          ),
          'https://cdn-avatars.huggingface.co/x/b.jpeg': ResponseBody.fromBytes(
            _avatarBytes,
            200,
          ),
        });
        final service = _service(adapter, cacheDirectory: cache);
        expect(await service.avatarForPublisher('bartowski'), isNotNull);
        expect(adapter.requests, 2);

        // A fresh service (as the next launch is) reads the cache, and no
        // request leaves the app at all.
        final offline = _service(_FakeAdapter(const {}), cacheDirectory: cache);
        expect(await offline.avatarForPublisher('bartowski'), isNotNull);
      },
    );

    test(
      'a publisher with no avatar is remembered for the session and a day',
      () async {
        final adapter = _FakeAdapter(const {});
        final service = _service(adapter, cacheDirectory: cache);

        expect(await service.avatarForPublisher('nobody'), isNull);
        // Both profile kinds were asked before giving up.
        expect(adapter.requests, 2);

        expect(await service.avatarForPublisher('nobody'), isNull);
        expect(adapter.requests, 2);
      },
    );

    test(
      'a response that is JSON, not an image, is never handed back',
      () async {
        final adapter = _FakeAdapter({
          'https://huggingface.co/api/users/bad/avatar': _json(
            '{"avatarUrl":"https://cdn-avatars.huggingface.co/x/oops.jpeg"}',
          ),
          'https://cdn-avatars.huggingface.co/x/oops.jpeg': _json(
            '{"error":"gone"}',
          ),
        });
        final service = _service(adapter, cacheDirectory: cache);

        expect(await service.avatarForPublisher('bad'), isNull);
      },
    );
  });
}
