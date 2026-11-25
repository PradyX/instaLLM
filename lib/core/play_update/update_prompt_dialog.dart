import 'dart:async';

import 'package:flutter/material.dart';
import 'package:installm/core/app_info.dart';
import 'package:installm/core/play_review/review_prompt.dart';
import 'package:installm/core/play_update/play_update_service.dart';
import 'package:installm/core/play_update/update_prompt.dart';
import 'package:installm/i18n/strings.g.dart';

/// The mockup-A dialog: one quiet card, a short explanation and a single green
/// action, with a dismiss that costs nothing.
Future<void> showUpdatePromptDialog({
  required BuildContext context,
  required PlayUpdateCheck check,
  required UpdatePromptPolicy policy,
  PlayUpdateService service = const PlayUpdateService(),
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) =>
        UpdatePromptDialog(check: check, policy: policy, service: service),
  );
}

class UpdatePromptDialog extends StatefulWidget {
  const UpdatePromptDialog({
    super.key,
    required this.check,
    required this.policy,
    this.service = const PlayUpdateService(),
  });

  final PlayUpdateCheck check;
  final UpdatePromptPolicy policy;
  final PlayUpdateService service;

  @override
  State<UpdatePromptDialog> createState() => _UpdatePromptDialogState();
}

class _UpdatePromptDialogState extends State<UpdatePromptDialog> {
  late PlayUpdateStage _stage = widget.check.stage;
  StreamSubscription<PlayUpdateStage>? _download;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    // A download started on an earlier launch (or before the last restart) is
    // still running; follow it instead of asking about the update again.
    if (_stage == PlayUpdateStage.downloading) _followDownload();
  }

  @override
  void dispose() {
    _download?.cancel();
    super.dispose();
  }

  void _followDownload() {
    _download ??= widget.service.installStages.listen(
      (stage) {
        if (!mounted) return;
        setState(() => _stage = stage);
        if (stage == PlayUpdateStage.ready) {
          _download?.cancel();
          _download = null;
        }
      },
      onError: (Object error) {
        // Without Play's events the download may still finish; the next launch
        // asks again rather than leaving a stuck dialog on screen.
        if (!mounted) return;
        setState(() => _stage = PlayUpdateStage.available);
      },
    );
  }

  Future<void> _updateNow() async {
    if (_busy) return;
    setState(() => _busy = true);

    if (!widget.check.canUpdateInApp) {
      // Play allows only its own full-screen flow here (or did not install this
      // build), so hand the user to the listing instead of pretending.
      widget.policy.dismiss(
        availableVersionCode: widget.check.availableVersionCode,
      );
      if (mounted) Navigator.of(context).pop();
      await openPlayStoreListing();
      return;
    }

    final started = await widget.service.startBackgroundDownload();
    if (!mounted) return;
    if (!started) {
      widget.policy.dismiss(
        availableVersionCode: widget.check.availableVersionCode,
      );
      Navigator.of(context).pop();
      await openPlayStoreListing();
      return;
    }
    setState(() {
      _busy = false;
      _stage = PlayUpdateStage.downloading;
    });
    _followDownload();
  }

  Future<void> _restart() async {
    if (_busy) return;
    setState(() => _busy = true);
    final installed = await widget.service.installDownloaded();
    if (!mounted) return;
    if (!installed) {
      // Play refused to apply it; the listing is the one path that still works.
      setState(() => _busy = false);
      Navigator.of(context).pop();
      await openPlayStoreListing();
    }
    // A successful install restarts the app, so nothing after it runs.
  }

  void _dismiss() {
    widget.policy.dismiss(
      availableVersionCode: widget.check.availableVersionCode,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ready = _stage == PlayUpdateStage.ready;
    final downloading = _stage == PlayUpdateStage.downloading;

    return Dialog(
      backgroundColor: colors.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ready ? t.update.readyTitle : t.update.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t.update.meta(version: appVersion),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (downloading) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    backgroundColor: colors.surfaceContainerHighest,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                ready
                    ? t.update.readyBody
                    : downloading
                    ? t.update.downloading
                    : t.update.body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: ready
                    ? [
                        TextButton(
                          onPressed: _busy ? null : _dismiss,
                          child: Text(t.update.later),
                        ),
                        const SizedBox(width: 6),
                        _PrimaryAction(
                          label: t.update.restart,
                          onPressed: _busy ? null : _restart,
                        ),
                      ]
                    : downloading
                    ? [
                        TextButton(
                          onPressed: _dismiss,
                          child: Text(t.update.hide),
                        ),
                      ]
                    : [
                        TextButton(
                          onPressed: _busy ? null : _dismiss,
                          child: Text(t.update.notNow),
                        ),
                        const SizedBox(width: 6),
                        _PrimaryAction(
                          label: t.update.updateNow,
                          onPressed: _busy ? null : _updateNow,
                        ),
                      ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The mockup's single green action: soft fill, green label, flat corners. A
/// `FilledButton` would draw the store-wide pill, which is louder than this
/// dialog's one ask deserves.
class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: colors.primaryContainer,
        foregroundColor: colors.onPrimaryContainer,
        disabledBackgroundColor: colors.surfaceContainerHighest,
        disabledForegroundColor: colors.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      child: Text(label),
    );
  }
}
