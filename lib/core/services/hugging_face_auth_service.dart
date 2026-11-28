import 'package:dio/dio.dart';
import 'package:installm/storage/secure_storage.dart';

/// What Hugging Face says about the account a token belongs to.
class HuggingFaceIdentity {
  const HuggingFaceIdentity({required this.name, this.isPro = false});

  /// The account name, or the name of the token when it has no account name.
  final String name;

  /// Whether the account has a paid plan. Not shown as a promise, only as the
  /// answer Hugging Face gave.
  final bool isPro;
}

/// A problem with the saved token, worded for the person who pasted it.
class HuggingFaceTokenException implements Exception {
  const HuggingFaceTokenException(this.message, {this.rejected = false});

  final String message;

  /// True when Hugging Face answered 401, so the token itself is the problem
  /// rather than the network.
  final bool rejected;

  @override
  String toString() => message;
}

/// Where the token is kept.
///
/// The app uses [SecureHuggingFaceTokenStore]; the tests use an in-memory one.
abstract class HuggingFaceTokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

/// Keeps the token in the platform's encrypted storage.
class SecureHuggingFaceTokenStore implements HuggingFaceTokenStore {
  /// Versioned like the other stored values: a new key when the format changes.
  static const storageKey = 'hf_access_token_v1';

  @override
  Future<String?> read() => SecureStorage.instance.readPrimitive(storageKey);

  @override
  Future<void> write(String token) =>
      SecureStorage.instance.writePrimitive(key: storageKey, value: token);

  @override
  Future<void> delete() => SecureStorage.instance.delete(storageKey);
}

/// Holds the optional Hugging Face access token.
///
/// A token raises Hugging Face's anonymous rate limit and lets a download take
/// the account's bandwidth, which is the difference between a catalog that
/// loads and one that is throttled. Nothing is sent when no token is saved: the
/// app works exactly as it did before.
class HuggingFaceAuthService {
  HuggingFaceAuthService({HuggingFaceTokenStore? store, Dio? dio})
    : _store = store ?? SecureHuggingFaceTokenStore(),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://huggingface.co',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              headers: const {'Accept': 'application/json'},
            ),
          );

  /// The token the app's own services read from.
  static final HuggingFaceAuthService instance = HuggingFaceAuthService();

  /// Hosts that may receive the token. A redirect or a third-party URL never
  /// sees it.
  static bool isHuggingFaceHost(String host) =>
      host == 'huggingface.co' ||
      host.endsWith('.huggingface.co') ||
      host == 'hf.co' ||
      host.endsWith('.hf.co');

  final HuggingFaceTokenStore _store;
  final Dio _dio;

  String? _cached;
  bool _loaded = false;

  /// The saved token, or null when none is saved.
  ///
  /// Reading storage once per launch keeps every request from touching the
  /// keystore; a storage failure is treated as no token, so a platform without
  /// encrypted storage still downloads.
  Future<String?> token() async {
    if (_loaded) return _cached;
    try {
      final stored = await _store.read();
      _cached = (stored == null || stored.trim().isEmpty)
          ? null
          : stored.trim();
    } catch (_) {
      _cached = null;
    }
    _loaded = true;
    return _cached;
  }

  Future<bool> hasToken() async => await token() != null;

  /// Stores [raw] after trimming it.
  ///
  /// The token is one line; a pasted newline or a stray space is the usual
  /// reason a token is rejected, so both are refused here with a sentence that
  /// says what to do.
  Future<void> saveToken(String raw) async {
    final token = raw.trim();
    if (token.isEmpty) {
      throw const HuggingFaceTokenException('Paste a token first.');
    }
    if (RegExp(r'\s').hasMatch(token)) {
      throw const HuggingFaceTokenException(
        'A token is one line with no spaces. Copy it again from '
        'huggingface.co/settings/tokens.',
      );
    }
    await _store.write(token);
    _cached = token;
    _loaded = true;
  }

  /// Forgets the token. Downloads fall back to anonymous requests.
  Future<void> clear() async {
    try {
      await _store.delete();
    } finally {
      _cached = null;
      _loaded = true;
    }
  }

  /// Asks Hugging Face who the saved token belongs to.
  ///
  /// Throws [HuggingFaceTokenException] when nothing is saved, when Hugging
  /// Face rejects the token, or when it cannot be reached.
  Future<HuggingFaceIdentity> verify() async {
    final saved = await token();
    if (saved == null) {
      throw const HuggingFaceTokenException('No token is saved.');
    }
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/whoami-v2',
        options: Options(headers: {'Authorization': 'Bearer $saved'}),
      );
      final data = response.data ?? const <String, dynamic>{};
      final name =
          (data['name'] as String?)?.trim() ??
          (data['preferred_username'] as String?)?.trim() ??
          'this account';
      final plan = (data['plan'] as String?)?.toLowerCase();
      return HuggingFaceIdentity(name: name, isPro: plan == 'pro');
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        throw const HuggingFaceTokenException(
          'Hugging Face rejected this token. Check that it is a read token '
          'and that it has not been revoked.',
          rejected: true,
        );
      }
      throw const HuggingFaceTokenException(
        'Could not reach Hugging Face to check the token.',
      );
    }
  }

  /// The interceptor that signs a request when a token is saved.
  Interceptor get requestInterceptor => _HuggingFaceAuthInterceptor(this);
}

class _HuggingFaceAuthInterceptor extends Interceptor {
  _HuggingFaceAuthInterceptor(this._auth);

  final HuggingFaceAuthService _auth;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Only the app's own Hugging Face hosts get the token: an image URL or a
    // redirect elsewhere must not carry it.
    if (HuggingFaceAuthService.isHuggingFaceHost(options.uri.host)) {
      final token = await _auth.token();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }
}
