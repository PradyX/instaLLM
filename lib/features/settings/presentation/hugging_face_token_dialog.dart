import 'dart:async';

import 'package:flutter/material.dart';
import 'package:installm/core/services/hugging_face_auth_service.dart';

/// What the token dialog changed, so the caller can refresh and say so.
enum HuggingFaceTokenChange { none, saved, removed }

/// Opens the editor for the optional Hugging Face token.
///
/// Both the Settings row and the Models "Add a model" sheet use this, so the
/// rules for saving, checking and removing a token live in one place.
Future<HuggingFaceTokenChange> showHuggingFaceTokenDialog(
  BuildContext context, {
  HuggingFaceAuthService? auth,
}) async {
  final change = await showDialog<HuggingFaceTokenChange>(
    context: context,
    builder: (_) =>
        _HuggingFaceTokenDialog(auth: auth ?? HuggingFaceAuthService.instance),
  );
  return change ?? HuggingFaceTokenChange.none;
}

class _HuggingFaceTokenDialog extends StatefulWidget {
  const _HuggingFaceTokenDialog({required this.auth});

  final HuggingFaceAuthService auth;

  @override
  State<_HuggingFaceTokenDialog> createState() =>
      _HuggingFaceTokenDialogState();
}

class _HuggingFaceTokenDialogState extends State<_HuggingFaceTokenDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _saved = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedToken());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadSavedToken() async {
    final token = await widget.auth.token();
    if (!mounted) return;
    setState(() => _saved = token != null);
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.saveToken(_controller.text);
      try {
        await widget.auth.verify();
      } on HuggingFaceTokenException catch (failure) {
        if (failure.rejected) {
          // Do not keep a token Hugging Face just refused.
          await widget.auth.clear();
          if (!mounted) return;
          setState(() {
            _busy = false;
            _saved = false;
            _error = failure.message;
          });
          return;
        }
        // Saved but unchecked: a working setup when the device is offline.
      }
      if (!mounted) return;
      Navigator.of(context).pop(HuggingFaceTokenChange.saved);
    } on HuggingFaceTokenException catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'The token could not be saved.';
      });
    }
  }

  Future<void> _remove() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.clear();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'The token could not be removed.';
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(HuggingFaceTokenChange.removed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Hugging Face token'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A read token raises the anonymous download limit and is kept in '
            'this device\u2019s encrypted storage. It is sent only to '
            'huggingface.co. Create one at huggingface.co/settings/tokens.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Token',
              hintText: 'hf_\u2026',
              errorText: _error,
              errorMaxLines: 3,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => unawaited(_save()),
          ),
        ],
      ),
      actions: [
        if (_saved)
          TextButton(
            onPressed: _busy ? null : () => unawaited(_remove()),
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: _busy
              ? null
              : () => Navigator.of(context).pop(HuggingFaceTokenChange.none),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_save()),
          child: Text(_busy ? 'Checking\u2026' : 'Save'),
        ),
      ],
    );
  }
}
