import 'package:flutter/material.dart';
import 'package:installm/core/navigation/app_router.dart';
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
    final themeMode = ref.watch(themeModeNotifierProvider);
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
      builder: (context, child) => AppearanceBackground(child: child!),
    );
  }
}
