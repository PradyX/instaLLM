import 'package:flutter/services.dart';

/// Text another app handed to InstaLLM through the Android share sheet
/// (Road Map 5 Phase 5.1).
///
/// Only the transport: the text is never sent to a model here, and nothing is
/// stored. What the user shared is a draft until they send it.
abstract class SharedTextReceiver {
  /// The text that launched this run, or null when the app was opened normally.
  ///
  /// Reading it consumes it, so an old share cannot come back the next time the
  /// app is opened from the launcher.
  Future<String?> takeInitial();

  /// Calls [onText] for every share that arrives while the app is running.
  void listen(void Function(String text) onText);
}

/// The Android implementation, backed by `installm/share` in `MainActivity`.
///
/// On a platform without the channel both calls are no-ops: a missing plugin
/// means "no share", never an error the user has to read.
class PlatformSharedTextReceiver implements SharedTextReceiver {
  PlatformSharedTextReceiver({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('installm/share');

  final MethodChannel _channel;

  @override
  Future<String?> takeInitial() async {
    try {
      final text = await _channel.invokeMethod<String>('getSharedText');
      return _clean(text);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  void listen(void Function(String text) onText) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'sharedText') return null;
      final text = _clean(call.arguments as String?);
      if (text == null) return null;
      onText(text);
      return null;
    });
  }

  static String? _clean(String? text) {
    final trimmed = text?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
