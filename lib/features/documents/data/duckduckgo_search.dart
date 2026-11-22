import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:installm/features/documents/data/web_fetch_service.dart';
import 'package:installm/features/documents/domain/network_policy.dart';

/// Keyless web search for Road Map 5 Phase 5.5.
///
/// The unit was specified without a paid key, and this is the seam that makes
/// that real: no account, no token, no per-query billing. It asks DuckDuckGo's
/// public HTML endpoint first and falls back to Brave's HTML search page when
/// DuckDuckGo refuses a request (it answers 202 with a challenge page from some
/// networks). Both are labelled `duckduckgo` in the workspace policy, so the
/// user flips one switch; `tavily` and `brave` remain keyed alternatives behind
/// the same dispatch.
///
/// Nothing here runs by itself: the workspace network policy is checked before
/// this is called, there is no background fetch, and every result carries the
/// URL it came from plus the time it was read.
class KeylessWebSearch {
  KeylessWebSearch({Dio? dio, DateTime Function()? clock})
    : _dio = dio,
      _clock = clock ?? DateTime.now;

  final Dio? _dio;
  final DateTime Function() _clock;

  static const String duckDuckGoEndpoint = 'https://html.duckduckgo.com/html/';
  static const String braveEndpoint = 'https://search.brave.com/search';

  /// Keyless JSON fallback: Wikipedia's own search API. An encyclopedia is not
  /// the whole web, but it answers factual questions without a rate limit, and
  /// it is what keeps the unit working on a network where the engines above
  /// refuse (Brave answers 429 there within seconds of a second search).
  static const String wikipediaEndpoint = 'https://en.wikipedia.org/w/api.php';

  /// A plain browser user agent: both endpoints answer a bare client with a
  /// challenge page instead of results.
  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';

  /// Searches DuckDuckGo, then Brave, and reports why nothing came back only
  /// when every engine failed to answer.
  Future<DuckDuckGoResult> search(String query, {int limit = 5}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const DuckDuckGoResult();

    final duck = await _get(duckDuckGoEndpoint, {'q': trimmed});
    if (duck == null) {
      return const DuckDuckGoResult(
        error: 'the search service could not be reached',
      );
    }
    if (duck.status == 200) {
      final results = parseDuckDuckGo(
        duck.body,
        fetchedAt: _clock(),
        limit: limit,
      );
      if (results.isNotEmpty) return DuckDuckGoResult(snippets: results);
    }

    final brave = await _get(braveEndpoint, {'q': trimmed, 'source': 'web'});
    if (brave == null) {
      return DuckDuckGoResult(
        error: duck.status == 200
            ? 'no search engine answered with results'
            : 'the search service answered ${duck.status}',
      );
    }
    final braveResults = brave.status == 200
        ? parseBrave(brave.body, fetchedAt: _clock(), limit: limit)
        : const <WebSnippet>[];
    if (braveResults.isNotEmpty) {
      return DuckDuckGoResult(snippets: braveResults);
    }

    final wiki = await _get(wikipediaEndpoint, {
      'action': 'query',
      'list': 'search',
      'srsearch': trimmed,
      'srlimit': '$limit',
      'format': 'json',
      'utf8': '1',
    });
    if (wiki != null && wiki.status == 200) {
      final results = parseWikipedia(
        wiki.body,
        fetchedAt: _clock(),
        limit: limit,
      );
      if (results.isNotEmpty) return DuckDuckGoResult(snippets: results);
    }

    return DuckDuckGoResult(
      error:
          'duckduckgo answered ${duck.status}, brave ${brave.status}, '
          'wikipedia ${wiki?.status ?? 'unreachable'}',
    );
  }

  /// Reads Wikipedia's search JSON into snippets with real article URLs.
  static List<WebSnippet> parseWikipedia(
    String body, {
    required DateTime fetchedAt,
    int limit = 5,
  }) {
    final decoded = jsonDecodeOrNull(body);
    if (decoded is! Map) return const [];
    final query = decoded['query'];
    if (query is! Map) return const [];
    final results = query['search'];
    if (results is! List) return const [];
    final snippets = <WebSnippet>[];
    for (final entry in results) {
      if (snippets.length >= limit) break;
      if (entry is! Map) continue;
      final title = entry['title'];
      if (title is! String || title.trim().isEmpty) continue;
      final text = _squash(
        WebFetchService.htmlToText('${entry['snippet'] ?? ''}'),
      );
      snippets.add(
        WebSnippet(
          url:
              'https://en.wikipedia.org/wiki/'
              '${Uri.encodeComponent(title.trim().replaceAll(' ', '_'))}',
          fetchedAt: fetchedAt,
          text: text.isEmpty ? title.trim() : text,
          title: title.trim(),
          provider: 'duckduckgo',
        ),
      );
    }
    return snippets;
  }

  static Object? jsonDecodeOrNull(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  Future<({int status, String body})?> _get(
    String url,
    Map<String, String> query,
  ) async {
    try {
      final client = _dio ?? Dio();
      final response = await client.get(
        url,
        queryParameters: query,
        options: Options(
          headers: {
            'User-Agent': userAgent,
            'Accept': 'text/html,application/xhtml+xml',
            'Accept-Language': 'en-US,en;q=0.9',
          },
          responseType: ResponseType.plain,
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          followRedirects: true,
          validateStatus: (_) => true,
        ),
      );
      final data = response.data;
      return (
        status: response.statusCode ?? 0,
        body: data is String ? data : '',
      );
    } on DioException catch (error) {
      if (error.response?.statusCode != null) {
        return (status: error.response!.statusCode!, body: '');
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Reads the result list out of a DuckDuckGo HTML page.
  ///
  /// Two shapes are accepted because the endpoint serves both: `/l/?uddg=…`
  /// redirect links and direct links. A result without a usable http(s) URL is
  /// dropped rather than shown with a placeholder.
  static List<WebSnippet> parseDuckDuckGo(
    String html, {
    required DateTime fetchedAt,
    int limit = 5,
  }) {
    final snippets = <WebSnippet>[];
    final anchors = RegExp(
      r'<a[^>]+class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
      dotAll: true,
      caseSensitive: false,
    ).allMatches(html);
    for (final anchor in anchors) {
      if (snippets.length >= limit) break;
      final url = normalizeResultUrl(anchor.group(1) ?? '');
      if (url == null) continue;
      final title = _squash(WebFetchService.htmlToText(anchor.group(2) ?? ''));
      snippets.add(
        WebSnippet(
          url: url,
          fetchedAt: fetchedAt,
          text: title,
          title: title,
          provider: 'duckduckgo',
        ),
      );
    }
    if (snippets.isEmpty) return const [];

    // Snippets belong to the result above them; the page lists them in order,
    // so the n-th summary fills the n-th result when the counts line up.
    final summaries = RegExp(
      r'<a[^>]+class="[^"]*result__snippet[^"]*"[^>]*>(.*?)</a>',
      dotAll: true,
      caseSensitive: false,
    );
    final texts = [
      for (final match in summaries.allMatches(html))
        _squash(WebFetchService.htmlToText(match.group(1) ?? '')),
    ];
    if (texts.length != snippets.length) return snippets;
    return [
      for (var index = 0; index < snippets.length; index++)
        WebSnippet(
          url: snippets[index].url,
          fetchedAt: snippets[index].fetchedAt,
          text: texts[index].isEmpty ? snippets[index].text : texts[index],
          title: snippets[index].title,
          provider: 'duckduckgo',
        ),
    ];
  }

  /// Reads web results out of Brave's HTML search page.
  ///
  /// Each result is a heading anchor (class `desktop-heading-h3`) whose target
  /// is the page, followed by a `generic-snippet` block with the description.
  /// Search-engine house links are skipped: they are navigation, not sources.
  static List<WebSnippet> parseBrave(
    String html, {
    required DateTime fetchedAt,
    int limit = 5,
  }) {
    final snippets = <WebSnippet>[];
    final anchors = RegExp(
      r'<a href="(https?://[^"]+)"[^>]*class="[^"]*desktop-heading-h3[^"]*"[^>]*>(.*?)</a>',
      dotAll: true,
      caseSensitive: false,
    ).allMatches(html);
    for (final anchor in anchors) {
      if (snippets.length >= limit) break;
      final url = normalizeResultUrl(anchor.group(1) ?? '');
      if (url == null || _isSearchEngineHost(url)) continue;
      if (snippets.any((snippet) => snippet.url == url)) continue;
      final title = _squash(WebFetchService.htmlToText(anchor.group(2) ?? ''));
      final tail = html.substring(
        anchor.end,
        (anchor.end + 4000).clamp(0, html.length),
      );
      final description = RegExp(
        r'class="content desktop-default-regular[^"]*"[^>]*>(.*?)</div>',
        dotAll: true,
        caseSensitive: false,
      ).firstMatch(tail);
      final text = description == null
          ? ''
          : _squash(WebFetchService.htmlToText(description.group(1) ?? ''));
      snippets.add(
        WebSnippet(
          url: url,
          fetchedAt: fetchedAt,
          text: text.isEmpty ? title : text,
          title: title,
          provider: 'duckduckgo',
        ),
      );
    }
    return snippets;
  }

  /// One line of plain text: the endpoints wrap titles across source lines and
  /// escape punctuation as entities (`&#x27;`, `&amp;`, `&#39;`).
  static String _squash(String value) {
    final decoded = value
        .replaceAllMapped(
          RegExp(r'&#x([0-9a-fA-F]+);'),
          (match) => String.fromCharCode(
            int.tryParse(match.group(1)!, radix: 16) ?? 63,
          ),
        )
        .replaceAllMapped(
          RegExp(r'&#(\d+);'),
          (match) => String.fromCharCode(int.tryParse(match.group(1)!) ?? 63),
        )
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
    return decoded.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _isSearchEngineHost(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.endsWith('brave.com') ||
        host.endsWith('duckduckgo.com') ||
        host.endsWith('google.com') ||
        host.endsWith('bing.com');
  }

  /// The real target of a result link, or null when it is not http(s).
  static String? normalizeResultUrl(String href) {
    var value = href.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('//')) value = 'https:$value';
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    if (uri.host.contains('duckduckgo.com') &&
        uri.queryParameters['uddg'] != null) {
      return normalizeResultUrl(uri.queryParameters['uddg']!);
    }
    if (!uri.hasScheme) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return uri.toString();
  }
}

/// What one search returned, and why when it returned nothing.
class DuckDuckGoResult {
  const DuckDuckGoResult({this.snippets = const [], this.error});

  final List<WebSnippet> snippets;

  /// Null when an engine answered: an empty list then means it genuinely had
  /// no results. Otherwise a short, user-safe reason.
  final String? error;

  bool get isFailure => error != null;
}
