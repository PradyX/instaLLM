import 'dart:async';

import 'package:flutter/material.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/features/home/application/reply_notice_service.dart';
import 'package:installm/features/home/presentation/home_controller.dart';
import 'package:installm/features/reminders/application/scheduled_job_service.dart';
import 'package:installm/features/share/application/assist_launch_provider.dart';
import 'package:installm/features/share/application/draft_attachments_provider.dart';
import 'package:installm/features/share/application/share_inbox.dart';
import 'package:installm/features/share/application/share_providers.dart';
import 'package:installm/features/share/application/process_text_provider.dart';
import 'package:installm/core/play_update/update_prompt.dart';
import 'package:installm/features/share/application/share_target_provider.dart';
import 'package:installm/features/share/domain/shared_payload.dart';
import 'package:installm/core/theme/theme.dart';
import 'package:installm/core/theme/theme_provider.dart';
import 'package:installm/core/theme/appearance_provider.dart';
import 'package:installm/core/theme/appearance_surfaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final textTheme = Theme.of(context).textTheme;
    final appearance = ref.watch(appearanceProvider).preferences;
    final theme = MaterialTheme(
      textTheme,
      accent: appearance.accent,
      surfaceStyle: appearance.surfaceStyle,
      contrast: appearance.contrast,
      glassOpacity: appearance.glassOpacity,
    );

    return MaterialApp.router(
      title: 'InstaLLM',
      debugShowCheckedModeBanner: false,
      theme: theme.light(),
      darkTheme: theme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) =>
          AppearanceBackground(child: _ShareInboxBridge(child: child!)),
    );
  }
}

/// Stages what another app shared for the chat composer (Road Map 5 Phase
/// 5.1).
///
/// It sits above the router rather than in a page, because a share can arrive
/// while any screen is open: text and links go to the composer draft, files go
/// to the draft-attachment provider, and the chat is brought to the front,
/// where the user still has to press send.
class _ShareInboxBridge extends ConsumerStatefulWidget {
  const _ShareInboxBridge({required this.child});

  final Widget child;

  @override
  ConsumerState<_ShareInboxBridge> createState() => _ShareInboxBridgeState();
}

class _ShareInboxBridgeState extends ConsumerState<_ShareInboxBridge> {
  @override
  void initState() {
    super.initState();
    final inbox = ShareInbox(
      receiver: ref.read(sharedContentReceiverProvider),
      onPayload: _stage,
    );
    unawaited(inbox.start());
    // Re-apply the stored Sharing choice at launch, so a component state that
    // drifted (a restore, a reinstall) matches what Settings shows.
    ref.read(shareTargetEnabledProvider);
    // Scheduled jobs (Road Map 5 Phase 5.4) are checked while the app is
    // alive: at launch, every tick, and whenever it comes back to the front.
    ref.read(scheduledJobServiceProvider).start();
    // A reply that finishes while the user is elsewhere posts a short notice
    // and opens its conversation when tapped (Road Map 5 Phase 5.6).
    ref.read(replyNoticeServiceProvider).start();
    // Play's own updater is asked once per launch, after the first frame so it
    // never delays startup. Off Android, and on a build Play did not install,
    // it is a quiet no-op.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(maybePromptForUpdate(context, ref));
    });
  }

  void _stage(SharedPayload payload) {
    if (!mounted) return;
    final text = payload.text;
    if (text != null) {
      ref.read(composerDraftProvider.notifier).setDraft(text);
    }
    ref.read(draftAttachmentsProvider.notifier).stage(payload.attachments);
    final readOnly = payload.processTextReadOnly;
    if (readOnly != null) {
      ref.read(processTextRequestProvider.notifier).begin(readOnly: readOnly);
    }
    // The assistant launch brings nothing with it: it only asks for the
    // composer, which is empty until the user types.
    if (payload.assist) {
      ref.read(assistLaunchProvider.notifier).signal();
    }
    ref.read(appRouterProvider).go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
