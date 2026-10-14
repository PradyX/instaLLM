import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:installm/features/profile_images/data/profile_image_store.dart';
import 'package:installm/features/profile_images/domain/petdex_pet.dart';

/// Requests public assets only, using a dedicated client with no auth/logging.
/// The catalog stays in memory. Only requested search/selected images reach disk.
class PetdexService {
  PetdexService({required Directory directory, required Dio dio})
    : _directory = directory,
      _dio = dio,
      store = ProfileImageStore(
        File(p.join(directory.path, 'selections.json')),
      );

  static const maxSearchImages = 100;
  static const _maxAssetBytes = 8 * 1024 * 1024;
  final Directory _directory;
  final Dio _dio;
  final ProfileImageStore store;
  final _pending = <String, Future<File>>{};
  Future<List<PetdexPet>>? _catalog;
  // Limit native decodes and HTTP requests even when a grid is scrolled quickly.
  Future<void> _imageQueue = Future<void>.value();

  void close() => _dio.close(force: true);

  Future<List<PetdexPet>> catalog({CancelToken? cancelToken}) async {
    final existing = _catalog;
    if (existing != null) return existing;
    final request = _loadCatalog(cancelToken);
    _catalog = request;
    try {
      return await request;
    } catch (_) {
      _catalog = null;
      rethrow;
    }
  }

  Future<List<PetdexPet>> _loadCatalog(CancelToken? token) async {
    final bytes = await _download(
      'https://petdex.dev/api/manifest',
      cancelToken: token,
    );
    final raw = jsonDecode(utf8.decode(bytes));
    if (raw is! Map || raw['pets'] is! List) {
      throw const FormatException('Invalid Petdex catalog');
    }
    final pets = (raw['pets'] as List)
        .map(PetdexPet.fromJson)
        .whereType<PetdexPet>()
        .toList();
    pets.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List.unmodifiable(pets);
  }

  /// An empty search never fetches a gallery of images.
  static List<PetdexPet> search(List<PetdexPet> pets, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    return pets
        .where(
          (pet) => '${pet.name} ${pet.slug}'.toLowerCase().contains(needle),
        )
        .take(60)
        .toList(growable: false);
  }

  /// A small starting selection for the explicitly opened bot creation sheet.
  /// Metadata is cheap; only visible portraits are fetched by the widgets.
  static List<PetdexPet> featured(List<PetdexPet> pets) {
    final curated = pets.where(
      (pet) =>
          pet.spritesheetUrl.startsWith('https://assets.petdex.dev/curated/'),
    );
    final seenSlugs = <String>{};
    final seenImages = <String>{};
    return curated
        .followedBy(pets)
        .where(
          (pet) =>
              seenSlugs.add(pet.slug) && seenImages.add(pet.spritesheetUrl),
        )
        .take(6)
        .toList(growable: false);
  }

  File cachedFile(PetdexPet pet) =>
      File(p.join(_directory.path, 'images', '${pet.slug}.png'));

  Future<File> image(PetdexPet pet, {CancelToken? cancelToken}) async {
    if (PetdexPet.fromJson(pet.toJson()) == null) {
      throw const FormatException('Invalid Petdex pet');
    }
    final file = cachedFile(pet);
    if (await file.exists()) {
      // Invalid/partial cache files are re-fetched, never displayed as blank.
      final bytes = await file.readAsBytes();
      if (_isCachedAvatar(bytes)) {
        await file.setLastModified(DateTime.now());
        return file;
      }
    }
    final existing = _pending[pet.slug];
    if (existing != null) return existing;
    final request = _imageQueue.then((_) => _loadImage(pet, cancelToken));
    _imageQueue = request.then<void>((_) {}, onError: (Object _) {});
    _pending[pet.slug] = request;
    try {
      return await request;
    } finally {
      _pending.remove(pet.slug);
    }
  }

  bool _isCachedAvatar(Uint8List bytes) {
    try {
      final decoder = img.PngDecoder();
      final info = decoder.startDecode(bytes);
      return info?.width == 96 &&
          info?.height == 104 &&
          decoder.decodeFrame(0) != null;
    } catch (_) {
      return false;
    }
  }

  Future<File> _loadImage(PetdexPet pet, CancelToken? token) async {
    if (token?.isCancelled == true) throw token!.cancelError!;
    Uint8List avatar;
    try {
      final bytes = await _download(pet.previewUrl, cancelToken: token);
      avatar = await compute(cropPetdexAvatar, (bytes, true));
    } on DioException catch (error) {
      // Previews can be absent; transient network failures should stay actionable.
      if (error.response?.statusCode != 404) rethrow;
      final bytes = await _download(pet.spritesheetUrl, cancelToken: token);
      avatar = await compute(cropPetdexAvatar, (bytes, false));
    }
    if (token?.isCancelled == true) throw token!.cancelError!;
    final file = cachedFile(pet);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.part');
    try {
      await temporary.writeAsBytes(avatar, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    await pruneCache(keepSlug: pet.slug);
    return file;
  }

  Future<Uint8List> _download(String url, {CancelToken? cancelToken}) async {
    if (url != 'https://petdex.dev/api/manifest' &&
        !PetdexPet.isAssetUrl(url)) {
      throw const FormatException('Unsupported Petdex asset host');
    }
    // Follow Petdex's documented manifest redirect, and bound streamed bytes.
    final response = await _dio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(responseType: ResponseType.stream),
    );
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.data!.stream) {
      if (builder.length + chunk.length > _maxAssetBytes) {
        throw const FormatException('Petdex response exceeds 8 MiB');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// Selected images are protected; only older search thumbnails are evicted.
  Future<void> pruneCache({String? keepSlug}) async {
    final images = Directory(p.join(_directory.path, 'images'));
    if (!await images.exists()) return;
    final protected = {
      for (final pet in store.load().values) '${pet.slug}.png',
    };
    if (store.isReadOnly) return;
    if (keepSlug != null) protected.add('$keepSlug.png');
    final candidates = <(File, DateTime)>[];
    await for (final entry in images.list()) {
      if (entry is File &&
          p.extension(entry.path) == '.png' &&
          !protected.contains(p.basename(entry.path))) {
        candidates.add((entry, (await entry.stat()).modified));
      }
    }
    candidates.sort((a, b) => a.$2.compareTo(b.$2));
    for (final candidate in candidates.take(
      (candidates.length - maxSearchImages).clamp(0, candidates.length),
    )) {
      await candidate.$1.delete();
    }
  }
}

/// Petdex previews are a six-frame idle strip, not a standalone portrait.
/// Render one frame at avatar size instead of displaying the entire atlas.
Uint8List cropPetdexAvatar((Uint8List, bool) input) {
  final decoder = img.findDecoderForData(input.$1);
  final info = decoder?.startDecode(input.$1);
  if (info == null || info.width > 1536 || info.height > 2288) {
    throw const FormatException('Invalid Petdex image dimensions');
  }
  final expectedWidth = input.$2 ? 1152 : 1536;
  final validHeight = input.$2
      ? info.height == 208
      : info.height == 1872 || info.height == 2288;
  if (info.width != expectedWidth || !validHeight) {
    throw const FormatException('Unsupported Petdex sprite format');
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) throw const FormatException('Invalid Petdex image');
  final frame = img.copyCrop(decoded, x: 0, y: 0, width: 192, height: 208);
  return img.encodePng(
    img.copyResize(
      frame,
      width: 96,
      height: 104,
      interpolation: img.Interpolation.average,
    ),
  );
}
