import 'package:installm/features/documents/domain/network_policy.dart';
import 'package:installm/features/tools/application/tool_registry.dart';
import 'package:installm/features/tools/domain/tool_definition.dart';

/// Tool: fetch one explicit URL as Markdown-capped text.
///
/// Sensitive: it leaves the device, so the registry asks the user first even
/// when the workspace policy enables it. Refuses while the policy is closed —
/// the web stays fully off until the policy enables it — and every snippet
/// carries its source URL and fetch time.
ToolEntry buildFetchUrlTool({
  required NetworkPolicy Function() policyForActiveWorkspace,
  required Future<WebSnippet?> Function(String url) fetch,
}) {
  return ToolEntry(
    definition: const ToolDefinition(
      name: 'fetch_url',
      description:
          'Fetches one URL the user named and returns its text as Markdown, '
          'size-capped. Explicit use only: stays off until the workspace '
          'network policy enables it. The answer carries its source URL and '
          'fetch time and is labelled as web text, never as trusted facts.',
      risk: ToolRiskLevel.sensitive,
      timeout: Duration(seconds: 20),
      parameters: [
        ToolParameter(
          name: 'url',
          type: ToolParameterType.string,
          description: 'http(s) URL to fetch.',
          maxLength: 2000,
        ),
      ],
    ),
    handler: (arguments) async {
      final policy = policyForActiveWorkspace();
      if (!policy.allowsFetchUrl) {
        return 'The web is off in this workspace. The user can enable fetching '
            'in the workspace network settings; until then nothing is fetched.';
      }
      final url = arguments['url'] as String;
      final snippet = await fetch(url);
      if (snippet == null) {
        return 'Could not fetch "$url". It may be unreachable, not an http(s) '
            'URL, or larger than the text limit allows to read.';
      }
      return snippet.render();
    },
  );
}

/// Tool: search the web through the workspace's configured provider.
///
/// Sensitive: it leaves the device with the user's key, so the registry asks
/// first. Only runs through a user-configured provider plus key — there is no
/// built-in search backend — and every result carries its source URL and
/// fetch time.
ToolEntry buildWebSearchTool({
  required NetworkPolicy Function() policyForActiveWorkspace,
  required Future<List<WebSnippet>> Function(String query) search,
}) {
  return ToolEntry(
    definition: const ToolDefinition(
      name: 'web_search',
      description:
          'Searches the web through the workspace\u2019s configured provider and '
          'returns up to five results with their source URLs and fetch times. '
          'Explicit use only: stays off until the workspace network policy '
          'enables it with a provider. Results are labelled as web text, '
          'never as trusted facts.',
      risk: ToolRiskLevel.sensitive,
      timeout: Duration(seconds: 20),
      parameters: [
        ToolParameter(
          name: 'query',
          type: ToolParameterType.string,
          description: 'Words to search the web for.',
          maxLength: 200,
        ),
      ],
    ),
    handler: (arguments) async {
      final policy = policyForActiveWorkspace();
      if (!policy.allowsWebSearch) {
        return 'Web search is off or unconfigured in this workspace. The user '
            'can enable it with a provider in the workspace network settings; '
            'until then nothing is searched.';
      }
      final query = arguments['query'] as String;
      final snippets = await search(query);
      if (snippets.isEmpty) {
        return 'No web results for "$query" through ${policy.webSearchProvider}.';
      }
      final buffer = StringBuffer()
        ..writeln(
          snippets.length == 1
              ? '1 web result for "$query" (web text, not trusted facts):'
              : '${snippets.length} web results for "$query" (web text, not trusted facts):',
        );
      for (var index = 0; index < snippets.length; index++) {
        buffer
          ..writeln('[${index + 1}] ${snippets[index].label}')
          ..writeln(snippets[index].text);
      }
      return buffer.toString().trimRight();
    },
  );
}
