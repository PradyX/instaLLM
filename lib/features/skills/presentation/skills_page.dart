import 'package:installm/i18n/strings.g.dart';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/skills/application/skills_controller.dart';
import 'package:installm/features/skills/domain/skill.dart';

/// The skill registry: what is installed, what is on, and what each skill
/// may need.
///
/// Road Map 2 Phase 2.2. Installing costs no context: only skills the
/// selector deems relevant to the current task are loaded into a prompt,
// and supporting resources load on demand from there.
class SkillsPage extends ConsumerWidget {
  const SkillsPage({super.key});

  Future<void> _importFile(BuildContext context, WidgetRef ref) async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Skill', extensions: ['md']),
      ],
    );
    if (file == null) return;
    final skill = await ref
        .read(skillsProvider.notifier)
        .importFile(File(file.path));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          skill == null
              ? 'Could not save the skill.'
              : 'Imported ${skill.name}.',
        ),
      ),
    );
  }

  /// Deleting an imported skill destroys its copied bundle, so it asks first.
  /// Removing a built-in only takes it out of the list and can be undone, so
  /// it does not.
  Future<void> _remove(BuildContext context, WidgetRef ref, Skill skill) async {
    if (!skill.isBuiltIn) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete ${skill.name}?'),
          content: const Text(
            'Its instructions and copied resources are removed from this '
            'device. Chats, bots and rooms are untouched.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await ref.read(skillsProvider.notifier).removeSkill(skill.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(skillsProvider);
    final notifier = ref.read(skillsProvider.notifier);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Skills')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _importFile(context, ref),
        icon: const Icon(Icons.upload_file),
        label: const Text('Import SKILL.md'),
      ),
      body: !state.isReady
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Text(
                  'Skills are reusable procedures a bot can follow. Only '
                  'skills relevant to the current task are loaded, so '
                  'installing one costs no context until it is needed.',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (state.skills.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No skills yet. Import a SKILL.md file.'),
                    ),
                  ),
                for (final skill in state.skills)
                  _SkillTile(
                    skill: skill,
                    onToggle: (enabled) =>
                        notifier.setEnabled(skill.id, enabled),
                    onRemove: () => _remove(context, ref, skill),
                  ),
                if (state.removedBuiltInSkills.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Removed built-ins', style: textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'These ship with the app, so removing one only takes it '
                    'out of the list. Restoring puts it back on.',
                    style: textTheme.bodySmall,
                  ),
                  for (final skill in state.removedBuiltInSkills)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.auto_awesome),
                      title: Text(skill.name),
                      trailing: TextButton(
                        onPressed: () => notifier.restoreSkill(skill.id),
                        child: const Text('Restore'),
                      ),
                    ),
                ],
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    state.errorMessage!,
                    style: textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _SkillTile extends StatelessWidget {
  const _SkillTile({
    required this.skill,
    required this.onToggle,
    required this.onRemove,
  });

  final Skill skill;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: ExpansionTile(
        leading: Icon(
          skill.source == SkillSource.builtIn
              ? Icons.auto_awesome
              : Icons.extension_outlined,
        ),
        title: Text(skill.name),
        subtitle: Text(
          skill.description.isEmpty
              ? skill.source.label
              : '${skill.source.label} · ${skill.description}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: skill.enabled, onChanged: onToggle),
            // Red is for deleting a file. A built-in's removal is a reversible
            // list change, so it stays neutral.
            IconButton(
              icon: Icon(
                skill.isBuiltIn
                    ? Icons.remove_circle_outline
                    : Icons.delete_outline,
              ),
              color: skill.isBuiltIn ? null : colorScheme.error,
              tooltip: skill.isBuiltIn ? 'Remove built-in' : 'Delete skill',
              onPressed: onRemove,
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (skill.requiredCapabilities.isNotEmpty)
                  Text(
                    'Needs: ${skill.requiredCapabilities.join(', ')}',
                    style: textTheme.bodySmall,
                  ),
                if (skill.scriptNames.isNotEmpty)
                  Text(
                    t.skills.scriptFiles(names: skill.scriptNames.join(', ')),
                  ),
                if (skill.resourceNames.isNotEmpty)
                  Text(
                    'Resources: ${skill.resourceNames.join(', ')}',
                    style: textTheme.bodySmall,
                  ),
                const SizedBox(height: 8),
                Text(
                  skill.body,
                  style: textTheme.bodySmall,
                  maxLines: 12,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
