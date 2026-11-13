import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The system's Reduce Motion preference, where Flutter does not report it.
///
/// Flutter surfaces Android's "remove animations" as
/// `MediaQuery.disableAnimations`, but macOS only exposes "Reduce motion" to
/// AppKit, and the macOS embedder does not forward it. The runner reads
/// `NSWorkspace.accessibilityDisplayShouldReduceMotion` and sends it over this
/// channel, so custom animation can honour the setting there too.
class ReduceMotion {
  ReduceMotion._();

  static const MethodChannel _channel = MethodChannel('installm/accessibility');

  /// True while the user has asked the system to reduce motion. On platforms
  /// without the channel this stays false and the Flutter flags decide.
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  static bool _started = false;

  /// Starts listening once; safe to call from any widget that animates.
  static void ensureStarted() {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'reduceMotionChanged') {
        enabled.value = call.arguments == true;
      }
      return null;
    });
    _refresh();
  }

  static Future<void> _refresh() async {
    try {
      enabled.value =
          await _channel.invokeMethod<bool>('shouldReduceMotion') ?? false;
    } on MissingPluginException {
      // Not macOS, or no runner support: the Flutter flags are all there is.
    } on PlatformException {
      // Same: leave the preference at its safe default.
    }
  }
}
