import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/theme/appearance_preferences.dart';
import 'package:installm/core/theme/appearance_provider.dart';
import 'package:installm/core/theme/appearance_surfaces.dart';
import 'package:installm/core/theme/theme_provider.dart';
import 'package:installm/features/settings/presentation/accent_theme_tile.dart';
import 'package:installm/i18n/strings.g.dart';

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
              const SizedBox(height: 32),
              _AppearanceGroup(
                title: t.appearance.surfaceStyle,
                child: Wrap(
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
              ),
              const SizedBox(height: 32),
              _AppearanceGroup(
                title: t.appearance.accentColor,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 12.0;
                    final textScale =
                        (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
                          1.0,
                          1.5,
                        );
                    final columns =
                        ((constraints.maxWidth + gap) / (220 * textScale + gap))
                            .floor()
                            .clamp(1, 3);
                    final width =
                        (constraints.maxWidth - gap * (columns - 1)) / columns;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final accent in AccentColor.values)
                          SizedBox(
                            width: width,
                            child: AccentThemeTile(
                              key: ValueKey('accent-${accent.name}'),
                              accent: accent,
                              label: _accentLabel(accent),
                              contrast: preferences.contrast,
                              selected: preferences.accent == accent,
                              onSelected: !editable
                                  ? null
                                  : () => notifier.setAccent(accent),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),
              _AppearanceGroup(
                title: t.appearance.interface,
                child: Column(
                  children: [
                    _AppearanceSlider(
                      key: const ValueKey('appearance-contrast'),
                      title: t.appearance.contrast,
                      description: t.appearance.contrastHint,
                      value: preferences.contrast,
                      min: AppearancePreferences.minContrast,
                      max: AppearancePreferences.maxContrast,
                      divisions: 20,
                      onSaved: editable ? notifier.setContrast : null,
                    ),
                    const SizedBox(height: 24),
                    _AppearanceSlider(
                      key: const ValueKey('appearance-glass-opacity'),
                      title: t.appearance.glassOpacity,
                      description:
                          preferences.surfaceStyle == SurfaceStyle.translucent
                          ? t.appearance.glassOpacityHint
                          : t.appearance.glassOpacitySolidHint,
                      value: preferences.glassOpacity,
                      min: AppearancePreferences.minGlassOpacity,
                      max: AppearancePreferences.maxGlassOpacity,
                      divisions: 50,
                      onSaved:
                          editable &&
                              preferences.surfaceStyle ==
                                  SurfaceStyle.translucent
                          ? notifier.setGlassOpacity
                          : null,
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
  AccentColor.grey => t.appearance.grey,
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

/// Drag locally; commit once on release rather than writing a file per tick.
class _AppearanceSlider extends StatefulWidget {
  const _AppearanceSlider({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    this.onSaved,
  });

  final String title;
  final String description;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Future<bool> Function(double)? onSaved;

  @override
  State<_AppearanceSlider> createState() => _AppearanceSliderState();
}

class _AppearanceSliderState extends State<_AppearanceSlider> {
  double? _dragValue;
  bool _saving = false;

  @override
  void didUpdateWidget(covariant _AppearanceSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onSaved == null) _dragValue = null;
  }

  Future<void> _save(double value) async {
    final save = widget.onSaved;
    if (save == null) return;
    setState(() => _saving = true);
    try {
      await save(value);
    } finally {
      if (mounted) {
        setState(() {
          _dragValue = null;
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = _dragValue ?? widget.value;
    final enabled = widget.onSaved != null && !_saving;
    final description = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(widget.description, style: theme.textTheme.bodySmall),
      ],
    );
    final controls = Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${(value * 100).round()}%',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        Expanded(
          child: Semantics(
            label: widget.title,
            child: SliderTheme(
              data: SliderTheme.of(
                context,
              ).copyWith(tickMarkShape: SliderTickMarkShape.noTickMark),
              child: Slider(
                value: value,
                min: widget.min,
                max: widget.max,
                divisions: widget.divisions,
                label: '${(value * 100).round()}%',
                semanticFormatterCallback: (value) =>
                    '${(value * 100).round()}%',
                onChanged: enabled
                    ? (value) => setState(() => _dragValue = value)
                    : null,
                onChangeEnd: enabled ? _save : null,
              ),
            ),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth >= 640 && textScale <= 1.3) {
          return Row(
            children: [
              Expanded(child: description),
              const SizedBox(width: 24),
              SizedBox(width: 300, child: controls),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [description, const SizedBox(height: 8), controls],
        );
      },
    );
  }
}
