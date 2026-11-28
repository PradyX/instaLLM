import 'dart:async';

import 'package:flutter/material.dart';
import 'package:installm/features/settings/presentation/hugging_face_token_dialog.dart';
import 'package:installm/core/services/hugging_face_auth_service.dart';

/// The optional Hugging Face access token.
///
/// It is the one setting that changes how the catalog and downloads are read,
/// so it sits on its own row: what it is, who it belongs to, and one action to
/// add, replace or remove it.
class HuggingFaceTokenSection extends StatefulWidget {
  const HuggingFaceTokenSection({super.key, this.auth});

  /// Injectable for tests; the app uses the shared service.
  final HuggingFaceAuthService? auth;

  @override
  State<HuggingFaceTokenSection> createState() =>
      _HuggingFaceTokenSectionState();
}

class _HuggingFaceTokenSectionState extends State<HuggingFaceTokenSection> {
  late final HuggingFaceAuthService _auth =
      widget.auth ?? HuggingFaceAuthService.instance;

  bool _loading = true;
  String? _token;
  String? _account;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final token = await _auth.token();
    if (!mounted) return;
    setState(() {
      _token = token;
      _loading = false;
      if (token == null) _account = null;
    });
    if (token == null) return;
    try {
      final identity = await _auth.verify();
      if (!mounted) return;
      setState(() => _account = identity.name);
    } on HuggingFaceTokenException {
      // Offline, or the token was revoked after it was saved. The row still
      // says a token is saved; the dialog is where it is checked or replaced.
      if (!mounted) return;
      setState(() => _account = null);
    }
  }

  String get _subtitle {
    if (_loading) return 'Checking\u2026';
    if (_token == null) {
      return 'Not set. Downloads share Hugging Face\u2019s anonymous rate '
          'limit.';
    }
    if (_account != null) {
      return 'Connected as $_account. Downloads use this account\u2019s '
          'limits.';
    }
    return 'Saved. Downloads use this account\u2019s limits.';
  }

  Future<void> _editToken() async {
    final change = await showHuggingFaceTokenDialog(context, auth: _auth);
    if (change == HuggingFaceTokenChange.none || !mounted) return;
    await _load();
    if (!mounted) return;
    final message = change == HuggingFaceTokenChange.removed
        ? 'Token removed. Downloads are anonymous again.'
        : _account != null
        ? 'Connected as $_account.'
        : 'Token saved. It could not be checked right now.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.vpn_key_outlined),
        title: const Text('Hugging Face token'),
        subtitle: Text(_subtitle),
        trailing: TextButton(
          onPressed: _loading ? null : () => unawaited(_editToken()),
          child: Text(_token == null ? 'Add' : 'Manage'),
        ),
        onTap: _loading ? null : () => unawaited(_editToken()),
      ),
    );
  }
}
