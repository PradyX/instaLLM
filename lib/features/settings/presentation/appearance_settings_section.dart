import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_llm/core/theme/appearance_preferences.dart';
import 'package:pocket_llm/core/theme/appearance_provider.dart';
import 'package:pocket_llm/core/theme/appearance_surfaces.dart';
import 'package:pocket_llm/core/theme/theme_provider.dart';
import 'package:pocket_llm/i18n/strings.g.dart';

class AppearanceSettingsSection extends ConsumerWidget {
  const AppearanceSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeNotifierProvider);
    final appearance = ref.watch(appearanceProvider);
    final preferences = appearance.preferences;
    final editable = appearance.isReady && !appearance.isReadOnly;
    final notifier = ref.read(appearanceProvider.notifier);
    return FrostedPanel(
      borderRadius: BorderRadius.circular(12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AppearanceGroup(
                title: t.appearance.themeMode,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (value, label, icon) in [
                      (
                        ThemeMode.system,
                        t.appearance.auto,
                        Icons.brightness_auto,
                      ),
                      (ThemeMode.light, t.appearance.light, Icons.light_mode),
                      (ThemeMode.dark, t.appearance.dark, Icons.dark_mode),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        avatar: Icon(icon, size: 18),
                        selected: mode == value,
                        onSelected: (selected) async {
                          if (!selected) return;
                          try {
                            await ref
                                .read(themeModeNotifierProvider.notifier)
                                .setThemeMode(value);
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(t.appearance.modeSaveError),
                                ),
                              );
                            }
                          }
                        },
                      ),
                  ],
                ),
              ),
              const Divider(height: 32),
              _AppearanceGroup(
                title: t.appearance.surfaceStyle,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (value, label, icon) in [
                          (
                            SurfaceStyle.solid,
                            t.appearance.solid,
                            Icons.rectangle_outlined,
                          ),
                          (
                            SurfaceStyle.translucent,
                            t.appearance.translucent,
                            Icons.blur_on_rounded,
                          ),
                        ])
                          ChoiceChip(
                            label: Text(label),
                            avatar: Icon(icon, size: 18),
                            selected: preferences.surfaceStyle == value,
                            onSelected: !editable
                                ? null
                                : (selected) {
                                    if (selected) {
                                      notifier.setSurfaceStyle(value);
                                    }
                                  },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.appearance.translucentHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Divider(height: 32),
              _AppearanceGroup(
                title: t.appearance.accentColor,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final accent in AccentColor.values)
                      ChoiceChip(
                        label: Text(_accentLabel(accent)),
                        selected: preferences.accent == accent,
                        avatar: DecoratedBox(
                          decoration: BoxDecoration(
                            color: accent.seed,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox.square(dimension: 18),
                        ),
                        onSelected: !editable
                            ? null
                            : (selected) {
                                if (selected) notifier.setAccent(accent);
                              },
                      ),
                  ],
                ),
              ),
              if (appearance.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    switch (appearance.error!) {
                      AppearanceError.load => t.appearance.loadError,
                      AppearanceError.save => t.appearance.saveError,
                      AppearanceError.newerVersion => t.appearance.newerVersion,
                    },
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _accentLabel(AccentColor accent) => switch (accent) {
  AccentColor.green => t.appearance.green,
  AccentColor.blue => t.appearance.blue,
  AccentColor.purple => t.appearance.purple,
  AccentColor.teal => t.appearance.teal,
  AccentColor.pink => t.appearance.pink,
  AccentColor.orange => t.appearance.orange,
  AccentColor.red => t.appearance.red,
  AccentColor.amber => t.appearance.amber,
};

class _AppearanceGroup extends StatelessWidget {
  const _AppearanceGroup({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 12),
      child,
    ],
  );
}
