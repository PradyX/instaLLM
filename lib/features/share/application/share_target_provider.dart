import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/share/application/share_providers.dart';
import 'package:installm/storage/secure_storage.dart';

/// Whether other apps may hand InstaLLM text or a link
/// (Road Map 5 Phase 5.1).
///
/// Off until the user turns it on: an app that quietly joins every share sheet
/// is not a privacy-first default. The choice is stored with the other app
/// settings and also applied to the platform, because the Android component
/// that appears in other apps' share sheets outlives this process — so the
/// stored value is re-applied at startup rather than trusted to have stuck.
typedef ShareTargetSettingReader = Future<bool?> Function();
typedef ShareTargetSettingWriter = Future<void> Function(bool enabled);

final shareTargetEnabledProvider = NotifierProvider<ShareTargetNotifier, bool>(
  ShareTargetNotifier.new,
);

class ShareTargetNotifier extends Notifier<bool> {
  ShareTargetNotifier({
    ShareTargetSettingReader? read,
    ShareTargetSettingWriter? write,
  }) : _read = read ?? _readStored,
       _write = write ?? _writeStored;

  static const String settingsKey = 'share_target_enabled';

  final ShareTargetSettingReader _read;
  final ShareTargetSettingWriter _write;

  @override
  bool build() {
    _restore();
    return false;
  }

  Future<void> _restore() async {
    final stored = await _read() ?? false;
    state = stored;
    await _apply(stored);
  }

  /// Turns the share and link target on or off and remembers the choice.
  Future<void> setEnabled(bool enabled) async {
    if (state == enabled) return;
    state = enabled;
    await _write(enabled);
    await _apply(enabled);
  }

  Future<void> _apply(bool enabled) async {
    try {
      await ref
          .read(sharedContentReceiverProvider)
          .setShareTargetEnabled(enabled);
    } catch (_) {
      // The stored choice is what matters; a platform that refuses the
      // component change is retried on the next launch.
    }
  }

  static Future<bool?> _readStored() async {
    try {
      final stored = await SecureStorage.instance.read(settingsKey);
      final enabled = stored?['enabled'];
      return enabled is bool ? enabled : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeStored(bool enabled) async {
    try {
      await SecureStorage.instance.write(
        key: settingsKey,
        value: {'enabled': enabled},
      );
    } catch (_) {
      // An unreadable store must not take the switch down with it.
    }
  }
}
