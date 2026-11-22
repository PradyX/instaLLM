import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/conversations/domain/message.dart';
import 'package:installm/features/documents/data/duckduckgo_search.dart';
import 'package:installm/features/documents/data/web_fetch_service.dart';
import 'package:installm/features/documents/domain/network_policy.dart';
import 'package:installm/features/tools/application/tools_providers.dart';
import 'package:installm/features/web_research/application/web_research_service.dart';
import 'package:installm/features/web_research/domain/web_research.dart';

final DateTime _readAt = DateTime.utc(2026, 11, 22, 9, 30);

WebSnippet _snippet(int index) => WebSnippet(
  url: 'https://example$index.org/story',
  fetchedAt: _readAt,
  text: 'Excerpt $index',
  title: 'Story $index',
  provider: 'duckduckgo',
);

const _openSearch = NetworkPolicy(
  webSearchEnabled: true,
  webSearchProvider: 'duckduckgo',
);

WebSearchOutcome _outcome(List<WebSnippet> snippets) =>
    WebSearchOutcome(snippets: snippets);

void main() {
  group('search intent', () {
    test('a question about the present needs the web', () {
      expect(
        WebSearchIntent.needsLiveInformation(
          'What is the latest Android version?',
        ),
        isTrue,
      );
      expect(
        WebSearchIntent.needsLiveInformation('who won the match yesterday'),
        isTrue,
      );
      expect(
        WebSearchIntent.needsLiveInformation('search the web for koalas'),
        isTrue,
      );
      expect(
        WebSearchIntent.needsLiveInformation('what is the exchange rate today'),
        isTrue,
      );
    });

    test('a question the model can answer itself does not search', () {
      expect(WebSearchIntent.needsLiveInformation('hi'), isFalse);
      expect(WebSearchIntent.needsLiveInformation('what is 12*9'), isFalse);
      expect(
        WebSearchIntent.needsLiveInformation('summarise our conversation'),
        isFalse,
      );
      expect(WebSearchIntent.needsLiveInformation('   '), isFalse);
    });
  });

  group('duckduckgo parsing', () {
    const html = '''
<html><body>
  <div class="result">
    <a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.org%2Fa&amp;rut=1">Example
      result</a>
    <a class="result__snippet" href="#">Example snippet text.</a>
  </div>
  <div class="result">
    <a class="result__a" href="https://other.example/b">Second <b>result</b></a>
    <a class="result__snippet" href="#">Other snippet.</a>
  </div>
  <div class="result">
    <a class="result__a" href="javascript:alert(1)">Bad link</a>
  </div>
</body></html>
''';

    test('reads real URLs and titles, drops unusable links', () {
      final results = KeylessWebSearch.parseDuckDuckGo(
        html,
        fetchedAt: _readAt,
      );
      expect(results, hasLength(2));
      expect(results.first.url, 'https://example.org/a');
      expect(results.first.title, 'Example result');
      expect(results.first.text, 'Example snippet text.');
      expect(results.first.fetchedAt, _readAt);
      expect(results[1].url, 'https://other.example/b');
      expect(results[1].title, 'Second result');
    });

    test('a redirect wrapper resolves to its target', () {
      expect(
        KeylessWebSearch.normalizeResultUrl(
          'https://duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.org%2Fx',
        ),
        'https://example.org/x',
      );
      expect(
        KeylessWebSearch.normalizeResultUrl('javascript:alert(1)'),
        isNull,
      );
      expect(KeylessWebSearch.normalizeResultUrl('/relative'), isNull);
    });

    test('an empty page is no results, not an error', () {
      expect(
        KeylessWebSearch.parseDuckDuckGo('<html></html>', fetchedAt: _readAt),
        isEmpty,
      );
    });
  });

  group('citations', () {
    final sources = [
      WebSource(
        marker: 1,
        url: 'https://a.example/one',
        title: 'One',
        fetchedAt: _readAt,
      ),
      WebSource(
        marker: 2,
        url: 'https://b.example/two',
        title: 'Two',
        fetchedAt: _readAt,
      ),
    ];

    test('only markers the answer used are cited', () {
      expect(citedMarkers('Android 16 shipped [2]. See also [2] and [7].'), [
        2,
        7,
      ]);
      expect(citedSources('Android 16 shipped [2].', sources), hasLength(1));
      expect(citedSources('Android 16 shipped [2].', sources).single.marker, 2);
    });

    test('an answer without markers cites nothing', () {
      expect(citedMarkers('It shipped in 2025.'), isEmpty);
      expect(citedSources('It shipped in 2025.', sources), isEmpty);
    });

    test('the prompt block names every page with its URL and time', () {
      final block = WebResearch(
        query: 'android',
        sources: sources,
      ).promptBlock();
      expect(block, contains('[1] One — https://a.example/one'));
      expect(block, contains('[2] Two — https://b.example/two'));
      expect(block, contains('2026-11-22T09:30:00.000Z'));
      expect(block, contains('never cite a page you did not read'));
      expect(block, contains('web text, not trusted facts'));
    });
  });

  group('search output', () {
    test('candidate URLs are read in order without duplicates', () {
      const output = '''
web_search results for "android":
[1] web · https://a.example/one · 2026-11-22T09:30:00.000Z — One
first body
[2] web · https://b.example/two · 2026-11-22T09:30:00.000Z — Two
second body
[3] web · https://a.example/one · 2026-11-22T09:30:00.000Z — One again
''';
      final urls = urlsFromSearchOutput(output);
      expect(urls, ['https://a.example/one', 'https://b.example/two']);
      expect(titlesFromSearchOutput(output, urls), ['One', 'Two']);
    });
  });

  group('research loop', () {
    ({NetworkPolicy policy, WebSearchRunner runner, WebFetchService? fetcher})
    container({
      required NetworkPolicy policy,
      required WebSearchRunner runner,
      WebFetchService? fetcher,
    }) {
      return (policy: policy, runner: runner, fetcher: fetcher);
    }

    WebResearchService serviceFor(
      ({NetworkPolicy policy, WebSearchRunner runner, WebFetchService? fetcher})
      harness,
    ) => WebResearchService(
      policy: () => harness.policy,
      search: harness.runner,
      fetcher: harness.fetcher,
    );

    test('a refused policy never searches', () async {
      var searched = false;
      final scoped = container(
        policy: NetworkPolicy.closed,
        runner: (query) async {
          searched = true;
          return _outcome(const []);
        },
      );
      final result = await serviceFor(
        scoped,
      ).research('latest android version');
      expect(searched, isFalse);
      expect(result.isOk, isFalse);
      expect(result.failure!.kind, WebResearchFailureKind.refused);
      expect(result.failure!.text, contains('off in this workspace'));
    });

    test('a provider error degrades honestly', () async {
      final scoped = container(
        policy: _openSearch,
        runner: (query) async => const WebSearchOutcome(
          error:
              'the search service could not be '
              'reached',
        ),
      );
      final result = await serviceFor(
        scoped,
      ).research('latest android version');
      expect(result.isOk, isFalse);
      expect(result.failure!.kind, WebResearchFailureKind.unreachable);
      expect(
        result.failure!.text,
        contains('could not reach a search service'),
      );
      expect(result.failure!.text, contains('no sources'));
    });

    test('empty results are no results, not an invented answer', () async {
      final scoped = container(
        policy: _openSearch,
        runner: (query) async => _outcome(const []),
      );
      final result = await serviceFor(
        scoped,
      ).research('latest android version');
      expect(result.isOk, isFalse);
      expect(result.failure!.kind, WebResearchFailureKind.noResults);
      expect(result.failure!.text, contains('did not invent one'));
    });

    test('pages are read through the fetch service and numbered', () async {
      final scoped = container(
        policy: const NetworkPolicy(
          webSearchEnabled: true,
          webSearchProvider: 'duckduckgo',
          fetchUrlEnabled: true,
        ),
        runner: (query) async =>
            _outcome([for (var i = 1; i <= 5; i++) _snippet(i)]),
        fetcher: WebFetchService(
          fetchBody: (uri) async =>
              '<html><head><title>Read ${uri.host}</title></head>'
              '<body><p>Article body for ${uri.path}</p></body></html>',
        ),
      );
      final result = await serviceFor(
        scoped,
      ).research('latest android version');
      expect(result.isOk, isTrue);
      final research = result.research!;
      // Budget: never more than three pages in one turn.
      expect(research.sources, hasLength(3));
      expect(research.sources.map((source) => source.marker), [1, 2, 3]);
      expect(research.sources.first.url, 'https://example1.org/story');
      expect(research.sources.first.title, 'Read example1.org');
      expect(research.sources.first.excerpt, contains('Article body'));
    });

    test(
      'a page that cannot be read falls back to the search snippet',
      () async {
        final scoped = container(
          policy: const NetworkPolicy(
            webSearchEnabled: true,
            webSearchProvider: 'duckduckgo',
            fetchUrlEnabled: true,
          ),
          runner: (query) async => _outcome([_snippet(1)]),
          fetcher: WebFetchService(
            fetchBody: (uri) async => throw Exception('offline'),
          ),
        );
        final result = await serviceFor(
          scoped,
        ).research('latest android version');
        expect(result.isOk, isTrue);
        expect(result.research!.sources.single.excerpt, 'Excerpt 1');
      },
    );
  });

  group('message storage', () {
    test('web sources survive a JSON round trip', () {
      final message = Message(
        id: 'm1',
        conversationId: 'c1',
        role: MessageRole.assistant,
        content: 'Android 16 shipped [1].',
        createdAt: _readAt,
        webSources: [
          WebSource(
            marker: 1,
            url: 'https://example.org/a',
            title: 'A',
            fetchedAt: _readAt,
            excerpt: 'Body',
          ),
        ],
      );
      final restored = Message.fromJson(message.toJson());
      expect(restored.webSources, hasLength(1));
      expect(restored.webSources.single.url, 'https://example.org/a');
      expect(restored.webSources.single.fetchedAt, _readAt);
      expect(citedSources(restored.content, restored.webSources), hasLength(1));
    });

    test('a message without web sources reads as none', () {
      final restored = Message.fromJson({
        'id': 'm2',
        'conversationId': 'c1',
        'role': 'assistant',
        'content': 'plain',
        'createdAt': _readAt.toIso8601String(),
      });
      expect(restored.webSources, isEmpty);
    });

    test('unreadable stored sources are skipped, not fatal', () {
      expect(decodeWebSources('not json'), isEmpty);
      expect(
        decodeWebSources([
          {'marker': 1, 'url': '', 'fetchedAt': _readAt.toIso8601String()},
          {'marker': 2, 'url': 'https://ok.example/x', 'fetchedAt': 'nope'},
          {
            'marker': 3,
            'url': 'https://ok.example/y',
            'fetchedAt': _readAt.toIso8601String(),
          },
        ]),
        hasLength(1),
      );
    });
  });

  test('brave html results become sources, house links dropped', () {
    const html = '''
<div class="snippet">
  <a href="https://en.wikipedia.org/wiki/Android_version_history" target="_self"
     class="desktop-heading-h3 svelte-z63s58">Android
     version history</a>
  <div class="generic-snippet svelte-1cwdgg3">
    <div class="content desktop-default-regular t-primary">June 2026:
      <strong>Android 17</strong> is the latest release.</div>
  </div>
</div>
<div class="snippet">
  <a href="https://search.brave.com/x" class="desktop-heading-h3">Brave</a>
</div>
''';
    final results = KeylessWebSearch.parseBrave(html, fetchedAt: _readAt);
    expect(results, hasLength(1));
    expect(
      results.single.url,
      'https://en.wikipedia.org/wiki/Android_version_history',
    );
    expect(results.single.title, 'Android version history');
    expect(results.single.text, contains('Android 17'));
  });

  test('duckduckgo is a keyless known provider', () {
    expect(WebFetchLimits.knownProviders, contains('duckduckgo'));
    expect(WebFetchLimits.needsKey('duckduckgo'), isFalse);
    expect(WebFetchLimits.needsKey('tavily'), isTrue);
  });
}
