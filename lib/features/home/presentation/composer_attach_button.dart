import 'package:flutter/material.dart';

/// The composer's attach button: a circular paperclip that opens the attachment
/// menu.
///
/// The circle is rendered by an [IconButton] kept deliberately
/// non-interactive. A live button as the child of a [PopupMenuButton] wins
/// the gesture arena and silently swallows the tap, so the menu could never
/// open. Here the popup's own ink well owns the tap, while the disabled
/// colours are still set to the enabled ones so the button looks active.
class ComposerAttachButton extends StatelessWidget {
  const ComposerAttachButton({
    super.key,
    required this.enabled,
    required this.canAttachImage,
    required this.hasHistoryImages,
    required this.onPickImage,
    required this.onPickHistory,
    required this.onAttachFiles,
  });

  /// Whether the composer accepts input at all: a model is ready and no
  /// generation is running.
  final bool enabled;

  /// Whether the selected model is a downloaded vision model. Without it the
  /// image rows stay listed but greyed out.
  final bool canAttachImage;

  /// Whether this chat already holds images that can be reused.
  final bool hasHistoryImages;

  final VoidCallback onPickImage;
  final VoidCallback onPickHistory;
  final VoidCallback onAttachFiles;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Attach',
      enabled: enabled,
      // Dark rounded sheet; it opens above the attachment button on its own.
      color: colorScheme.surfaceContainerHigh,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) {
        switch (value) {
          case 'pick':
            onPickImage();
          case 'history':
            onPickHistory();
          case 'files':
            onAttachFiles();
        }
      },
      itemBuilder: (context) => [
        // Images need a downloaded vision model. Those rows keep their plain
        // labels and grey out instead, so the menu looks the same whichever
        // model is selected and the option never has to explain itself.
        PopupMenuItem(
          value: 'pick',
          enabled: canAttachImage,
          child: _menuRow(
            colorScheme,
            enabled: canAttachImage,
            icon: Icons.image_outlined,
            label: 'Upload images',
          ),
        ),
        if (hasHistoryImages)
          PopupMenuItem(
            value: 'history',
            enabled: canAttachImage,
            child: _menuRow(
              colorScheme,
              enabled: canAttachImage,
              icon: Icons.collections_rounded,
              label: 'Images from this chat',
            ),
          ),
        PopupMenuItem(
          value: 'files',
          child: _menuRow(
            colorScheme,
            enabled: true,
            icon: Icons.attach_file_outlined,
            label: 'Attach files or folder',
          ),
        ),
      ],
      child: _CircleAttachButton(enabled: enabled),
    );
  }

  /// Icon + label row. A disabled row greys its icon to match the label,
  /// which [PopupMenuItem] already dims on its own.
  Widget _menuRow(
    ColorScheme colorScheme, {
    required bool enabled,
    required IconData icon,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 19,
          color: enabled
              ? colorScheme.primary
              : colorScheme.onSurface.withValues(alpha: 0.38),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _CircleAttachButton extends StatelessWidget {
  const _CircleAttachButton({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = colorScheme.surfaceContainerLow;
    return SizedBox.square(
      dimension: 40,
      child: IconButton(
        // Non-interactive on purpose: the PopupMenuButton above owns the tap.
        onPressed: null,
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.attach_file_rounded, size: 19),
        style: IconButton.styleFrom(
          backgroundColor: background,
          foregroundColor: colorScheme.primary,
          // Keep the enabled look when the popup itself is enabled.
          disabledBackgroundColor: enabled ? background : null,
          disabledForegroundColor: enabled ? colorScheme.primary : null,
        ),
      ),
    );
  }
}
