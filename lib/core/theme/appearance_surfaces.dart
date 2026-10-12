import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:pocket_llm/core/theme/appearance_preferences.dart';

class SurfaceAppearance extends ThemeExtension<SurfaceAppearance> {
  const SurfaceAppearance(this.style);
  final SurfaceStyle style;
  bool get isTranslucent => style == SurfaceStyle.translucent;

  @override
  SurfaceAppearance copyWith({SurfaceStyle? style}) =>
      SurfaceAppearance(style ?? this.style);

  @override
  SurfaceAppearance lerp(covariant SurfaceAppearance? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

bool usesTranslucentSurfaces(BuildContext context) =>
    Theme.of(context).extension<SurfaceAppearance>()?.isTranslucent ?? false;

Color appearanceSurfaceColor(BuildContext context, Color color) =>
    usesTranslucentSurfaces(context) ? color.withValues(alpha: 0.78) : color;

/// One clipped blur per large panel, never a blur on each message or row.
class FrostedPanel extends StatelessWidget {
  const FrostedPanel({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
  });
  final Widget child;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) => !usesTranslucentSurfaces(context)
      ? child
      : ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: child,
          ),
        );
}

/// An app-owned background: no desktop capture, images or native window effects.
class AppearanceBackground extends StatelessWidget {
  const AppearanceBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!usesTranslucentSurfaces(context)) return child;
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.surface,
            Color.alphaBlend(
              colors.primaryContainer.withValues(alpha: 0.55),
              colors.surface,
            ),
            Color.alphaBlend(
              colors.tertiaryContainer.withValues(alpha: 0.35),
              colors.surface,
            ),
            colors.surface,
          ],
        ),
      ),
      child: child,
    );
  }
}
