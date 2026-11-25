import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/play_review/review_prompt.dart';
import 'package:installm/core/play_update/play_update_service.dart';
import 'package:installm/core/play_update/update_prompt_dialog.dart';
import 'package:installm/core/play_update/update_prompt_store.dart';

final updatePromptStoreProvider = FutureProvider<UpdatePromptStore>(
  (ref) => UpdatePromptStore.open(),
);

/// A dismissal quiets the prompt for a week. The update keeps working in the
/// background meanwhile, and Play itself still shows its own update rows.
const updatePromptDismissWindow = Duration(days: 7);

/// Decides whether Play's update availability is worth interrupting for.
class UpdatePromptPolicy {
  UpdatePromptPolicy(this._store);

  final UpdatePromptStore _store;

  bool get isReadOnly => _store.isReadOnly;

  bool shouldPrompt({int? availableVersionCode, DateTime? now}) {
    final state = _store.load();
    final dismissedAt = state.dismissedAt;
    if (dismissedAt == null) return true;

    // A different build is a different update: ask straight away.
    final dismissedCode = state.dismissedVersionCode;
    if (availableVersionCode != null &&
        dismissedCode != null &&
        availableVersionCode != dismissedCode) {
      return true;
    }
    return (now ?? DateTime.now()).difference(dismissedAt) >=
        updatePromptDismissWindow;
  }

  void dismiss({int? availableVersionCode}) {
    _store.save(
      UpdatePromptState(
        dismissedAt: DateTime.now(),
        dismissedVersionCode: availableVersionCode,
      ),
    );
  }
}

/// Sees whether the Play Store has a newer build and asks the user about it.
///
/// Called once per launch, after the first frame, so it never delays startup or
/// fights the composer for focus. Everything it decides is Play's own data: the
/// app makes no request of its own.
///
/// Debug builds never ask: Play would refuse a sideloaded APK anyway, and a
/// development install should not nag about the store version.
Future<void> maybePromptForUpdate(BuildContext context, WidgetRef ref) async {
  if (kDebugMode) return;
  const service = PlayUpdateService();
  if (!PlayUpdateService.isSupported) return;

  final check = await service.check();
  if (!check.hasUpdate || !context.mounted) return;

  final UpdatePromptPolicy policy;
  try {
    policy = UpdatePromptPolicy(
      await ref.read(updatePromptStoreProvider.future),
    );
  } catch (_) {
    return;
  }
  if (policy.isReadOnly) return;
  if (!policy.shouldPrompt(availableVersionCode: check.availableVersionCode)) {
    return;
  }
  if (!context.mounted) return;

  await showUpdatePromptDialog(
    context: context,
    check: check,
    policy: policy,
    service: service,
  );
}

/// Kept here so the Play listing opener lives in one place for both Play
/// prompts (the star row and this dialog).
Future<void> openPlayStore() => openPlayStoreListing();
