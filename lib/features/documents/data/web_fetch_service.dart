import 'package:dio/dio.dart';
import 'package:installm/features/documents/domain/network_policy.dart';

/// Explicit web fetching for one workspace (Road Map 3 Phase 3.4).
///
/// There is no background fetching here: a snippet exists only because the
/// user or the model asked for that URL through an enabled tool. The network
/// policy decides first — a disabled workspace refuses before any socket
/// opens — and every snippet carries its source URL and fetch time so
/// retrieved web text reads as web text, never as trusted facts.
///
/// Fetchers are injectable so tests can answer without a socket: the default
/// answers over `dio` with a size cap and a plain HTML-to-text pass.
class WebFetchService {
  WebFetchService({
    Dio? dio,
    Future<String> Function(Uri uri)? fetchBody,
    Future<List<WebSnippet>> Function(String query)? searchBackend,
    DateTime Function()? clock,
  }) : _dio = dio,
       _fetchBody = fetchBody,
       _searchBackend = searchBackend,
       _clock = clock ?? DateTime.now;

  final Dio? _dio;
  final Future<String> Function(Uri uri)? _fetchBody;
  final Future<List<WebSnippet>> Function(String query)? _searchBackend;
  final DateTime Function() _clock;

  /// Fetches [rawUrl] as text for an explicit request.
  ///
  /// Returns null when the URL is not an http(s) URL, the workspace policy
  /// refuses it, or the fetch fails — the tool then says so instead of
  /// answering with nothing.
  Future<WebSnippet?> fetchUrl(String rawUrl, NetworkPolicy policy) async {
    if (!policy.allowsFetchUrl) return null;
    final uri = _parseUrl(rawUrl);
    if (uri == null) return null;
    try {
      final body = await _body(uri);
      final text = htmlToText(body);
      if (text.trim().isEmpty) return null;
      return WebSnippet(
        url: uri.toString(),
        fetchedAt: _clock(),
        text: capText(text),
        title: extractTitle(body),
      );
    } catch (_) {
      return null;
    }
  }

  /// Searches the web through the workspace's configured provider.
  ///
  /// The API key itself lives in secure storage and never in the policy file;
  /// this service receives a search backend the caller built with that key.
  /// Empty when the policy refuses, the provider is unknown, or no backend
  /// was supplied — the tool then says so.
  Future<List<WebSnippet>> search(String query, NetworkPolicy policy) async {
    if (!policy.allowsWebSearch) return const [];
    if (!WebFetchLimits.knownProviders.contains(
      policy.webSearchProvider.trim(),
    )) {
      return const [];
    }
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final backend = _searchBackend;
    if (backend == null) return const [];
    try {
      final snippets = await backend(trimmed);
      return [
        for (final snippet in snippets.take(5))
          WebSnippet(
            url: snippet.url,
            fetchedAt: snippet.fetchedAt,
            text: capText(snippet.text),
            title: snippet.title,
            provider: policy.webSearchProvider.trim(),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<String> _body(Uri uri) async {
    final fetch = _fetchBody;
    if (fetch != null) return fetch(uri);
    final dio = _dio ?? Dio();
    final response = await dio.getUri(
      uri,
      options: Options(
        responseType: ResponseType.plain,
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    final data = response.data;
    if (data is String) return data;
    return data.toString();
  }

  /// http(s) URLs within the length bound, or null.
  static Uri? _parseUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty || trimmed.length > WebFetchLimits.maxUrlLength) {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return uri;
  }

  /// Keeps the first [WebFetchLimits.maxCharacters] characters, so one page
  /// can never swallow the context window on its own.
  static String capText(String text) {
    if (text.length <= WebFetchLimits.maxCharacters) return text;
    return '${text.substring(0, WebFetchLimits.maxCharacters)}…';
  }

  /// Best-effort HTML to text: scripts, styles and tags go, headings and
  /// list items break lines, entities decode for the common five.
  static String htmlToText(String html) {
    var text = html.replaceAll(
      RegExp(
        r'<(script|style)[^>]*>.*?</\1>',
        dotAll: true,
        caseSensitive: false,
      ),
      ' ',
    );
    text = text.replaceAllMapped(
      RegExp(r'<(h1|h2|h3|h4|p|div|br|li|tr)[^>]*>', caseSensitive: false),
      (_) => '\n',
    );
    text = text.replaceAll(RegExp(r'<[^>]*>'), ' ');
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  /// Best-effort `<title>` extraction for snippet labels.
  static String extractTitle(String html) {
    final match = RegExp(
      r'<title[^>]*>(.*?)</title>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(html);
    if (match == null) return '';
    return htmlToText(match.group(1) ?? '').trim();
  }

  /// True for a YouTube watch/share URL with a video id.
  static bool isYoutubeUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    if (host == 'youtu.be') return uri.pathSegments.isNotEmpty;
    if (host.endsWith('youtube.com')) {
      if (uri.path == '/watch') return uri.queryParameters['v'] != null;
      if (uri.pathSegments.isNotEmpty &&
          (uri.pathSegments.first == 'shorts' ||
              uri.pathSegments.first == 'embed')) {
        return true;
      }
    }
    return false;
  }

  /// Transcript lines of a YouTube timed-text response (`<text start=..>`),
  /// joined as plain lines. Explicit URLs only — the captions exist because
  /// the user named that video.
  static String parseYoutubeTimedText(String xml) {
    final matches = RegExp(
      r'<text[^>]*>(.*?)</text>',
      dotAll: true,
    ).allMatches(xml);
    final lines = <String>[];
    for (final match in matches) {
      final line = htmlToText(match.group(1) ?? '').trim();
      if (line.isNotEmpty) lines.add(line);
    }
    return lines.join('\n');
  }

  /// Messages of an mbox file: each `From ` separator starts one message and
  /// its `Subject:`/`Date:`/`From:` headers travel with the body excerpt.
  /// Local files only, picked by the user — nothing is fetched.
  static List<MboxMessage> parseMbox(String content) {
    final messages = <MboxMessage>[];
    final chunks = content.split(RegExp(r'^From .*$', multiLine: true));
    for (final chunk in chunks) {
      final trimmed = chunk.trim();
      if (trimmed.isEmpty) continue;
      final lines = trimmed.split('\n');
      var subject = '';
      var from = '';
      var date = '';
      var bodyStart = 0;
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (line.trim().isEmpty) {
          bodyStart = index + 1;
          break;
        }
        final lower = line.toLowerCase();
        if (lower.startsWith('subject:')) {
          subject = line.substring(8).trim();
        } else if (lower.startsWith('from:')) {
          from = line.substring(5).trim();
        } else if (lower.startsWith('date:')) {
          date = line.substring(5).trim();
        }
        bodyStart = index + 1;
      }
      final body = lines
          .skip(bodyStart)
          .join('\n')
          .replaceAll(RegExp(r'^>From ', multiLine: true), 'From ')
          .trim();
      if (body.isEmpty && subject.isEmpty) continue;
      messages.add(
        MboxMessage(subject: subject, from: from, date: date, body: body),
      );
    }
    return messages;
  }
}

/// One message of a user-picked mbox file.
class MboxMessage {
  const MboxMessage({
    required this.subject,
    required this.from,
    required this.date,
    required this.body,
  });

  final String subject;
  final String from;
  final String date;
  final String body;

  /// File-ready rendering: headers first, then the body, so the import reads
  /// as mail rather than as anonymous text.
  String render() {
    final buffer = StringBuffer();
    if (subject.isNotEmpty) buffer.writeln('Subject: $subject');
    if (from.isNotEmpty) buffer.writeln('From: $from');
    if (date.isNotEmpty) buffer.writeln('Date: $date');
    if (buffer.isNotEmpty) buffer.writeln();
    buffer.write(body.trim());
    return buffer.toString().trimRight();
  }
}
