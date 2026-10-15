import 'package:flutter/material.dart';
import 'package:installm/core/widgets/composer_command_picker.dart';
import 'package:installm/core/theme/appearance_surfaces.dart';
import 'package:installm/features/home/presentation/composer_shortcuts.dart';

/// What the composer's mic is doing.
///
/// The mic stays a control for as long as voice is open, and only becomes a
/// spinner for work the user cannot end by tapping.
enum ComposerMicState {
  /// Nothing is being dictated: tapping the mic opens it.
  idle,

  /// Listening or recording: tapping the mic finishes the turn.
  active,

  /// A clip is being turned into words: there is nothing to press.
  transcribing,
}

/// The app's one composer card: borderless expanding field on top, one
/// action row at the bottom. Home and room chats share it so the two can
/// never drift apart again.
///
/// Slots keep each surface's extras: [header] is home's generating row and
/// draft-image preview, [leading] its model pill, [middle] its attach
/// button. A room passes none of those and gets the same field, mic and send
/// controls. [onMicPressed] null hides the mic — rooms had nowhere to send
/// a clip until inline transcription landed, so they hid it first.
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.enabled,
    required this.hintText,
    required this.onSend,
    this.sendsOnEnter = true,
    this.header,
    this.leading,
    this.reasoning,
    this.middle,
    this.onMicPressed,
    this.micState = ComposerMicState.idle,
    this.focusNode,
    this.onKeyEvent,
    this.commands = const [],
    this.additionalQuery,
  });

  /// Text being composed; owned by the hosting page.
  final TextEditingController controller;

  /// False while generating or with no model: field locks, buttons disable.
  final bool enabled;

  /// Idle prompt inside the empty field.
  final String hintText;

  /// Sends [controller]'s text.
  final Future<void> Function() onSend;

  /// Desktop Return-to-send behavior; mobile keeps its own send action.
  final bool sendsOnEnter;

  /// Extra rows above the field (home's generating row, draft preview).
  final Widget? header;

  /// First action in the bottom row (home's model pill).
  final Widget? leading;

  /// The reasoning chip, drawn beside [leading] and telling its own margins: it
  /// draws nothing at all for a model that declares no reasoning, and the row
  /// must not carry a gap for a control that is not there.
  final Widget? reasoning;

  /// Right-aligned action next to mic/send (home's attach button).
  final Widget? middle;

  /// Inline voice input. Null hides the mic button.
  final VoidCallback? onMicPressed;

  /// What the mic shows; see [ComposerMicState].
  final ComposerMicState micState;

  final List<ComposerCommand> commands;
  final ComposerCommandQuery? Function(TextEditingValue)? additionalQuery;
  final FocusNode? focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;

  @override
  Widget build(BuildContext context) {
    return ComposerCommandPicker(
      controller: controller,
      enabled: enabled,
      commands: commands,
      additionalQuery: additionalQuery,
      focusNode: focusNode,
      onKeyEvent: onKeyEvent,
      onSend: onSend,
      builder: (focus, keyHandler, submit) =>
          _buildPanel(context, focus, keyHandler, submit),
    );
  }

  Widget _buildPanel(
    BuildContext context,
    FocusNode focus,
    KeyEventResult Function(FocusNode, KeyEvent) keyHandler,
    Future<void> Function() submit,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final micHandler = onMicPressed;
    return FrostedPanel(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: appearanceSurfaceColor(
            context,
            colorScheme.surfaceContainerHigh,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (header case final Widget widget) widget,
            // Desktop: Return sends, Shift+Return adds a line. Mobile
            // keyboards keep their own send action and Return as a line
            // break, which is what the shortcut wrapper checks. No Expanded
            // here: this column shrink-wraps, so the field sizes itself.
            ComposerSendOnEnter(
              sendsOnEnter: enabled && sendsOnEnter,
              onSend: submit,
              child: Focus(
                onKeyEvent: keyHandler,
                child: TextField(
                  focusNode: focus,
                  controller: controller,
                  enabled: enabled,
                  readOnly: !enabled,
                  maxLines: 5,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: hintText,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                  ),
                  onSubmitted: enabled ? (_) => submit() : null,
                  onTapOutside: (_) => focus.unfocus(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  if (leading case final Widget widget) widget,
                  if (reasoning case final Widget widget) widget,
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: middle ?? const SizedBox(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (micHandler != null)
                    SizedBox.square(
                      dimension: 40,
                      child: switch (micState) {
                        // Only work the user cannot finish by tapping hides the
                        // control; listening and recording keep a tappable mic,
                        // because the tap is what ends them.
                        ComposerMicState.transcribing => const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        ComposerMicState.active => IconButton.filledTonal(
                          tooltip: 'Finish dictation',
                          onPressed: enabled ? micHandler : null,
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.mic_rounded, size: 20),
                        ),
                        ComposerMicState.idle => IconButton(
                          tooltip: 'Voice input',
                          onPressed: enabled ? micHandler : null,
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.mic_none_rounded, size: 20),
                        ),
                      },
                    ),
                  if (micHandler != null) const SizedBox(width: 4),
                  SizedBox.square(
                    dimension: 40,
                    child: IconButton.filled(
                      tooltip: 'Send',
                      onPressed: enabled ? onSend : null,
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
