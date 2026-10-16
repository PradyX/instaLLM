import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/documents/application/documents_controller.dart';
import 'package:installm/features/documents/domain/document.dart';
import 'package:installm/features/documents/domain/retrieval_tuning.dart';

/// Documents › collection tuning (Road Map 3 Phase 3.4).
///
/// Per-collection chunking, hybrid weights, rerank and full-document context.
/// Ranking-time changes never re-index; chunking changes mark documents for
/// refresh. The preview inspector shows why each chunk won: which channels
/// found it, which weights applied, and any rerank movement.
class CollectionTuningPage extends ConsumerStatefulWidget {
  const CollectionTuningPage({super.key, required this.collectionId});

  final String collectionId;

  @override
  ConsumerState<CollectionTuningPage> createState() =>
      _CollectionTuningPageState();
}

class _CollectionTuningPageState extends ConsumerState<CollectionTuningPage> {
  final _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(documentsProvider);
    final notifier = ref.read(documentsProvider.notifier);
    final collection = state.collections
        .where((entry) => entry.id == widget.collectionId)
        .firstOrNull;
    final textTheme = Theme.of(context).textTheme;

    if (!state.isReady) {
      return Scaffold(
        appBar: AppBar(title: const Text('Collection tuning')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (collection == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Collection tuning')),
        body: const Center(child: Text('This collection no longer exists.')),
      );
    }

    final tuning = collection.retrieval;
    final chunking = collection.chunking;

    return Scaffold(
      appBar: AppBar(title: Text('Tune ${collection.name}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Text('Ranking', style: textTheme.titleSmall),
          const SizedBox(height: 4),
          _WeightRow(
            label: 'Terms weight',
            value: tuning.lexicalWeight,
            onChanged: (value) => notifier.updateRetrievalTuning(
              collection.id,
              tuning.copyWith(lexicalWeight: value),
            ),
          ),
          _WeightRow(
            label: 'Meaning weight',
            value: tuning.vectorWeight,
            onChanged: (value) => notifier.updateRetrievalTuning(
              collection.id,
              tuning.copyWith(vectorWeight: value),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Rerank answers'),
            subtitle: const Text(
              'Local second pass over term coverage and headings',
            ),
            value: tuning.rerankEnabled,
            onChanged: (value) => notifier.updateRetrievalTuning(
              collection.id,
              tuning.copyWith(rerankEnabled: value),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Full collection context'),
            subtitle: const Text(
              'Small collections answer whole instead of top-k',
            ),
            value: tuning.fullDocumentContext,
            onChanged: (value) => notifier.updateRetrievalTuning(
              collection.id,
              tuning.copyWith(fullDocumentContext: value),
            ),
          ),
          const SizedBox(height: 12),
          Text('Slicing (re-indexes on refresh)', style: textTheme.titleSmall),
          _NumberRow(
            label: 'Target tokens',
            value: chunking.targetTokens,
            min: 32,
            max: 4000,
            onChanged: (value) => _updateChunking(
              ref,
              DocumentChunkingConfig(
                targetTokens: value,
                overlapTokens: chunking.overlapTokens,
                maxChunkTokens: chunking.maxChunkTokens,
              ),
            ),
          ),
          _NumberRow(
            label: 'Overlap tokens',
            value: chunking.overlapTokens,
            min: 0,
            max: chunking.targetTokens ~/ 2,
            onChanged: (value) => _updateChunking(
              ref,
              DocumentChunkingConfig(
                targetTokens: chunking.targetTokens,
                overlapTokens: value,
                maxChunkTokens: chunking.maxChunkTokens,
              ),
            ),
          ),
          _NumberRow(
            label: 'Max tokens',
            value: chunking.maxChunkTokens,
            min: chunking.targetTokens,
            max: 8000,
            onChanged: (value) => _updateChunking(
              ref,
              DocumentChunkingConfig(
                targetTokens: chunking.targetTokens,
                overlapTokens: chunking.overlapTokens,
                maxChunkTokens: value,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Preview inspector', style: textTheme.titleSmall),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryController,
                  decoration: const InputDecoration(
                    labelText: 'Try a question',
                    hintText: 'Words to look for',
                  ),
                  onSubmitted: (_) => notifier.search(_queryController.text),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => notifier.search(_queryController.text),
                child: const Text('Preview'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (state.searchQuery.isNotEmpty && state.searchResults.isEmpty)
            Text('No chunks matched.', style: textTheme.bodySmall),
          for (final hit in state.searchResults)
            Card(
              child: ListTile(
                title: Text(hit.citationLabel),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hit.chunk.text.length <= 220
                          ? hit.chunk.text
                          : '${hit.chunk.text.substring(0, 220)}…',
                      style: textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hit.rankDetail.isEmpty ? 'unranked' : hit.rankDetail,
                      style: textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _updateChunking(
    WidgetRef ref,
    DocumentChunkingConfig chunking,
  ) async {
    // Chunking lives on the collection via the library; the notifier owns the
    // write path through updateRetrievalTuning's sibling. Reuse the library
    // through a retrieval update that keeps tuning identical so the preview
    // stays honest while the stored chunking changes.
    final state = ref.read(documentsProvider);
    final collection = state.collections
        .where((entry) => entry.id == widget.collectionId)
        .firstOrNull;
    if (collection == null) return;
    final library = ref.read(documentsProvider.notifier).library;
    if (library == null) return;
    // Direct library write: chunking is index-time, tuning is rank-time.
    library.updateCollectionChunking(collection.id, chunking.normalized());
    await ref
        .read(documentsProvider.notifier)
        .updateRetrievalTuning(collection.id, collection.retrieval);
  }
}

class _WeightRow extends StatelessWidget {
  const _WeightRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        Expanded(
          flex: 2,
          child: Slider(
            min: RetrievalTuning.minWeight,
            max: RetrievalTuning.maxWeight,
            divisions: 8,
            label: value.toStringAsFixed(1),
            value: value.clamp(
              RetrievalTuning.minWeight,
              RetrievalTuning.maxWeight,
            ),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(value.toStringAsFixed(1), textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

class _NumberRow extends StatelessWidget {
  const _NumberRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        DropdownButton<int>(
          value: value.clamp(min, max),
          items: [
            for (final option in _options(min, max, value))
              DropdownMenuItem(value: option, child: Text('$option')),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ],
    );
  }

  static List<int> _options(int min, int max, int current) {
    final base = <int>{min, max, current, (min + max) ~/ 2};
    // Chunking presets the UI offers alongside any stored value.
    base.addAll([64, 150, 300, 600, 1200]);
    return base.where((v) => v >= min && v <= max).toList()..sort();
  }
}
