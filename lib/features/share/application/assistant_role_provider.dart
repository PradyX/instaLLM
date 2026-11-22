import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/share/application/share_providers.dart';

/// Whether InstaLLM is the device's default assistant
/// (Road Map 5 Phase 5.3).
///
/// The role is the user's to grant in system UI, so nothing here switches it on
/// by itself: [AssistantRoleNotifier.request] opens the platform's own prompt
/// and [AssistantRoleNotifier.refresh] reads back what the user chose. A
/// platform with no assistant role reports false, and the settings row says so
/// instead of offering a prompt that cannot appear.
final assistantRoleProvider =
    AsyncNotifierProvider<AssistantRoleNotifier, bool>(
      AssistantRoleNotifier.new,
    );

class AssistantRoleNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => _read();

  Future<bool> _read() async {
    try {
      return await ref
          .read(sharedContentReceiverProvider)
          .isAssistantRoleHeld();
    } catch (_) {
      return false;
    }
  }

  /// Re-reads the role, e.g. after the user came back from system settings.
  Future<void> refresh() async {
    state = AsyncData(await _read());
  }

  /// Asks the platform to show its "use as default assistant" prompt.
  ///
  /// Returns false when the platform has no such role, so the caller can say
  /// something actionable rather than showing nothing at all.
  Future<bool> request() async {
    try {
      final shown = await ref
          .read(sharedContentReceiverProvider)
          .requestAssistantRole();
      if (shown) {
        // The prompt is answered elsewhere; the role is read again when the
        // page is shown, and on the next launch.
        state = AsyncData(await _read());
      }
      return shown;
    } catch (_) {
      return false;
    }
  }
}
