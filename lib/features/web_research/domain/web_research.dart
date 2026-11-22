/// Agentic web search with citations (Road Map 5 Phase 5.5).
///
/// The turn searches only when a question actually needs current or external
/// information, reads a bounded number of pages, and answers with sources that
/// carry the URL each claim came from and the time it was read. This file is
/// the pure part: the intent rule, the citation marker parsing and the block
/// the prompt receives — no socket, no clock, no model.
library;

import 'dart:convert';

/// One page the turn actually read.
class WebSource {
  const WebSource({
    required this.marker,
    required this.url,
    required this.title,
    required this.fetchedAt,
    this.excerpt = '',
  });

  /// The number the answer cites: `[1]` is this source.
  final int marker;
  final String url;
  final String title;
  final DateTime fetchedAt;
  final String excerpt;

  /// Host shown in the transcript, e.g. `en.wikipedia.org`.
  String get host => Uri.tryParse(url)?.host ?? '';

  /// One line for the prompt and the transcript.
  String get label {
    final named = title.trim().isEmpty ? host : title.trim();
    return '$named — $url (read ${_stamp(fetchedAt)})';
  }

  Map<String, dynamic> toJson() => {
    'marker': marker,
    'url': url,
    'title': title,
    'fetchedAt': fetchedAt.toIso8601String(),
    if (excerpt.isNotEmpty) 'excerpt': excerpt,
  };

  static WebSource? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final url = map['url'];
    final marker = map['marker'];
    final fetchedAt = DateTime.tryParse(map['fetchedAt'] as String? ?? '');
    if (url is! String || url.trim().isEmpty) return null;
    if (marker is! int || marker < 1) return null;
    if (fetchedAt == null) return null;
    return WebSource(
      marker: marker,
      url: url,
      title: map['title'] is String ? map['title'] as String : '',
      fetchedAt: fetchedAt,
      excerpt: map['excerpt'] is String ? map['excerpt'] as String : '',
    );
  }

  static String _stamp(DateTime value) =>
      '${value.toIso8601String().split('.').first.replaceFirst('T', ' ')} UTC'
          .replaceFirst(' UTC', 'Z');
}

/// Why the turn has no web answer. Each one becomes a sentence the user reads
/// instead of an invented result.
enum WebResearchFailureKind {
  /// The workspace network policy does not allow search or reading.
  refused,

  /// The request never left the device, or the reply never arrived.
  unreachable,

  /// The provider answered, but with nothing usable.
  noResults,
}

class WebResearchFailure {
  const WebResearchFailure(this.kind, this.message);

  final WebResearchFailureKind kind;
  final String message;

  String get text => message.trim();
}

/// What one turn learned from the web.
class WebResearch {
  const WebResearch({required this.query, required this.sources});

  final String query;
  final List<WebSource> sources;

  bool get isEmpty => sources.isEmpty;

  /// The system-prompt block: every page numbered, labelled as web text and
  /// timestamped, so an answer can cite `[n]` and the marker is checkable
  /// against the transcript.
  String promptBlock() {
    final buffer = StringBuffer()
      ..writeln(
        '[web research] Search "$query" read these pages on '
        '${_stampSources()} (web text, not trusted facts):',
      );
    for (final source in sources) {
      buffer.writeln('[${source.marker}] ${source.label}');
      if (source.excerpt.trim().isNotEmpty) {
        buffer.writeln(source.excerpt.trim());
      }
      buffer.writeln();
    }
    buffer.writeln(
      'Answer the question in one or two sentences using only these pages, '
      'and end the answer with the number of the page you used in square '
      'brackets, for example: The latest version is 17 [3]. If the pages do '
      'not answer the question, say so plainly instead of guessing; never cite '
      'a page you did not read.',
    );
    return buffer.toString().trimRight();
  }

  String _stampSources() =>
      sources.isEmpty ? '' : sources.first.fetchedAt.toIso8601String();

  static List<WebSource> sort(List<WebSource> sources) {
    final sorted = [...sources]..sort((a, b) => a.marker.compareTo(b.marker));
    return sorted;
  }
}

/// Decides whether a question needs the web at all.
///
/// Deliberately conservative: a greeting, a calculation or a request about the
/// conversation must not spend a search on itself. Phrases that name the present
/// — news, today, latest, prices, weather, scores, releases — do, and so does an
/// explicit "search"/"look up".
abstract final class WebSearchIntent {
  static final List<RegExp> _live = [
    RegExp(
      r'\b(latest|newest|current|currently|today|tonight|yesterday|this (week|month|year)|right now|as of)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(news|headlines|weather|forecast|price|prices|stock|exchange rate|'
      r'score|scores|result|results|who won|release date|released|launch date|'
      r'election|population of)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(search|look up|google|browse|on the web|online)\b',
      caseSensitive: false,
    ),
    // A year that is this one or the next one reads as "current information".
    RegExp(r'\b20(2[4-9]|3[0-9])\b'),
  ];

  static bool needsLiveInformation(String text, {DateTime? now}) {
    final trimmed = text.trim();
    if (trimmed.length < 4) return false;
    return _live.any((pattern) => pattern.hasMatch(trimmed));
  }
}

/// Marker numbers an answer actually used, in order, without duplicates.
List<int> citedMarkers(String answer) {
  final seen = <int>{};
  for (final match in RegExp(r'\[(\d{1,2})\]').allMatches(answer)) {
    final index = int.tryParse(match.group(1) ?? '');
    if (index != null && index > 0) seen.add(index);
  }
  return seen.toList()..sort();
}

/// The sources an answer cites, or an empty list when it cites nothing.
List<WebSource> citedSources(String answer, List<WebSource> sources) {
  final markers = citedMarkers(answer).toSet();
  if (markers.isEmpty) return const [];
  return [
    for (final source in WebResearch.sort(sources))
      if (markers.contains(source.marker)) source,
  ];
}

/// URLs in a `web_search` tool output, in the order they appear, deduplicated.
///
/// The tool renders one `web · <url> · <time> — title` line per result, so the
/// loop can read the candidate pages without a second, parallel search path.
List<String> urlsFromSearchOutput(String output) {
  final urls = <String>[];
  for (final match in RegExp(r'https?://[^\s\)\]]+').allMatches(output)) {
    final url = match.group(0)!.replaceAll(RegExp(r'[.,;:]$'), '');
    if (url.isEmpty || urls.contains(url)) continue;
    urls.add(url);
  }
  return urls;
}

/// Titles paired with [urlsFromSearchOutput] where the tool knew them.
List<String> titlesFromSearchOutput(String output, List<String> urls) {
  return [
    for (final url in urls)
      () {
        final line = output
            .split('\n')
            .firstWhere((entry) => entry.contains(url), orElse: () => '');
        final dash = line.lastIndexOf('— ');
        return dash == -1 ? '' : line.substring(dash + 2).trim();
      }(),
  ];
}

/// JSON for the transcript store: sources as a plain list.
String encodeWebSources(List<WebSource> sources) =>
    jsonEncode([for (final source in sources) source.toJson()]);

/// Reads stored sources, skipping anything a newer build or a hand-edited file
/// left unreadable instead of failing the whole message.
List<WebSource> decodeWebSources(Object? raw) {
  if (raw is String) return decodeWebSources(_tryDecode(raw));
  if (raw is! List) return const [];
  final sources = <WebSource>[];
  for (final entry in raw) {
    final source = WebSource.fromJson(entry);
    if (source != null) sources.add(source);
  }
  return WebResearch.sort(sources);
}

Object? _tryDecode(String raw) {
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
}
