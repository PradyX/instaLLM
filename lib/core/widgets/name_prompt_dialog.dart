import 'package:flutter/material.dart';

/// A one-field name prompt ("New group chat", "New bot", ...).
///
/// The [TextEditingController] lives and dies with the dialog route on
/// purpose: creating it next to `showDialog` and disposing it when the
/// dialog future completes crashes the app, because the route stays mounted
/// through its pop exit animation and the next rebuild re-attaches the
/// field to the disposed controller ("used after being disposed"). Owning
/// the controller here ties disposal to route removal, after the animation
/// is gone.
class NamePromptDialog extends StatefulWidget {
  const NamePromptDialog({
    super.key,
    required this.title,
    required this.hintText,
    required this.confirmLabel,
  });

  final String title;
  final String hintText;
  final String confirmLabel;

  /// Shows the dialog and returns the raw entered name, or null on cancel.
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String hintText,
    required String confirmLabel,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => NamePromptDialog(
        title: title,
        hintText: hintText,
        confirmLabel: confirmLabel,
      ),
    );
  }

  @override
  State<NamePromptDialog> createState() => _NamePromptDialogState();
}

class _NamePromptDialogState extends State<NamePromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(hintText: widget.hintText),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
