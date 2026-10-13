import 'package:installm/features/benchmark/presentation/benchmark_screen.dart';
import 'package:installm/features/context/presentation/context_budget_page.dart';
import 'package:installm/features/conversations/presentation/conversations_page.dart';
import 'package:installm/features/home/presentation/home_page.dart';
import 'package:installm/features/inference_profiles/presentation/inference_profiles_page.dart';
import 'package:installm/features/model_selection/presentation/model_details_page.dart';
import 'package:installm/features/model_selection/presentation/model_selection_page.dart';
import 'package:installm/features/personas/presentation/personas_page.dart';
import 'package:installm/features/settings/presentation/settings_page.dart';
import 'package:installm/features/voice/presentation/voice_conversation_page.dart';
import 'package:installm/features/about/presentation/about_page.dart';
import 'package:installm/features/workspaces/presentation/workspace_detail_page.dart';
import 'package:installm/features/kanban/presentation/kanban_page.dart';
import 'package:installm/features/obsidian/presentation/vaults_page.dart';
import 'package:installm/features/mcp/presentation/mcp_page.dart';
import 'package:installm/features/skills/presentation/skills_page.dart';
import 'package:installm/features/workspaces/presentation/workspaces_page.dart';
import 'package:installm/features/backup/presentation/backup_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

/// Route path constants for type-safe navigation.
abstract class AppRoutes {
  static const home = '/';
  static const settings = '/settings';
  static const modelSelection = '/model-selection';
  static const benchmark = '/benchmark';
  static const about = '/about';
  static const conversations = '/conversations';
  static const inferenceProfiles = '/inference-profiles';
  static const contextBudget = '/context-budget';
  static const personas = '/personas';
  static const voiceConversation = '/voice/conversation';
  static const workspaces = '/workspaces';
  static const skills = '/skills';
  static const mcp = '/mcp';
  static const vaults = '/vaults';
  static const kanban = '/kanban';
  static const workspace = '/workspace';

  /// Route to one workspace's detail screen.
  static String workspaceFor(String workspaceId) {
    return '$workspace?id=${Uri.encodeQueryComponent(workspaceId)}';
  }

  static const backup = '/backup';
  static const modelDetails = '/model-details';

  /// Route to the GGUF metadata inspector for [modelId].
  static String modelDetailsFor(String modelId) {
    return '$modelDetails?id=${Uri.encodeQueryComponent(modelId)}';
  }
}

@riverpod
GoRouter appRouter(Ref ref) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: AppRoutes.conversations,
        builder: (context, state) => const ConversationsPage(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: AppRoutes.backup,
        builder: (context, state) => const BackupPage(),
      ),
      GoRoute(
        path: AppRoutes.modelSelection,
        builder: (context, state) => const ModelSelectionPage(),
      ),
      GoRoute(
        path: AppRoutes.modelDetails,
        builder: (context, state) =>
            ModelDetailsPage(modelId: state.uri.queryParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.benchmark,
        builder: (context, state) => const BenchmarkScreen(),
      ),
      GoRoute(
        path: AppRoutes.inferenceProfiles,
        builder: (context, state) => const InferenceProfilesPage(),
      ),
      GoRoute(
        path: AppRoutes.personas,
        builder: (context, state) => const PersonasPage(),
      ),
      GoRoute(
        path: AppRoutes.contextBudget,
        builder: (context, state) => const ContextBudgetPage(),
      ),
      GoRoute(
        path: AppRoutes.voiceConversation,
        builder: (context, state) => const VoiceConversationPage(),
      ),
      GoRoute(
        path: AppRoutes.about,
        builder: (context, state) => const AboutPage(),
      ),
      GoRoute(
        path: AppRoutes.workspaces,
        builder: (context, state) => const WorkspacesPage(),
      ),
      GoRoute(
        path: AppRoutes.skills,
        builder: (context, state) => const SkillsPage(),
      ),
      GoRoute(
        path: AppRoutes.mcp,
        builder: (context, state) => const McpPage(),
      ),

      GoRoute(
        path: AppRoutes.vaults,
        builder: (context, state) => const VaultsPage(),
      ),
      GoRoute(
        path: AppRoutes.kanban,
        builder: (context, state) => const KanbanPage(),
      ),

      GoRoute(
        path: AppRoutes.workspace,
        builder: (context, state) => WorkspaceDetailPage(
          workspaceId: state.uri.queryParameters['id'] ?? '',
        ),
      ),
    ],
  );
}
