import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/agents/application/hooks_controller.dart';
import 'package:installm/features/agents/domain/agent_hook.dart';

/// Settings › Hooks: the rules that guard agent work (Road Map 3 Phase 3.3.2).
///
/// A hook is a guardrail the user writes down: it refuses a tool call or asks
/// first, and it is always visible — this list, the refusal the model receives
/// and the tool activity of the turn all name the rule that decided. Nothing
/// here can allow what the permission gate refused.
class HooksPage extends ConsumerWidget {
  const HooksPage({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    AgentHook? existing,
  }) async {
    final result = await showDialog<_HookDraft>(
      context: context,
      builder: (context) => _HookDialog(existing: existing),
    );
    if (result == null) return;
    final notifier = ref.read(hooksProvider.notifier);
    if (existing == null) {
      await notifier.addHook(
        name: result.name,
        toolPattern: result.toolPattern,
        resourcePattern: result.resourcePattern,
        level: result.level,
      );
      return;
    }
    await notifier.updateHook(
      existing.copyWith(
        name: result.name,
        toolPattern: result.toolPattern,
        resourcePattern: result.resourcePattern,
        level: result.level,
      ),
    );
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    AgentHook hook,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete the hook “${hook.name}”?'),
        content: const Text(
          'Calls it refuses or questions are allowed as before. Nothing else '
          'changes.',
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
    await ref.read(hooksProvider.notifier).removeHook(hook.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hooksProvider);
    final notifier = ref.read(hooksProvider.notifier);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Hooks')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add rule'),
      ),
      body: !state.isReady
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Text(
                  'Hooks are the rules agent work obeys. A rule refuses a tool '
                  'call or asks you first, so a guardrail is something you can '
                  'read and change — never hidden automation.',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Text('Built in', style: textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'These ship with InstaLLM and are always on. They only ever '
                  'refuse or question a call — never allow one the permission '
                  'gate refused.',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final hook in BuiltInHooks.all)
                  Card(
                    key: ValueKey('builtin-${hook.id}'),
                    child: ListTile(
                      leading: Icon(
                        hook.level == HookLevel.refuse
                            ? Icons.block_outlined
                            : Icons.help_outline,
                      ),
                      title: Text(hook.name),
                      subtitle: Text('${_describe(hook)} · Always on'),
                    ),
                  ),
                const SizedBox(height: 16),
                Text('Your rules', style: textTheme.titleSmall),
                const SizedBox(height: 8),
                if (state.hooks.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No rules of your own yet. Add one to protect a path or '
                        'to be asked before a tool runs.',
                      ),
                    ),
                  ),
                for (final hook in state.hooks)
                  Card(
                    key: ValueKey('hook-${hook.id}'),
                    child: ListTile(
                      leading: Icon(
                        hook.level == HookLevel.refuse
                            ? Icons.block_outlined
                            : Icons.help_outline,
                      ),
                      title: Text(hook.name),
                      subtitle: Text(_describe(hook)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: hook.enabled,
                            onChanged: (enabled) =>
                                notifier.setEnabled(hook.id, enabled),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            color: Theme.of(context).colorScheme.error,
                            tooltip: 'Delete rule',
                            onPressed: () => _remove(context, ref, hook),
                          ),
                        ],
                      ),
                      onTap: () => _edit(context, ref, existing: hook),
                    ),
                  ),
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

  /// `Refuses writes to Projects/** · every tool` — the rule in one line.
  static String _describe(AgentHook hook) {
    final action = hook.level == HookLevel.refuse ? 'Refuses' : 'Asks before';
    final tool = hook.toolPattern == '*'
        ? 'every tool'
        : 'tools matching ${hook.toolPattern}';
    if (!hook.protectsPath) return '$action $tool runs';
    return '$action calls touching ${hook.resourcePattern} · $tool';
  }
}

/// What the dialog returns; the page applies it to the right hook.
class _HookDraft {
  const _HookDraft({
    required this.name,
    required this.toolPattern,
    required this.resourcePattern,
    required this.level,
  });

  final String name;
  final String toolPattern;
  final String resourcePattern;
  final HookLevel level;
}

class _HookDialog extends StatefulWidget {
  const _HookDialog({this.existing});

  final AgentHook? existing;

  @override
  State<_HookDialog> createState() => _HookDialogState();
}

class _HookDialogState extends State<_HookDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _tool = TextEditingController(
    text: widget.existing?.toolPattern ?? '*',
  );
  late final TextEditingController _path = TextEditingController(
    text: widget.existing?.resourcePattern ?? '',
  );
  late HookLevel _level = widget.existing?.level ?? HookLevel.refuse;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _tool.dispose();
    _path.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(
        () => _error = 'Give the rule a name so the list stays readable.',
      );
      return;
    }
    Navigator.of(context).pop(
      _HookDraft(
        name: name,
        toolPattern: _tool.text.trim().isEmpty ? '*' : _tool.text,
        resourcePattern: _path.text,
        level: _level,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add hook' : 'Edit hook'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('hook-name'),
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                helperText: 'Shown in the refusal and in this list.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<HookLevel>(
              segments: const [
                ButtonSegment(
                  value: HookLevel.refuse,
                  label: Text('Refuse'),
                  icon: Icon(Icons.block_outlined),
                ),
                ButtonSegment(
                  value: HookLevel.ask,
                  label: Text('Ask first'),
                  icon: Icon(Icons.help_outline),
                ),
              ],
              selected: {_level},
              onSelectionChanged: (selection) =>
                  setState(() => _level = selection.first),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('hook-path'),
              controller: _path,
              decoration: const InputDecoration(
                labelText: 'Path pattern (optional)',
                helperText:
                    'Applies to the file a tool names, e.g. Projects/** or '
                    '**/*.md. Leave empty for a rule about the tool itself.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('hook-tool'),
              controller: _tool,
              decoration: const InputDecoration(
                labelText: 'Tool',
                helperText:
                    '* for every tool, or a name like vault_write_note.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A rule can only refuse or question a call. It can never allow '
              'something the permission gate refused.',
              style: textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(widget.existing == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
