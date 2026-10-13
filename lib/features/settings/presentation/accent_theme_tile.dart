import 'package:flutter/material.dart';
import 'package:installm/core/theme/appearance_preferences.dart';
import 'package:installm/core/theme/theme.dart';

/// One accent choice with decorative previews of its actual light/dark palette.
class AccentThemeTile extends StatelessWidget {
  const AccentThemeTile({
    super.key,
    required this.accent,
    required this.label,
    required this.selected,
    required this.contrast,
    this.onSelected,
  });

  final AccentColor accent;
  final String label;
  final bool selected;
  final double contrast;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = MaterialTheme(
      const TextTheme(),
      accent: accent,
      contrast: contrast,
    );
    final radius = BorderRadius.circular(16);
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      enabled: onSelected != null,
      onTap: onSelected,
      child: ExcludeSemantics(
        child: Material(
          color: selected
              ? colors.primary.withValues(alpha: 0.06)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: selected ? colors.primary : colors.outlineVariant,
              width: 1.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onSelected,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _PaletteOrb(
                        scheme: palette.scheme(Brightness.light),
                        selected: selected,
                      ),
                      const SizedBox(width: 12),
                      _PaletteOrb(
                        scheme: palette.scheme(Brightness.dark),
                        selected: selected,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.check_circle_rounded,
                          color: colors.primary,
                          size: 18,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaletteOrb extends StatelessWidget {
  const _PaletteOrb({required this.scheme, required this.selected});
  final ColorScheme scheme;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final light = scheme.brightness == Brightness.light;
    return SizedBox.square(
      dimension: 72,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? colors.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(0.5, -0.4),
                      radius: 1.1,
                      colors: [
                        Color.lerp(
                          scheme.primaryContainer,
                          scheme.primary,
                          0.5,
                        )!,
                        scheme.surfaceContainerLow,
                        scheme.surfaceContainerHighest,
                      ],
                      stops: const [0, 0.75, 1],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.7, -0.6),
                        radius: 1.1,
                        colors: [
                          Colors.white.withValues(alpha: light ? 0.85 : 0.12),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colors.surfaceContainer,
                shape: BoxShape.circle,
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Icon(
                light ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                size: 14,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
