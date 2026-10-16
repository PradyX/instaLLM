/// Opt-in network policy for explicit web use (Road Map 3 Phase 3.4).
///
/// Part 2 deliberately deferred browsing. Part 3 allows explicit web use only:
/// off by default, per-workspace, per-tool. No background fetching, no link
/// prefetching, no telemetry.
///
/// Every field defaults to the closed posture, so a collection stored before
/// the policy existed answers exactly as it always has: nothing leaves the
/// device until the user enables one tool in one workspace.
class NetworkPolicy {
  const NetworkPolicy({
    this.fetchUrlEnabled = false,
    this.webSearchEnabled = false,
    this.webSearchProvider = '',
    this.youtubeEnabled = false,
  });

  /// Whether `fetch_url` may run in this workspace.
  final bool fetchUrlEnabled;

  /// Whether `web_search` may run in this workspace. Requires a
  /// user-configured provider plus key (the key itself lives in secure
  /// storage, never in this file).
  final bool webSearchEnabled;

  /// Which search provider the workspace uses (`tavily`, `brave`, ...).
  /// Empty means unconfigured, which refuses `web_search` like disabled.
  final String webSearchProvider;

  /// Whether YouTube transcript ingest may fetch captions for an explicit URL.
  final bool youtubeEnabled;

  /// Closed posture: everything off, no provider.
  static const NetworkPolicy closed = NetworkPolicy();

  /// True when `fetch_url` may run here.
  bool get allowsFetchUrl => fetchUrlEnabled;

  /// True when `web_search` may run here: enabled and configured.
  bool get allowsWebSearch =>
      webSearchEnabled && webSearchProvider.trim().isNotEmpty;

  /// True when YouTube ingest may fetch for an explicit URL.
  bool get allowsYoutube => youtubeEnabled && fetchUrlEnabled;

  NetworkPolicy copyWith({
    bool? fetchUrlEnabled,
    bool? webSearchEnabled,
    String? webSearchProvider,
    bool? youtubeEnabled,
  }) {
    return NetworkPolicy(
      fetchUrlEnabled: fetchUrlEnabled ?? this.fetchUrlEnabled,
      webSearchEnabled: webSearchEnabled ?? this.webSearchEnabled,
      webSearchProvider: webSearchProvider ?? this.webSearchProvider,
      youtubeEnabled: youtubeEnabled ?? this.youtubeEnabled,
    );
  }

  /// Provider id trimmed and length-bounded for storage.
  NetworkPolicy normalized() {
    final provider = webSearchProvider.trim();
    return NetworkPolicy(
      fetchUrlEnabled: fetchUrlEnabled,
      webSearchEnabled: webSearchEnabled,
      webSearchProvider: provider.length <= NetworkPolicyLimits.maxProviderId
          ? provider
          : provider.substring(0, NetworkPolicyLimits.maxProviderId),
      youtubeEnabled: youtubeEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'fetchUrlEnabled': fetchUrlEnabled,
    'webSearchEnabled': webSearchEnabled,
    'webSearchProvider': webSearchProvider,
    'youtubeEnabled': youtubeEnabled,
  };

  /// Parses stored policy, or the closed default when [raw] is missing,
  /// corrupt, or from before the policy existed — never null, never throwing.
  static NetworkPolicy fromJson(Object? raw) {
    if (raw is! Map) return NetworkPolicy.closed;
    final map = Map<String, dynamic>.from(raw);
    final provider = map['webSearchProvider'];
    return NetworkPolicy(
      fetchUrlEnabled: map['fetchUrlEnabled'] == true,
      webSearchEnabled: map['webSearchEnabled'] == true,
      webSearchProvider: provider is String ? provider : '',
      youtubeEnabled: map['youtubeEnabled'] == true,
    ).normalized();
  }
}

/// Bounds that keep a hand-edited policy file honest.
abstract final class NetworkPolicyLimits {
  /// Longest provider id stored; longer values are truncated.
  static const int maxProviderId = 40;

  /// Longest workspace id keyed in the file.
  static const int maxWorkspaceIdLength = 120;

  /// Most workspace overrides one file holds; older files never had any.
  static const int maxWorkspaces = 200;
}

/// Explicit web text, labelled at the source (Road Map 3 Phase 3.4).
///
/// Retrieved web text is labelled as web text, never trusted facts: every
/// snippet carries its source URL and fetch time, and the prompt prefix says
/// so. No background fetching: a snippet exists only because the user or the
/// model asked for that URL through an enabled tool.
class WebSnippet {
  const WebSnippet({
    required this.url,
    required this.fetchedAt,
    required this.text,
    this.title = '',
    this.provider = '',
  });

  /// Source URL the text was fetched from.
  final String url;

  /// When the fetch completed, in words the model can quote.
  final DateTime fetchedAt;

  /// Markdown or plain text of the page, already size-capped by the fetcher.
  final String text;

  /// Page title when the fetcher knew one.
  final String title;

  /// Search provider that returned this result, or empty for a direct fetch.
  final String provider;

  /// `web · https://example.com · 2026-10-16T07:00:00.000 — title`.
  String get label {
    final titlePart = title.trim().isEmpty ? '' : ' — ${title.trim()}';
    return 'web · $url · ${fetchedAt.toIso8601String()}$titlePart';
  }

  /// Prompt-ready rendering: source line first, then the text, so a model
  /// can cite where web words came from instead of stating them as facts.
  String render() {
    final buffer = StringBuffer()
      ..writeln('[web snippet] $label')
      ..writeln(text.trim());
    return buffer.toString().trimRight();
  }
}

/// Limits that keep one web fetch honest.
abstract final class WebFetchLimits {
  /// Largest page text kept, in characters. Pages past this are truncated
  /// with an ellipsis rather than refused, so a long article still answers.
  static const int maxCharacters = 12000;

  /// Longest URL accepted, so a model cannot pass a document as one input.
  static const int maxUrlLength = 2000;

  /// Search providers this build knows how to call. A stored provider outside
  /// this set refuses like unconfigured rather than guessing an endpoint.
  static const List<String> knownProviders = ['tavily', 'brave'];
}
