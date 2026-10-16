import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/features/documents/application/documents_controller.dart';

/// Settings › Knowledge: collections with tuning entry (Road Map 3 Phase 3.4).
///
/// Each collection shows how it answers and opens its tuning screen, where
/// chunking, weights, rerank and full-collection context live alongside the
/// preview inspector that shows why each chunk won.
class KnowledgeCollectionsPage extends ConsumerWidget {
  const KnowledgeCollectionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(documentsProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Knowledge')),
      body: !state.isReady
          ? const Center(child: CircularProgressIndicator())
          : state.collections.isEmpty
          ? const Center(child: Text('No collections yet.'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                for (final collection in state.collections)
                  Card(
                    child: ListTile(
                      title: Text(collection.name),
                      subtitle: Text(
                        '${state.documentCountIn(collection.id)} documents · '
                        '${collection.retrievalLabel}'
                        '${collection.retrieval.rerankEnabled ? ' · rerank' : ''}',
                        style: textTheme.bodySmall,
                      ),
                      trailing: TextButton(
                        onPressed: () => context.push(
                          AppRoutes.collectionTuningFor(collection.id),
                        ),
                        child: const Text('Tune'),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
