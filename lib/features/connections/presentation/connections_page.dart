import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/connections/application/connectors_controller.dart';

/// Settings › Connections: calendar and inbox, read-only first.
///
/// ICS/mbox files are picked locally; CalDAV/IMAP configuration names the
/// server while passwords live in secure storage and never in the config file.
class ConnectionsPage extends ConsumerWidget {
  const ConnectionsPage({super.key});

  Future<void> _pickIcs(WidgetRef ref) async {
    final picked = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(label: 'Calendar', extensions: ['ics']),
      ],
    );
    if (picked.isEmpty) return;
    await ref.read(connectorsProvider.notifier).addIcsPath(picked.first.path);
  }

  Future<void> _pickMbox(WidgetRef ref) async {
    final picked = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(label: 'Mailbox', extensions: ['mbox', 'mbox toys']),
      ],
    );
    if (picked.isEmpty) return;
    await ref.read(connectorsProvider.notifier).addMboxPath(picked.first.path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectorsProvider);
    final notifier = ref.read(connectorsProvider.notifier);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Connections')),
      body: !state.isOpen
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Text('Calendars', style: textTheme.titleSmall),
                for (final path in state.calendar.icsPaths)
                  ListTile(
                    dense: true,
                    title: Text(path, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => notifier.removeIcsPath(path),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => _pickIcs(ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Add ICS file'),
                ),
                const SizedBox(height: 12),
                Text('Inbox (local mbox)', style: textTheme.titleSmall),
                for (final path in state.email.mboxPaths)
                  ListTile(
                    dense: true,
                    title: Text(path, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => notifier.removeMboxPath(path),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => _pickMbox(ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Add mbox file'),
                ),
                const SizedBox(height: 12),
                Text(
                  'IMAP and CalDAV servers are configured here without storing passwords in the config file; passwords stay in secure storage.',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}
