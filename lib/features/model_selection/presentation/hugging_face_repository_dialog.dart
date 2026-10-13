import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:installm/core/services/hugging_face_repository_service.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:installm/i18n/strings.g.dart';

/// Browses a repository and hands the selected GGUF to the existing downloader.
Future<void> showHuggingFaceRepositoryDialog(
  BuildContext context,
  ModelSelectionController controller,
) async {
  final variant = await showDialog<HuggingFaceModelVariant>(
    context: context,
    builder: (_) => HuggingFaceRepositoryDialog(controller: controller),
  );
  if (variant == null || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('Downloading ${variant.fileName}...'),
    ),
  );
}

/// Own the input until the route is removed, including its exit animation.
class HuggingFaceRepositoryDialog extends StatefulWidget {
  const HuggingFaceRepositoryDialog({
    super.key,
    required this.controller,
    this.repositoryService,
  });

  final ModelSelectionController controller;
  final HuggingFaceRepositoryService? repositoryService;

  @override
  State<HuggingFaceRepositoryDialog> createState() =>
      _HuggingFaceRepositoryDialogState();
}

class _HuggingFaceRepositoryDialogState
    extends State<HuggingFaceRepositoryDialog> {
  final _input = TextEditingController();
  late final _service =
      widget.repositoryService ?? HuggingFaceRepositoryService();
  HuggingFaceRepository? _repository;
  List<HuggingFaceModelVariant> _variants = const [];
  Map<String, bool> _installedByPath = const {};
  HuggingFaceModelVariant? _selected;
  String? _error;
  var _loading = false;
  var _downloading = false;
  var _closing = false;

  bool get _active => mounted && !_closing;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (!_active || _loading || _downloading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = await _service.fetchRepository(_input.text);
      if (!_active) return;
      final parsed = HuggingFaceRepositoryService.variantsFromFiles(repo.files);
      final installed = <String, bool>{};
      for (final variant in parsed) {
        installed[variant.filePath] = await widget.controller
            .isHfVariantInstalled(variant);
        if (!_active) return;
      }
      setState(() {
        _repository = repo;
        _variants = parsed;
        _installedByPath = installed;
        _selected = parsed
            .where((variant) => installed[variant.filePath] != true)
            .firstOrNull;
      });
    } on HuggingFaceRepositoryException catch (error) {
      if (_active) setState(() => _error = error.message);
    } catch (_) {
      if (_active) {
        setState(() => _error = 'Could not read this repository.');
      }
    } finally {
      if (_active) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    final repo = _repository;
    final variant = _selected;
    if (!_active ||
        _loading ||
        _downloading ||
        repo == null ||
        variant == null) {
      return;
    }
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      await widget.controller.addModelFromHuggingFaceRepo(
        repository: repo,
        variant: variant,
      );
      if (!mounted || _closing) return;
      Navigator.of(context).pop(variant);
    } catch (_) {
      if (_active) setState(() => _error = t.modelRepository.addError);
    } finally {
      if (_active) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = _repository;
    return PopScope<HuggingFaceModelVariant>(
      canPop: !_downloading,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _closing = true;
      },
      child: AlertDialog(
        scrollable: true,
        title: const Text('Hugging Face repository'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (repo == null)
                TextField(
                  controller: _input,
                  autofocus: true,
                  enabled: !_loading,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    labelText: 'Repository',
                    hintText: 'author/repository or huggingface.co link',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _fetch(),
                )
              else ...[
                Text(
                  repo.repoId,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                // Viewports cannot provide the intrinsic sizes AlertDialog
                // requests. Bound both dimensions before laying out the list.
                SizedBox(
                  width: double.infinity,
                  height: math.min(
                    320,
                    MediaQuery.sizeOf(context).height * 0.45,
                  ),
                  child: ListView.builder(
                    itemCount: _variants.length,
                    itemBuilder: (context, index) {
                      final variant = _variants[index];
                      final installed =
                          _installedByPath[variant.filePath] == true;
                      return ListTile(
                        dense: true,
                        enabled: !installed && !_downloading,
                        leading: Icon(
                          installed
                              ? Icons.download_done_rounded
                              : _selected == variant
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 20,
                        ),
                        title: Text(
                          '${variant.quantization} · ${variant.fileName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_formatBytes(variant.sizeBytes ?? 0)}'
                          '${variant.projectorPath != null ? ' · vision projector' : ''}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        onTap: installed || _downloading
                            ? null
                            : () => setState(() => _selected = variant),
                      );
                    },
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _downloading ? null : () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (repo != null)
            FilledButton(
              onPressed: _selected == null || _downloading ? null : _download,
              child: const Text('Download'),
            )
          else
            FilledButton(
              onPressed: _loading ? null : _fetch,
              child: _loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Browse'),
            ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
