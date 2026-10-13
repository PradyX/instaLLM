import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/settings/voice_settings_provider.dart';
import 'package:installm/features/voice/application/whisper_models_controller.dart';
import 'package:installm/features/voice/domain/whisper_model_option.dart';

/// Opens the Whisper model picker: what can be downloaded, and what is here.
Future<void> showWhisperModelPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => const _WhisperModelSheet(),
  );
}

class _WhisperModelSheet extends ConsumerStatefulWidget {
  const _WhisperModelSheet();

  @override
  ConsumerState<_WhisperModelSheet> createState() => _WhisperModelSheetState();
}

class _WhisperModelSheetState extends ConsumerState<_WhisperModelSheet> {
  @override
  void initState() {
    super.initState();
    // Model files can be deleted outside the app while it runs, so the list
    // is re-read when the sheet opens rather than trusted from app start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(whisperModelsProvider.notifier).refresh();
    });
  }

  /// Downloads a model, then selects it when nothing usable is selected yet.
  ///
  /// Selecting on success is what makes the first download enough: the user
  /// picked this model by pressing Download, so having to pick it again in a
  /// second step would be a pointless extra tap.
  Future<void> _download(WhisperModelOption option) async {
    final installed = await ref
        .read(whisperModelsProvider.notifier)
        .download(option);
    if (!mounted || !installed) return;
    final selectedId = ref.read(voiceSettingsProvider).whisperModelId;
    final hasUsableSelection =
        selectedId != null &&
        ref.read(whisperModelsProvider).isInstalled(selectedId);
    if (hasUsableSelection) return;
    await ref.read(voiceSettingsProvider.notifier).setWhisperModel(option.id);
  }

  Future<void> _select(WhisperModelOption option) async {
    await ref.read(voiceSettingsProvider.notifier).setWhisperModel(option.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove(WhisperModelOption option) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${option.name}?'),
        content: Text(
          'The downloaded model file (${option.sizeLabel}) is deleted. '
          'Conversations, and every other model, are untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // A removed model must not stay selected: transcription would keep
    // pointing at a file that is gone.
    final wasSelected =
        ref.read(voiceSettingsProvider).whisperModelId == option.id;
    await ref.read(whisperModelsProvider.notifier).remove(option);
    if (!mounted || !wasSelected) return;
    final remaining = ref.read(whisperModelsProvider).installed;
    await ref
        .read(voiceSettingsProvider.notifier)
        .setWhisperModel(remaining.isEmpty ? null : remaining.first.option.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(whisperModelsProvider);
    final controller = ref.read(whisperModelsProvider.notifier);
    final selectedId = ref.watch(voiceSettingsProvider).whisperModelId;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('Whisper models', style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Downloaded once, then transcribed on this device by '
                'whisper.cpp. Audio is never uploaded, and each model runs '
                'without the others.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (state.errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final option in WhisperModelCatalog.models)
                    _WhisperModelTile(
                      option: option,
                      installed: state.isInstalled(option.id),
                      selected: selectedId == option.id,
                      downloading: state.downloadingId == option.id,
                      progress: state.progressFor(option.id),
                      onDownload: () => _download(option),
                      onCancel: controller.cancelDownload,
                      onSelect: () => _select(option),
                      onRemove: () => _remove(option),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Removing a model deletes its downloaded file only.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WhisperModelTile extends StatelessWidget {
  const _WhisperModelTile({
    required this.option,
    required this.installed,
    required this.selected,
    required this.downloading,
    required this.progress,
    required this.onDownload,
    required this.onCancel,
    required this.onSelect,
    required this.onRemove,
  });

  final WhisperModelOption option;
  final bool installed;
  final bool selected;
  final bool downloading;
  final double? progress;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onSelect;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: Text(option.name),
          subtitle: Text(
            downloading
                ? 'Downloading ${option.sizeLabel}...'
                : '${option.detail}\n${option.sizeLabel}',
          ),
          isThreeLine: !downloading,
          onTap: downloading ? null : (installed ? onSelect : onDownload),
          trailing: _trailing(theme),
        ),
        if (downloading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LinearProgressIndicator(value: progress),
          ),
      ],
    );
  }

  Widget _trailing(ThemeData theme) {
    if (downloading) {
      return IconButton(
        onPressed: onCancel,
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Cancel download',
      );
    }
    if (!installed) {
      return FilledButton.tonalIcon(
        onPressed: onDownload,
        icon: const Icon(Icons.download_rounded, size: 18),
        label: const Text('Download'),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selected)
          Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
        else
          TextButton(onPressed: onSelect, child: const Text('Use')),
        IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline_rounded),
          tooltip: 'Remove downloaded model',
        ),
      ],
    );
  }
}
