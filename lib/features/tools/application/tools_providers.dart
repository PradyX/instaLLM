import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/services/service_providers.dart';
import 'package:installm/features/agents/application/hooks_controller.dart';
import 'package:installm/features/conversations/presentation/conversation_controller.dart';
import 'package:installm/features/documents/application/documents_controller.dart';
import 'package:installm/features/documents/application/network_policy_controller.dart';
import 'package:installm/features/documents/data/duckduckgo_search.dart';
import 'package:installm/features/documents/data/web_fetch_service.dart';
import 'package:installm/features/workspaces/application/workspaces_controller.dart';
import 'package:installm/features/documents/domain/network_policy.dart';
import 'package:installm/features/kanban/application/kanban_controller.dart'
    show activeWorkspaceIdProvider;
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:installm/features/tools/application/built_in_tools.dart';
import 'package:installm/features/tools/application/tool_approval_controller.dart';
import 'package:installm/features/tools/application/tool_registry.dart';
import 'package:installm/features/tools/data/conversation_search_tool.dart';
import 'package:installm/features/tools/data/document_search_tool.dart';
import 'package:installm/features/tools/data/installed_models_tool.dart';
import 'package:installm/features/connections/application/connectors_controller.dart';
import 'package:installm/features/tools/data/local_context_tools.dart';
import 'package:installm/features/tools/data/read_document_tool.dart';
import 'package:installm/features/tools/data/web_tools.dart';
import 'package:installm/features/tools/domain/tool_definition.dart';

/// Web results for one query through the workspace's provider plus key.
///
/// No built-in backend: the key lives in secure storage and the provider is
/// named by the policy file. Unknown providers answer empty rather than
/// guessing an endpoint.
Future<List<WebSnippet>> searchWebWithProvider({
  required String provider,
  required String apiKey,
  required String query,
  Dio? dio,
}) async {
  final client = dio ?? Dio();
  final now = DateTime.now();
  final normalized = provider.trim().toLowerCase();
  try {
    if (normalized == 'tavily') {
      final response = await client.post(
        'https://api.tavily.com/search',
        data: {'api_key': apiKey, 'query': query, 'max_results': 5},
        options: Options(
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final data = response.data;
      if (data is! Map) return const [];
      final results = data['results'];
      if (results is! List) return const [];
      return [
            for (final entry in results.take(5))
              if (entry is Map)
                WebSnippet(
                  url: (entry['url'] ?? '').toString(),
                  fetchedAt: now,
                  text: (entry['content'] ?? entry['snippet'] ?? '').toString(),
                  title: (entry['title'] ?? '').toString(),
                  provider: 'tavily',
                ),
          ]
          .where(
            (snippet) =>
                snippet.url.isNotEmpty && snippet.text.trim().isNotEmpty,
          )
          .toList(growable: false);
    }
    if (normalized == 'brave') {
      final response = await client.get(
        'https://api.search.brave.com/res/v1/web/search',
        queryParameters: {'q': query, 'count': 5},
        options: Options(
          headers: {
            'X-Subscription-Token': apiKey,
            'Accept': 'application/json',
          },
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final data = response.data;
      if (data is! Map) return const [];
      final web = (data['web'] is Map) ? data['web']['results'] : null;
      if (web is! List) return const [];
      return [
            for (final entry in web.take(5))
              if (entry is Map)
                WebSnippet(
                  url: (entry['url'] ?? '').toString(),
                  fetchedAt: now,
                  text: (entry['description'] ?? entry['snippet'] ?? '')
                      .toString(),
                  title: (entry['title'] ?? '').toString(),
                  provider: 'brave',
                ),
          ]
          .where(
            (snippet) =>
                snippet.url.isNotEmpty && snippet.text.trim().isNotEmpty,
          )
          .toList(growable: false);
    }
    return const [];
  } catch (_) {
    return const [];
  }
}

/// The registry every tool call in the app goes through.
///
/// Built for the current platform once, so a tool declared for another platform
/// is never advertised or run here. Read-only tools read the same local data
/// the screens show — chat history, the active knowledge collection and
/// installed models — and never change it. Sensitive tools (web fetching and
/// the Android actions) run only after the user answers the approval prompt.
///
/// What one search attempt produced, and why when it produced nothing.
///
/// `error` is only set when the request itself failed; an empty list with no
/// error means the engine answered and had no results. The research loop turns
/// those two into different, honest sentences.
class WebSearchOutcome {
  const WebSearchOutcome({this.snippets = const [], this.error});

  final List<WebSnippet> snippets;
  final String? error;
}

typedef WebSearchRunner = Future<WebSearchOutcome> Function(String query);

/// One search, through the workspace policy and the configured provider.
///
/// This is the single seam both the `web_search` tool and the chat's research
/// step call (Road Map 5 Phase 5.5): the tool cannot reach a provider the
/// policy refuses, and the research step cannot either. `duckduckgo` needs no
/// key; `tavily` and `brave` read theirs from secure storage.
Future<WebSearchOutcome> runWebSearch(Ref ref, String query) async {
  final policy = await resolveNetworkPolicyForActiveWorkspace(ref);
  if (policy == null || !policy.allowsWebSearch) {
    return const WebSearchOutcome();
  }
  final workspaceId = ref.read(activeWorkspaceIdProvider)!;
  final provider = policy.webSearchProvider.trim().toLowerCase();
  if (provider == 'duckduckgo') {
    final result = await KeylessWebSearch().search(query);
    return WebSearchOutcome(snippets: result.snippets, error: result.error);
  }
  final key = await ref
      .read(networkPolicyControllerProvider.notifier)
      .readSearchKey(
        workspaceId: workspaceId,
        provider: policy.webSearchProvider,
      );
  if (key == null || key.trim().isEmpty) {
    return WebSearchOutcome(
      error: 'no API key is stored for "$provider" in this workspace',
    );
  }
  final service = WebFetchService(
    searchBackend: (q) => searchWebWithProvider(
      provider: policy.webSearchProvider,
      apiKey: key,
      query: q,
    ),
  );
  return WebSearchOutcome(snippets: await service.search(query, policy));
}

/// The network policy in force for the active workspace, or null when there is
/// no workspace to scope it to.
///
/// A plain `read` of the workspaces and policy controllers answers with their
/// empty first build when nothing else is watching them, which is exactly the
/// state that produced a false "web search is off" on the device (the turn ran
/// before either file had been read). This waits for both loads instead, and
/// falls back to reading the policy file directly when the controller has not
/// been opened yet.
Future<NetworkPolicy?> resolveNetworkPolicyForActiveWorkspace(Ref ref) async {
  final workspaces = ref.read(workspacesProvider);
  if (!workspaces.isReady) {
    try {
      await ref.read(workspacesProvider.notifier).whenReady;
    } catch (_) {
      return null;
    }
  }
  final workspaceId = ref.read(activeWorkspaceIdProvider);
  if (workspaceId == null || workspaceId.trim().isEmpty) return null;
  try {
    final state = ref.read(networkPolicyControllerProvider);
    if (state.isOpen) return state.snapshot.forWorkspace(workspaceId);
    final store = await ref.read(networkPolicyStoreProvider.future);
    return store.load().forWorkspace(workspaceId);
  } catch (_) {
    return null;
  }
}

/// The seam the chat turn reads, so both surfaces share one policy check.
final webSearchRunnerProvider = Provider<WebSearchRunner>(
  (ref) =>
      (query) => runWebSearch(ref, query),
);

/// The user's hooks and the workspace network policy are read here too, so
/// every surface that runs a tool — chat, rooms and agent runs — obeys the
/// same rules.
final toolRegistryProvider = Provider<ToolRegistry>((ref) {
  final base = buildToolRegistry(
    platform: currentToolPlatform(),
    permissionGate: ChatToolPermissionGate(
      ref.read(toolApprovalControllerProvider.notifier),
    ),
    hooks: ref.watch(hooksProvider).policy,
    androidActions: (toolName, arguments) => ref
        .read(androidToolExecutorServiceProvider)
        .executeAction(toolName: toolName, arguments: arguments),
    conversationHistorySearch: (query, limit) => searchConversationHistory(
      summaries: ref.read(conversationControllerProvider).summaries,
      loadMessages: ref.read(conversationRepositoryProvider).loadMessages,
      query: query,
      limit: limit,
    ),
    installedModels: () => installedModelSummaries(
      ref.read(modelSelectionControllerProvider).models,
    ),
    documentSearch: (query, limit) async {
      final library = await ref.read(documentLibraryProvider.future);
      final collectionId = library.activeCollectionId;
      if (library.chunkCountIn(collectionId) == 0) {
        return const <LocalDocumentMatch>[];
      }
      return searchLocalDocuments(
        retriever: library.retriever,
        query: query,
        collectionId: collectionId,
        limit: limit,
      );
    },
    documentReading: (documentName) async {
      final library = await ref.read(documentLibraryProvider.future);
      return readLocalDocument(
        documents: library.documentsIn(library.activeCollectionId),
        documentName: documentName,
      );
    },
  );
  NetworkPolicy policyForActiveWorkspace() {
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
  }

  return base.extendedWith([
    buildFetchUrlTool(
      policyForActiveWorkspace: policyForActiveWorkspace,
      fetch: (url) =>
          WebFetchService().fetchUrl(url, policyForActiveWorkspace()),
    ),
    buildCalendarTool(
      icsPaths: () {
        try {
          return ref.read(connectorsProvider).calendar.icsPaths;
        } catch (_) {
          return const [];
        }
      },
    ),
    buildInboxTool(
      mboxPaths: () {
        try {
          return ref.read(connectorsProvider).email.mboxPaths;
        } catch (_) {
          return const [];
        }
      },
    ),
    buildWebSearchTool(
      policyForActiveWorkspace: policyForActiveWorkspace,
      search: (query) async =>
          (await ref.read(webSearchRunnerProvider)(query)).snippets,
    ),
  ]);
});
