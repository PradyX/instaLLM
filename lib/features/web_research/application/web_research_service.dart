import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/documents/application/network_policy_controller.dart';
import 'package:installm/features/documents/data/web_fetch_service.dart';
import 'package:installm/features/documents/domain/network_policy.dart';
import 'package:installm/features/kanban/application/kanban_controller.dart'
    show activeWorkspaceIdProvider;
import 'package:installm/features/tools/application/tools_providers.dart';
import 'package:installm/features/web_research/domain/web_research.dart';

/// Result of one research attempt: the pages, or why there are none.
class WebResearchResult {
  const WebResearchResult.ok(WebResearch this.research) : failure = null;
  const WebResearchResult.failed(WebResearchFailure this.failure)
    : research = null;

  final WebResearch? research;
  final WebResearchFailure? failure;

  bool get isOk => research != null;
}

/// The network policy the research step obeys, in the active workspace.
///
/// Separated from the controller so the loop can be exercised without a policy
/// file, a workspace or a device — the production provider still reads exactly
/// the policy the `web_search` and `fetch_url` tools read.
final webResearchPolicyProvider = Provider<NetworkPolicy>((ref) {
  final workspaceId = ref.read(activeWorkspaceIdProvider);
  if (workspaceId == null) return NetworkPolicy.closed;
  try {
    return ref
        .read(networkPolicyControllerProvider)
        .snapshot
        .forWorkspace(workspaceId);
  } catch (_) {
    return NetworkPolicy.closed;
  }
});

final webResearchServiceProvider = Provider<WebResearchService>(
  (ref) => WebResearchService(
    policy: () => ref.read(webResearchPolicyProvider),
    search: ref.read(webSearchRunnerProvider),
  ),
);

/// The turn's web research: search, then read the candidate pages inside a
/// fixed budget (Road Map 5 Phase 5.5).
///
/// Both steps go through the seam the tools use — `webSearchRunnerProvider`,
/// which is the same closure the `web_search` tool calls, and `WebFetchService`
/// with the same `NetworkPolicy` the `fetch_url` tool checks — so the loop
/// cannot bypass the workspace switch, the hooks or the tool's refusal rules.
/// No background fetch and no prefetch: this runs once, for the question that
/// asked for it.
class WebResearchService {
  WebResearchService({
    required NetworkPolicy Function() policy,
    required WebSearchRunner search,
    WebFetchService? fetcher,
  }) : _policy = policy,
       _search = search,
       _fetcher = fetcher ?? WebFetchService();

  final NetworkPolicy Function() _policy;
  final WebSearchRunner _search;
  final WebFetchService _fetcher;

  /// Pages read per turn. Three is enough to answer a question and small enough
  /// that one turn cannot drain a phone's context window.
  static const int maxPages = 3;

  /// Characters of each page kept for the prompt.
  static const int maxExcerptCharacters = 1500;

  Future<WebResearchResult> research(String question) async {
    final policy = _policy();
    if (!policy.allowsWebSearch) {
      return const WebResearchResult.failed(
        WebResearchFailure(
          WebResearchFailureKind.refused,
          'Web search is off in this workspace, so I did not search. Turn it '
          'on in Settings › Network for this workspace and ask again.',
        ),
      );
    }

    final outcome = await _search(question);
    if (outcome.error != null) {
      return WebResearchResult.failed(
        WebResearchFailure(
          WebResearchFailureKind.unreachable,
          'I could not reach a search service: ${outcome.error}. Nothing was '
          'guessed, and this answer has no sources because none were read.',
        ),
      );
    }
    if (outcome.snippets.isEmpty) {
      return WebResearchResult.failed(
        WebResearchFailure(
          WebResearchFailureKind.noResults,
          'The search for "$question" returned no results, so I have nothing '
          'to cite. I did not invent one.',
        ),
      );
    }

    final sources = <WebSource>[];
    for (final snippet in outcome.snippets.take(maxPages)) {
      if (snippet.url.trim().isEmpty) continue;
      WebSnippet? page;
      if (policy.allowsFetchUrl) {
        page = await _fetcher.fetchUrl(snippet.url, policy);
      }
      final text = (page?.text ?? snippet.text).trim();
      sources.add(
        WebSource(
          marker: sources.length + 1,
          url: page?.url ?? snippet.url,
          title: (page?.title ?? snippet.title).trim(),
          fetchedAt: page?.fetchedAt ?? snippet.fetchedAt,
          excerpt: _cap(text),
        ),
      );
    }

    if (sources.isEmpty) {
      return const WebResearchResult.failed(
        WebResearchFailure(
          WebResearchFailureKind.noResults,
          'The search returned links I could not read, so there is nothing to '
          'cite.',
        ),
      );
    }

    return WebResearchResult.ok(WebResearch(query: question, sources: sources));
  }

  static String _cap(String text) {
    final single = text.trim();
    if (single.length <= maxExcerptCharacters) return single;
    return '${single.substring(0, maxExcerptCharacters)}…';
  }
}
