import 'package:flutter/services.dart';
import 'package:installm/features/share/domain/shared_payload.dart';

/// What another app handed to InstaLLM through the share sheet or a link
/// (Road Map 5 Phase 5.1).
///
/// Only the transport: nothing is sent to a model here, and nothing is stored.
/// What the user shared is a draft until they send it.
abstract class SharedContentReceiver {
  /// The payload that launched this run, or null when the app was opened
  /// normally.
  ///
  /// Reading it consumes it, so an old share cannot come back the next time the
  /// app is opened from the launcher.
  Future<SharedPayload?> takeInitial();

  /// Calls [onPayload] for every share that arrives while the app is running.
  void listen(void Function(SharedPayload payload) onPayload);

  /// Shows or hides InstaLLM as a share and link target on the device.
  ///
  /// The switch has to reach the platform, because the Android component that
  /// appears in other apps' share sheets outlives this process.
  Future<void> setShareTargetEnabled(bool enabled);

  /// Hands [text] back to the app a selection came from, replacing it.
  ///
  /// Returns false when no editable selection is waiting: a read-only one is
  /// never replaced, and the platform refuses it even if a caller asks.
  Future<bool> returnProcessedText(String text);
}

/// The Android implementation, backed by `installm/share` in `MainActivity`.
///
/// On a platform without the channel both calls are no-ops: a missing plugin
/// means "no share", never an error the user has to read.
class PlatformSharedContentReceiver implements SharedContentReceiver {
  PlatformSharedContentReceiver({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('installm/share');

  final MethodChannel _channel;

  @override
  Future<SharedPayload?> takeInitial() async {
    try {
      final payload = await _channel.invokeMethod<Object?>('getSharedContent');
      return sharedPayloadFromMap(payload);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  void listen(void Function(SharedPayload payload) onPayload) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'sharedContent') return null;
      final payload = sharedPayloadFromMap(call.arguments);
      if (payload == null) return null;
      onPayload(payload);
      return null;
    });
  }

  @override
  Future<void> setShareTargetEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<bool>('setShareTargetEnabled', enabled);
    } on MissingPluginException {
      // A platform with no share sheet has nothing to switch on.
    } on PlatformException {
      // The switch keeps its stored value; the next launch applies it again.
    }
  }

  @override
  Future<bool> returnProcessedText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'returnProcessedText',
            trimmed,
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
