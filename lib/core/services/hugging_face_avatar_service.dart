import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:installm/core/services/hugging_face_repository_service.dart';

/// Hugging Face publisher avatars, shown beside a model row in the list.
///
/// Hugging Face attaches no image to a model, but every repository has a
/// publisher, and publishers — community accounts and organizations alike —
/// have their own avatar: the same picture huggingface.co shows next to their
/// repositories. A family row whose download link is a Hugging Face repository
/// asks for that publisher's avatar and shows it in place of the letter
/// monogram; anything without a Hugging Face link, and any publisher without
/// an avatar, keeps the monogram.
///
/// Network behaviour is narrow on purpose: HTTP GETs of public avatar metadata
/// only (a publisher name travels because it is part of the public URL), no
/// user or device information is sent, and every answer — found or absent —
/// is cached on disk so the page does not repeat its publisher lookups on
/// every launch. Offline, the disk cache still answers and nothing reaches
/// the network.
class HuggingFaceAvatarService {
  HuggingFaceAvatarService({Dio? dio, Directory? cacheDirectory})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://huggingface.co',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: const {'Accept': 'application/json'},
            ),
          ),
      _cacheDirectory = cacheDirectory;

  final Dio _dio;
  final Directory? _cacheDirectory;

  /// How long a cached avatar is trusted before the network is asked again;
  /// avatars change rarely, and a stale one costs nothing to keep showing.
  static const Duration _avatarCacheLifetime = Duration(days: 30);

  /// How long "this publisher has no avatar" is remembered, so a page of
  /// unknown publishers does not re-ask on every launch — but a publisher
  /// that gains one later is picked up the next day.
  static const Duration _missingCacheLifetime = Duration(days: 1);

  static const String _avatarsDir = 'hf_avatars';
  static const String _avatarSuffix = '.avatar';
  static const String _missingSuffix = '.missing';

  final Map<String, Uint8List?> _memory = {};

  /// Requests already running, so several rows with one publisher share one
  /// lookup instead of each reaching the network.
  final Map<String, Future<Uint8List?>> _inFlight = {};

  /// The publisher (first path segment) of a Hugging Face
  /// `author/repository` id or URL; null for anything that is not one.
  static String? publisherFromUrl(String? url) {
    if (url == null) return null;
    final repoId = HuggingFaceRepositoryService.parseRepositoryInput(url);
    if (repoId == null) return null;
    final publisher = repoId.split('/').first;
    return publisher.trim().isEmpty ? null : publisher;
  }

  /// The model's own creator — Qwen for Qwen2.5, LiquidAI for LFM2.5 — not
  /// the community account that quantized it.
  ///
  /// A model row's download link names whichever repository the catalog
  /// pulls from (`bartowski/Qwen2.5-7B-Instruct-GGUF`, `lmstudio-community/...`),
  /// so its publisher avatar is a person or repackager, not the company
  /// behind the model. Hugging Face keeps no per-model logo; the closest
  /// thing is the creator's own organization avatar, which is the same
  /// picture huggingface.co shows on their profile. Model families with a
  /// known organization answer it; anything else answers null and keeps the
  /// repository publisher's avatar.
  static String? creatorOrgFor(String displayName) {
    final name = displayName.toLowerCase();
    if (name.startsWith('qwen')) return 'Qwen';
    if (name.startsWith('lfm') || name.contains('liquidai')) {
      return 'LiquidAI';
    }
    if (name.startsWith('smollm')) return 'HuggingFaceTB';
    if (name.startsWith('tinyllama')) return 'TinyLlama';
    if (name.startsWith('llama')) return 'meta-llama';
    if (name.startsWith('gemma')) return 'google';
    if (name.startsWith('phi')) return 'microsoft';
    if (name.startsWith('mistral') ||
        name.startsWith('mixtral') ||
        name.startsWith('ministral')) {
      return 'mistralai';
    }
    return null;
  }

  /// The publisher's avatar image, or null when it has none or cannot be
  /// reached right now.
  ///
  /// Answers in this order: this session's memory, a fresh disk cache, a
  /// recent "no avatar" note, and only then the network — the
  /// `/api/users/<publisher>/avatar` endpoint first, then
  /// `/api/organizations/...`, because huggingface.co keeps the two profile
  /// kinds apart and each 404s for the other.
  Future<Uint8List?> avatarForPublisher(String publisher) {
    final trimmed = publisher.trim();
    final memory = _memory[trimmed];
    if (memory != null) {
      return Future.value(memory);
    }
    final running = _inFlight[trimmed];
    if (running != null) return running;

    final request = _resolve(trimmed);
    _inFlight[trimmed] = request;
    unawaited(request.whenComplete(() => _inFlight.remove(trimmed)));
    return request;
  }

  Future<Uint8List?> _resolve(String publisher) async {
    final diskBytes = await _readBytes(
      publisher,
      _avatarSuffix,
      freshFor: _avatarCacheLifetime,
    );
    if (diskBytes != null) {
      _memory[publisher] = diskBytes;
      return diskBytes;
    }

    if (await _missingFileExists(publisher)) {
      _memory[publisher] = null;
      return null;
    }

    final avatarUrl = await _avatarUrlFor(publisher);
    if (avatarUrl == null) return null;

    final bytes = await _download(avatarUrl);
    if (bytes == null) return null;

    await _writeBytes(publisher, _avatarSuffix, bytes);
    _memory[publisher] = bytes;
    return bytes;
  }

  /// The CDN URL of a publisher's avatar, or null when the publisher has
  /// none.
  ///
  /// Transient trouble (offline, timeouts, 5xx) answers null without caching
  /// anything, so a later launch tries again; a definite "no such avatar"
  /// writes the short-lived missing marker.
  Future<String?> _avatarUrlFor(String publisher) async {
    var sawDefiniteNoAvatar = false;
    for (final kind in const ['users', 'organizations']) {
      try {
        final response = await _dio.get<Object?>(
          '/api/$kind/$publisher/avatar',
          options: Options(responseType: ResponseType.plain),
        );
        final url = _extractAvatarUrl(response.data);
        if (url != null) return url;
        // An answer that names no avatar is a definite no.
        sawDefiniteNoAvatar = true;
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        if (status == 401 || status == 403 || status == 404) {
          sawDefiniteNoAvatar = true;
          continue;
        }
        return null;
      } catch (_) {
        return null;
      }
    }
    if (sawDefiniteNoAvatar) {
      await _writeBytes(publisher, _missingSuffix, const []);
    }
    return null;
  }

  /// Reads `"avatarUrl": "..."` from the JSON both endpoints return.
  ///
  /// Dio hands the body back either as already-decoded JSON or as the raw
  /// text, depending on version and content-type; both shapes are read.
  String? _extractAvatarUrl(Object? data) {
    Object? json;
    if (data is Map) {
      json = data;
    } else if (data is String) {
      try {
        json = jsonDecode(data);
      } catch (_) {
        // Not JSON; treated the same as a missing field.
      }
    }
    if (json is Map) {
      final value = json['avatarUrl'];
      if (value is String && value.startsWith('http')) return value;
    }
    return null;
  }

  /// Downloads the avatar bytes from the CDN.
  ///
  /// Anything suspiciously small, or that starts like a JSON error document
  /// rather than an image, is treated as "no avatar" instead of rendered as a
  /// broken picture.
  Future<Uint8List?> _download(String url) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: const {'Accept': 'image/*'},
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.length < 32) return null;
      if (!_plausiblyImage(bytes.sublist(0, bytes.length > 4 ? 4 : 4))) {
        return null;
      }
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  /// JPEG starts with `FF D8`, PNG with the `89 50` signature; other formats
  /// also lead with bytes that never appear in an ASCII error document (GIF
  /// `47`, WebP `52`, BMP `42`, TIFF `49`). Only these first bytes are
  /// checked, so `{"error": ...}` is never mistaken for an image.
  bool _plausiblyImage(List<int> head) {
    if (head.isEmpty) return false;
    switch (head.first) {
      case 0xFF: // JPEG
      case 0x89: // PNG
      case 0x47: // GIF ('G')
      case 0x52: // WebP/RIFF ('R')
      case 0x49: // TIFF ('I')
      case 0x42: // BMP ('B')
        return true;
      default:
        return false;
    }
  }

  // --- Disk cache -----------------------------------------------------------

  /// The browser cache is keyed by the publisher's name, hashed so the
  /// filesystem never sees raw user-influenced strings as file names, and
  /// recorded per answer kind: a `.avatar` file holds the image bytes, and a
  /// `.missing` marker records a publisher without an avatar.
  Future<File?> _cacheFile(String publisher, String suffix) async {
    try {
      final directory =
          _cacheDirectory ?? await getApplicationSupportDirectory();
      final avatars = Directory(
        '${directory.path}${Platform.pathSeparator}$_avatarsDir',
      );
      return File(
        '${avatars.path}${Platform.pathSeparator}'
        '${sha1.convert(utf8.encode(publisher.toLowerCase()))}$suffix',
      );
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _readBytes(
    String publisher,
    String suffix, {
    required Duration freshFor,
  }) async {
    try {
      final file = await _cacheFile(publisher, suffix);
      if (file == null || !await file.exists()) return null;
      if (DateTime.now().difference(await file.lastModified()) > freshFor) {
        return null;
      }
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeBytes(
    String publisher,
    String suffix,
    List<int> bytes,
  ) async {
    try {
      final file = await _cacheFile(publisher, suffix);
      if (file == null) return;
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      // The cache is an optimization; failing to write it changes nothing
      // except the next lookup having to reach the network again.
    }
  }

  Future<bool> _missingFileExists(String publisher) async {
    try {
      final file = await _cacheFile(publisher, _missingSuffix);
      if (file == null || !await file.exists()) return false;
      if (DateTime.now().difference(await file.lastModified()) >
          _missingCacheLifetime) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
