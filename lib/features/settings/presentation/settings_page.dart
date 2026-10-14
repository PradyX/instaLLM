import 'package:flutter/material.dart';
import 'package:installm/i18n/strings.g.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/core/settings/attachment_settings_provider.dart';
import 'package:installm/core/services/attachment_image_service.dart';
import 'package:installm/features/settings/presentation/appearance_settings_section.dart';
import 'package:installm/features/context/application/context_budget_controller.dart';
import 'package:installm/features/conversations/domain/context_policy.dart'
    show formatTokens;
import 'package:installm/features/inference_profiles/application/inference_profiles_controller.dart';
import 'package:installm/features/personas/application/personas_controller.dart';
import 'package:installm/features/voice/presentation/voice_settings_section.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachmentSettings = ref.watch(attachmentSettingsProvider);
    final defaultPersonaName = ref.watch(personasProvider).defaultPersona.name;
    final activeProfileName = ref
        .watch(inferenceProfilesProvider)
        .activeProfile
        .name;
    final contextBudget = ref.watch(contextBudgetProvider).budget;
    final contextCap = contextBudget.windowCap;
    final contextBudgetSummary = contextCap == null
        ? 'Automatic'
        : 'Limited to ${formatTokens(contextCap)} tokens';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Appearance',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          const AppearanceSettingsSection(),
          const SizedBox(height: 24),
          Text(
            'Chat',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.face_retouching_natural),
                  title: const Text('Personas'),
                  subtitle: Text('Default: $defaultPersonaName'),
                  onTap: () => context.push(AppRoutes.personas),
                ),
                ListTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('Inference Profiles'),
                  subtitle: Text('Active: $activeProfileName'),
                  onTap: () => context.push(AppRoutes.inferenceProfiles),
                ),
                ListTile(
                  leading: const Icon(Icons.pie_chart_outline),
                  title: const Text('Context'),
                  subtitle: Text('Budget: $contextBudgetSummary'),
                  onTap: () => context.push(AppRoutes.contextBudget),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_copy_outlined),
                  title: const Text('Workspaces'),
                  subtitle: const Text(
                    'Projects linking bots, chats, skills and boards',
                  ),
                  onTap: () => context.push(AppRoutes.workspaces),
                ),
                ListTile(
                  leading: const Icon(Icons.extension_outlined),
                  title: const Text('Skills'),
                  subtitle: const Text('Reusable procedures bots can follow'),
                  onTap: () => context.push(AppRoutes.skills),
                ),
                ListTile(
                  leading: const Icon(Icons.hub_outlined),
                  title: const Text('MCP servers'),
                  subtitle: const Text('External tools bots can use'),
                  onTap: () => context.push(AppRoutes.mcp),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('Vault'),
                  subtitle: const Text('Human-readable project knowledge'),
                  onTap: () => context.push(AppRoutes.vaults),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Voice',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          const VoiceSettingsSection(),
          const SizedBox(height: 24),
          Text(
            'Data',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('Backup and restore'),
                  subtitle: const Text(
                    'Save chats, personas, profiles, settings and benchmarks '
                    'to one file',
                  ),
                  onTap: () => context.push(AppRoutes.backup),
                ),
              ],
            ),
          ),
          // The prebuilt global "LLM Inference" controls (adaptive mode, sampling
          // preset, max output tokens, advanced sampling override) are hidden for
          // now while Inference Profiles own per-chat sampling. Their providers are
          // untouched and still drive the chat runtime.
          const SizedBox(height: 24),
          Text(
            'Images',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Optimize Images Before Sending'),
                  subtitle: const Text(
                    'Downscales large photos and re-encodes them to a size a '
                    'local model can afford. Re-encoding also removes their '
                    'metadata.',
                  ),
                  value: attachmentSettings.optimizeImages,
                  onChanged: (value) {
                    ref
                        .read(attachmentSettingsProvider.notifier)
                        .setOptimizeImages(value);
                  },
                ),
                if (attachmentSettings.optimizeImages)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        const Expanded(child: Text('Longest edge')),
                        DropdownButton<int>(
                          value: attachmentSettings.maxImageEdge,
                          onChanged: (value) {
                            if (value == null) return;
                            ref
                                .read(attachmentSettingsProvider.notifier)
                                .setMaxImageEdge(value);
                          },
                          items: [
                            for (final edge in _maxEdgeOptions(
                              attachmentSettings.maxImageEdge,
                            ))
                              DropdownMenuItem(
                                value: edge,
                                child: Text('$edge px'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                SwitchListTile(
                  title: const Text('Remove Image Metadata'),
                  subtitle: Text(
                    attachmentSettings.optimizeImages
                        ? 'Optimizing already stores images without EXIF/GPS.'
                        : 'Re-encodes images without EXIF/GPS before they are '
                              'stored.',
                  ),
                  // Optimizing implies a re-encode, so the switch reports what
                  // really happens and only the re-encode-only path can change
                  // it.
                  value:
                      attachmentSettings.optimizeImages ||
                      attachmentSettings.stripMetadata,
                  onChanged: attachmentSettings.optimizeImages
                      ? null
                      : (value) {
                          ref
                              .read(attachmentSettingsProvider.notifier)
                              .setStripMetadata(value);
                        },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text(t.navigation.about),
                  onTap: () => context.push(AppRoutes.about),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Max-edge choices, keeping any stored value selectable.
  static List<int> _maxEdgeOptions(int current) {
    const options = [768, 1280, 1600, AttachmentImageOptions.maxMaxEdge];
    if (options.contains(current)) return options;
    return [...options, current]..sort();
  }
}
