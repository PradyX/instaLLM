import 'package:flutter/material.dart';

enum SurfaceStyle { solid, translucent }

enum AccentColor {
  green(Color(0xff4c662b)),
  blue(Color(0xff3568c0)),
  purple(Color(0xff7952b3)),
  teal(Color(0xff008577)),
  pink(Color(0xffb74786)),
  orange(Color(0xffbd651c)),
  red(Color(0xffbf4040)),
  amber(Color(0xffa47716)),
  grey(Color(0xff60636a));

  const AccentColor(this.seed);
  final Color seed;
}

/// Cosmetic preferences are independent of the existing theme-mode setting.
class AppearancePreferences {
  const AppearancePreferences({
    this.surfaceStyle = SurfaceStyle.solid,
    this.accent = AccentColor.green,
    this.contrast = defaultContrast,
    this.glassOpacity = defaultGlassOpacity,
  });

  static const defaultContrast = 1.0;
  static const minContrast = 1.0;
  static const maxContrast = 2.0;
  static const defaultGlassOpacity = 0.78;
  static const minGlassOpacity = 0.5;
  static const maxGlassOpacity = 1.0;

  final SurfaceStyle surfaceStyle;
  final AccentColor accent;
  final double contrast;
  final double glassOpacity;

  AppearancePreferences copyWith({
    SurfaceStyle? surfaceStyle,
    AccentColor? accent,
    double? contrast,
    double? glassOpacity,
  }) => AppearancePreferences(
    surfaceStyle: surfaceStyle ?? this.surfaceStyle,
    accent: accent ?? this.accent,
    contrast: _boundedNumber(
      contrast ?? this.contrast,
      minContrast,
      maxContrast,
      defaultContrast,
    ),
    glassOpacity: _boundedNumber(
      glassOpacity ?? this.glassOpacity,
      minGlassOpacity,
      maxGlassOpacity,
      defaultGlassOpacity,
    ),
  );

  Map<String, dynamic> toJson() => {
    'surfaceStyle': surfaceStyle.name,
    'accent': accent.name,
    'contrast': contrast,
    'glassOpacity': glassOpacity,
  };

  factory AppearancePreferences.fromJson(Map<String, dynamic> json) =>
      AppearancePreferences(
        surfaceStyle: SurfaceStyle.values.firstWhere(
          (style) => style.name == json['surfaceStyle'],
          orElse: () => SurfaceStyle.solid,
        ),
        accent: AccentColor.values.firstWhere(
          (accent) => accent.name == json['accent'],
          orElse: () => AccentColor.green,
        ),
        contrast: _boundedNumber(
          json['contrast'],
          minContrast,
          maxContrast,
          defaultContrast,
        ),
        glassOpacity: _boundedNumber(
          json['glassOpacity'],
          minGlassOpacity,
          maxGlassOpacity,
          defaultGlassOpacity,
        ),
      );
}

double _boundedNumber(Object? value, double min, double max, double fallback) =>
    value is num && value.isFinite
    ? value.toDouble().clamp(min, max)
    : fallback;
