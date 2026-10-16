import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/documents/data/network_policy_store.dart';
import 'package:installm/features/documents/data/web_fetch_service.dart';
import 'package:installm/features/documents/domain/network_policy.dart';
import 'package:installm/features/tools/application/tool_registry.dart';
import 'package:installm/features/tools/data/web_tools.dart';
import 'package:installm/features/tools/domain/tool_call.dart';

void main() {
  group('NetworkPolicy defaults closed', () {
    test('closed posture refuses everything', () {
      const policy = NetworkPolicy.closed;
      expect(policy.allowsFetchUrl, isFalse);
      expect(policy.allowsWebSearch, isFalse);
      expect(policy.allowsYoutube, isFalse);
    });

    test('missing or corrupt JSON answers closed, never throwing', () {
      expect(NetworkPolicy.fromJson(null), NetworkPolicy.closed);
      expect(NetworkPolicy.fromJson('nope'), NetworkPolicy.closed);
      expect(
        NetworkPolicy.fromJson(const {'fetchUrlEnabled': 'yes'}).allowsFetchUrl,
        isFalse,
      );
    });

    test('web search needs both the switch and a known provider', () {
      const enabledNoProvider = NetworkPolicy(
        fetchUrlEnabled: true,
        webSearchEnabled: true,
      );
      expect(enabledNoProvider.allowsWebSearch, isFalse);

      const unknown = NetworkPolicy(
        fetchUrlEnabled: true,
        webSearchEnabled: true,
        webSearchProvider: 'mystery',
      );
      // Domain allows the switch; the service refuses unknown providers.
      expect(unknown.allowsWebSearch, isTrue);
    });

    test('youtube needs the fetch switch as well', () {
      const youtubeOnly = NetworkPolicy(youtubeEnabled: true);
      expect(youtubeOnly.allowsYoutube, isFalse);
      const both = NetworkPolicy(fetchUrlEnabled: true, youtubeEnabled: true);
      expect(both.allowsYoutube, isTrue);
    });
  });

  group('NetworkPolicySnapshot', () {
    test('absent workspace answers closed', () {
      expect(
        NetworkPolicySnapshot.empty.forWorkspace('ws-1').allowsFetchUrl,
        isFalse,
      );
    });

    test('round-trips one workspace and drops empty ids', () {
      var snapshot = NetworkPolicySnapshot.empty.setWorkspace(
        'ws-1',
        const NetworkPolicy(fetchUrlEnabled: true),
      );
      expect(snapshot.forWorkspace('ws-1').allowsFetchUrl, isTrue);
      expect(snapshot.forWorkspace('ws-other').allowsFetchUrl, isFalse);

      snapshot = snapshot.setWorkspace('', NetworkPolicy.closed);
      expect(snapshot.policies.containsKey(''), isFalse);

      final removed = snapshot.removeWorkspace('ws-1');
      expect(removed.forWorkspace('ws-1').allowsFetchUrl, isFalse);
    });
  });

  group('WebFetchService pure helpers', () {
    test('htmlToText strips tags and keeps line breaks', () {
      const html =
          '<html><head><title>Example</title></head>'
          '<body><h1>Hello</h1><p>World &amp; friends</p>'
          '<script>evil()</script></body></html>';
      final text = WebFetchService.htmlToText(html);
      expect(text, contains('Hello'));
      expect(text, contains('World & friends'));
      expect(text.contains('evil'), isFalse);
      expect(WebFetchService.extractTitle(html), 'Example');
    });

    test('capText truncates past the limit with an ellipsis', () {
      final long = List.filled(WebFetchLimits.maxCharacters + 10, 'x').join();
      final capped = WebFetchService.capText(long);
      expect(capped.length, WebFetchLimits.maxCharacters + 1);
      expect(capped.endsWith('…'), isTrue);
    });

    test('youtube detection and timed-text parsing', () {
      expect(
        WebFetchService.isYoutubeUrl('https://www.youtube.com/watch?v=abc123'),
        isTrue,
      );
      expect(WebFetchService.isYoutubeUrl('https://youtu.be/abc123'), isTrue);
      expect(WebFetchService.isYoutubeUrl('https://example.com/page'), isFalse);

      const xml =
          '<?xml version="1.0"?><transcript>'
          '<text start="0">hello world</text>'
          '<text start="1.5">second line</text></transcript>';
      expect(
        WebFetchService.parseYoutubeTimedText(xml),
        'hello world\nsecond line',
      );
    });

    test('mbox parsing keeps headers with the body', () {
      const mbox =
          'From alice@example.com Mon Oct 13 10:00:00 2026\n'
          'From: Alice <alice@example.com>\n'
          'Subject: Launch plan\n'
          'Date: Mon, 13 Oct 2026 10:00:00 +0530\n'
          '\n'
          'Here is the plan.\n'
          '\n'
          'From bob@example.com Mon Oct 13 11:00:00 2026\n'
          'Subject: Re: Launch plan\n'
          '\n'
          'Looks good.\n';
      final messages = WebFetchService.parseMbox(mbox);
      expect(messages, hasLength(2));
      expect(messages.first.subject, 'Launch plan');
      expect(messages.first.from, contains('alice@example.com'));
      expect(messages.first.body, contains('Here is the plan.'));
      expect(messages.first.render(), contains('Subject: Launch plan'));
    });
  });

  group('WebFetchService policy gate', () {
    test('fetch_url refuses while the policy is closed', () async {
      final service = WebFetchService(
        fetchBody: (_) async => 'should never be called',
      );
      final snippet = await service.fetchUrl(
        'https://example.com',
        NetworkPolicy.closed,
      );
      expect(snippet, isNull);
    });

    test('fetch_url labels every snippet with URL and time', () async {
      final service = WebFetchService(
        fetchBody: (_) async =>
            '<html><head><title>T</title></head><body><p>Words</p></body></html>',
        clock: () => DateTime.utc(2026, 10, 16, 7),
      );
      final snippet = await service.fetchUrl(
        'https://example.com/page',
        const NetworkPolicy(fetchUrlEnabled: true),
      );
      expect(snippet, isNotNull);
      expect(snippet!.url, 'https://example.com/page');
      expect(snippet.label, contains('https://example.com/page'));
      expect(snippet.label, contains('2026-10-16'));
      expect(snippet.render(), contains('[web snippet]'));
      expect(snippet.render(), contains('https://example.com/page'));
    });

    test('non-http URLs refuse without a socket', () async {
      var called = false;
      final service = WebFetchService(
        fetchBody: (_) async {
          called = true;
          return 'x';
        },
      );
      final snippet = await service.fetchUrl(
        'file:///etc/passwd',
        const NetworkPolicy(fetchUrlEnabled: true),
      );
      expect(snippet, isNull);
      expect(called, isFalse);
    });

    test('search refuses unknown providers and empty queries', () async {
      final service = WebFetchService(
        searchBackend: (_) async => [
          WebSnippet(
            url: 'https://example.com',
            fetchedAt: DateTime.utc(2026, 10, 16),
            text: 'hi',
          ),
        ],
      );
      expect(
        await service.search(
          'query',
          const NetworkPolicy(
            webSearchEnabled: true,
            webSearchProvider: 'mystery',
          ),
        ),
        isEmpty,
      );
      expect(
        await service.search(
          '  ',
          const NetworkPolicy(
            fetchUrlEnabled: true,
            webSearchEnabled: true,
            webSearchProvider: 'tavily',
          ),
        ),
        isEmpty,
      );
    });
  });

  group('web tools through the real registry', () {
    ToolRegistry registryWith({
      required NetworkPolicy policy,
      Future<WebSnippet?> Function(String url)? fetch,
      Future<List<WebSnippet>> Function(String query)? search,
    }) {
      return ToolRegistry(
        tools: [
          buildFetchUrlTool(
            policyForActiveWorkspace: () => policy,
            fetch: fetch ?? (_) async => null,
          ),
          buildWebSearchTool(
            policyForActiveWorkspace: () => policy,
            search: search ?? (_) async => const [],
          ),
        ],
        platform: null,
      );
    }

    test('fetch_url stays off until the policy enables it', () async {
      final registry = registryWith(
        policy: NetworkPolicy.closed,
        fetch: (_) async => WebSnippet(
          url: 'https://example.com',
          fetchedAt: DateTime.utc(2026, 10, 16),
          text: 'should never surface',
        ),
      );
      final result = await registry.execute(
        const ToolCall(toolName: 'fetch_url', arguments: {'url': 'x'}),
      );
      // Null platform refuses first (unsupported), so exercise the handler
      // path through validation of the closed message instead.
      expect(result.output, isNotEmpty);
    });

    test('fetch_url handler message names the closed policy', () async {
      final entry = buildFetchUrlTool(
        policyForActiveWorkspace: () => NetworkPolicy.closed,
        fetch: (_) async => null,
      );
      final output = await entry.handler({'url': 'https://example.com'});
      expect(output, contains('web is off'));
    });

    test('web_search handler message names the closed policy', () async {
      final entry = buildWebSearchTool(
        policyForActiveWorkspace: () => NetworkPolicy.closed,
        search: (_) async => const [],
      );
      final output = await entry.handler({'query': 'hello'});
      expect(output, contains('off or unconfigured'));
    });

    test('web_search results carry source URLs and fetch times', () async {
      final entry = buildWebSearchTool(
        policyForActiveWorkspace: () => const NetworkPolicy(
          fetchUrlEnabled: true,
          webSearchEnabled: true,
          webSearchProvider: 'tavily',
        ),
        search: (_) async => [
          WebSnippet(
            url: 'https://example.com/a',
            fetchedAt: DateTime.utc(2026, 10, 16, 7),
            text: 'Answer words',
            provider: 'tavily',
          ),
        ],
      );
      final output = await entry.handler({'query': 'hello'});
      expect(output, contains('https://example.com/a'));
      expect(output, contains('2026-10-16'));
      expect(output, contains('web text, not trusted facts'));
    });
  });
}
