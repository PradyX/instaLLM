import 'dart:async';

import 'package:flutter/material.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/features/home/presentation/home_controller.dart';
import 'package:installm/features/share/application/share_inbox.dart';
import 'package:installm/features/share/application/share_providers.dart';
import 'package:installm/features/share/application/share_target_provider.dart';
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

/// Stages text another app shared into the chat composer (Road Map 5 Phase
/// 5.1).
///
/// It sits above the router rather than in a page, because a share can arrive
/// while any screen is open: the draft is handed to the composer provider and
/// the chat is brought to the front, where the user still has to press send.
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
      receiver: ref.read(sharedTextReceiverProvider),
      onText: _stage,
    );
    unawaited(inbox.start());
    // Re-apply the stored Sharing choice at launch, so a component state that
    // drifted (a restore, a reinstall) matches what Settings shows.
    ref.read(shareTargetEnabledProvider);
  }

  void _stage(String text) {
    if (!mounted) return;
    ref.read(composerDraftProvider.notifier).setDraft(text);
    ref.read(appRouterProvider).go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
