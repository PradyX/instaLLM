import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pocket_llm/features/profile_images/application/profile_images_controller.dart';
import 'package:pocket_llm/features/profile_images/data/petdex_service.dart';
import 'package:pocket_llm/features/profile_images/data/profile_image_store.dart';
import 'package:pocket_llm/features/profile_images/domain/petdex_pet.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final ResponseBody Function(RequestOptions) respond;
  final urls = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    urls.add(options.uri.toString());
    expect(
      options.headers.keys.map((key) => key.toLowerCase()),
      isNot(contains('authorization')),
    );
    expect(options.data, isNull);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

const _boba = PetdexPet(
  slug: 'boba',
  name: 'Boba',
  creator: 'railly',
  spritesheetUrl: 'https://assets.petdex.dev/curated/boba/sprite.webp',
);

Uint8List _sprite({bool preview = true}) {
  final image = img.Image(
    width: preview ? 1152 : 1536,
    height: preview ? 208 : 1872,
    numChannels: 4,
  );
  img.fill(image, color: img.ColorRgba8(0, 0, 255, 255));
  img.fillRect(
    image,
    x1: 0,
    y1: 0,
    x2: 191,
    y2: 207,
    color: img.ColorRgba8(255, 0, 0, 255),
  );
  return img.encodePng(image);
}

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('petdex_test'),
  );
  tearDown(() async => directory.delete(recursive: true));

  PetdexService service(_Adapter adapter) {
    final dio = Dio()..httpClientAdapter = adapter;
    final result = PetdexService(directory: directory, dio: dio);
    addTearDown(result.close);
    return result;
  }

  test(
    'loads catalog metadata once without caching or downloading gallery images',
    () async {
      final adapter = _Adapter(
        (_) => ResponseBody.fromString(
          jsonEncode({
            'pets': [
              _boba.toJson(),
              {'slug': '../invalid'},
              {
                'slug': 'bad',
                'displayName': 'Bad',
                'spritesheetUrl': 'https://example.com/image',
              },
            ],
          }),
          200,
        ),
      );
      final api = service(adapter);
      final catalog = await api.catalog();
      expect(catalog, [_boba]);
      expect(await api.catalog(), same(catalog));
      expect(adapter.urls, ['https://petdex.dev/api/manifest']);
      expect(directory.listSync(), isEmpty);
      expect(PetdexService.search(catalog, ' '), isEmpty);
      expect(PetdexService.search(catalog, 'BOB'), [_boba]);
      expect(PetdexService.search(catalog, 'missing'), isEmpty);
    },
  );

  test('failed catalog requests can be retried', () async {
    var count = 0;
    final api = service(
      _Adapter(
        (_) => ++count == 1
            ? ResponseBody.fromString('unavailable', 503)
            : ResponseBody.fromString(
                jsonEncode({
                  'pets': [_boba.toJson()],
                }),
                200,
              ),
      ),
    );
    await expectLater(api.catalog(), throwsA(isA<DioException>()));
    expect(await api.catalog(), [_boba]);
  });

  test(
    'only the requested image is cached; deduplicates requests and reuses cache after restart',
    () async {
      final bytes = _sprite();
      final adapter = _Adapter((_) => ResponseBody.fromBytes(bytes, 200));
      final api = service(adapter);
      final files = await Future.wait([api.image(_boba), api.image(_boba)]);
      expect(files.map((file) => file.path).toSet(), hasLength(1));
      expect(adapter.urls, [_boba.previewUrl]);
      final avatar = img.decodePng(await files.first.readAsBytes())!;
      expect((avatar.width, avatar.height), (96, 104));
      expect(avatar.getPixel(48, 52).r, 255);
      expect(avatar.getPixel(48, 52).b, 0);
      final cached = await service(adapter).image(_boba);
      expect(cached.path, files.first.path);
      expect(adapter.urls, hasLength(1));
      expect(
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => p.basename(file.path)),
        ['boba.png'],
      );
    },
  );

  test('missing preview falls back to the published sprite atlas', () async {
    final sprite = _sprite(preview: false);
    final adapter = _Adapter(
      (options) => options.uri.toString() == _boba.previewUrl
          ? ResponseBody.fromString('not found', 404)
          : ResponseBody.fromBytes(sprite, 200),
    );
    final file = await service(adapter).image(_boba);
    expect(await file.exists(), isTrue);
    expect(adapter.urls, [_boba.previewUrl, _boba.spritesheetUrl]);
  });

  test('repairs partial cache files and refuses invalid asset data', () async {
    final bytes = _sprite();
    final api = service(_Adapter((_) => ResponseBody.fromBytes(bytes, 200)));
    final file = api.cachedFile(_boba);
    await file.parent.create(recursive: true);
    await file.writeAsBytes([137, 80, 78, 71, 13, 10, 26, 10]);
    expect(
      img.decodePng(await (await api.image(_boba)).readAsBytes()),
      isNotNull,
    );
    await file.delete();
    final invalid = service(
      _Adapter((_) => ResponseBody.fromString('invalid image', 200)),
    );
    await expectLater(invalid.image(_boba), throwsFormatException);
    expect(await file.exists(), isFalse);
    expect(
      file.parent.listSync().where((file) => file.path.endsWith('.part')),
      isEmpty,
    );
  });

  test('cancelled images do not download or leave partial files', () async {
    final adapter = _Adapter((_) => ResponseBody.fromBytes(_sprite(), 200));
    final api = service(adapter);
    final token = CancelToken()..cancel();
    await expectLater(
      api.image(_boba, cancelToken: token),
      throwsA(isA<DioException>()),
    );
    expect(adapter.urls, isEmpty);
    expect(await api.cachedFile(_boba).exists(), isFalse);
  });

  test('interrupted and oversized responses leave no cache file', () async {
    final interrupted = service(
      _Adapter(
        (_) => ResponseBody(
          Stream<Uint8List>.error(const SocketException('interrupted')),
          200,
        ),
      ),
    );
    await expectLater(interrupted.image(_boba), throwsA(anything));
    final oversized = service(
      _Adapter(
        (_) => ResponseBody(
          Stream.fromIterable(List.generate(9, (_) => Uint8List(1024 * 1024))),
          200,
        ),
      ),
    );
    await expectLater(oversized.image(_boba), throwsFormatException);
    expect(directory.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test(
    'evicts old searched images while preserving all selected images',
    () async {
      final api = service(
        _Adapter((_) => throw StateError('network not expected')),
      );
      expect(api.store.save({botProfileKey('builtin'): _boba}), isTrue);
      final images = api.cachedFile(_boba).parent..createSync();
      api.cachedFile(_boba).writeAsStringSync('selected');
      api.cachedFile(_boba).setLastModifiedSync(DateTime(2000));
      for (var index = 0; index < 105; index++) {
        final file = File(p.join(images.path, 'searched-$index.png'))
          ..writeAsStringSync('cached');
        file.setLastModifiedSync(DateTime(2001).add(Duration(minutes: index)));
      }
      await api.pruneCache();
      expect(images.listSync().whereType<File>(), hasLength(101));
      expect(api.cachedFile(_boba).readAsStringSync(), 'selected');
      expect(File(p.join(images.path, 'searched-0.png')).existsSync(), isFalse);
      expect(
        File(p.join(images.path, 'searched-104.png')).existsSync(),
        isTrue,
      );
    },
  );

  test(
    'versioned selections recover partial data and keep bots and rooms independent',
    () {
      final file = File(p.join(directory.path, 'selections.json'));
      final store = ProfileImageStore(file);
      expect(store.load(), isEmpty);
      file.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'selections': {
            botProfileKey('coder'): _boba.toJson(),
            roomProfileKey('dev'): _boba.toJson(),
            'bot:broken': 5,
            'room:invalid': {'slug': '../escape'},
          },
        }),
      );
      final restored = store.load();
      expect(restored.keys, [botProfileKey('coder'), roomProfileKey('dev')]);
      restored.remove(botProfileKey('coder'));
      expect(store.save(restored), isTrue);
      expect(ProfileImageStore(file).load(), {roomProfileKey('dev'): _boba});
      expect(jsonDecode(file.readAsStringSync())['version'], 1);
    },
  );

  test(
    'backs up corrupt documents and refuses to downgrade newer selections',
    () {
      final file = File(p.join(directory.path, 'selections.json'))
        ..writeAsStringSync('broken');
      final store = ProfileImageStore(file);
      expect(store.load(), isEmpty);
      expect(store.save({botProfileKey('coder'): _boba}), isTrue);
      expect(
        directory.listSync().whereType<File>().where(
          (file) => file.path.contains('.corrupt-'),
        ),
        hasLength(1),
      );
      final future = jsonEncode({
        'version': 2,
        'selections': {roomProfileKey('dev'): _boba.toJson()},
      });
      file.writeAsStringSync(future);
      final newer = ProfileImageStore(file);
      expect(newer.load(), isEmpty);
      expect(newer.isReadOnly, isTrue);
      expect(newer.save({}), isFalse);
      expect(file.readAsStringSync(), future);
    },
  );

  test(
    'concurrent choices preserve separate bot and room selections',
    () async {
      final api = service(
        _Adapter((_) => throw StateError('network not expected')),
      );
      final container = ProviderContainer(
        overrides: [petdexServiceProvider.overrideWith((ref) async => api)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(profileImagesProvider.notifier);
      expect(
        await Future.wait([
          notifier.select(botProfileKey('builtin'), _boba),
          notifier.select(roomProfileKey('dev'), _boba),
        ]),
        [true, true],
      );
      expect(api.store.load().keys, [
        botProfileKey('builtin'),
        roomProfileKey('dev'),
      ]);
    },
  );

  test('rejects paths and unrelated network hosts in metadata', () {
    expect(
      PetdexPet.fromJson({..._boba.toJson(), 'slug': '../escape'}),
      isNull,
    );
    expect(
      PetdexPet.fromJson({
        ..._boba.toJson(),
        'spritesheetUrl': 'https://user:secret@assets.petdex.dev/x',
      }),
      isNull,
    );
    expect(
      PetdexPet.fromJson({
        ..._boba.toJson(),
        'spritesheetUrl': 'https://example.com/x',
      }),
      isNull,
    );
    expect(
      PetdexPet.fromJson({
        ..._boba.toJson(),
        'spritesheetUrl': 'http://assets.petdex.dev/x',
      }),
      isNull,
    );
  });
}
