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
  amber(Color(0xffa47716));

  const AccentColor(this.seed);
  final Color seed;
}

/// Cosmetic preferences are independent of the existing theme-mode setting.
class AppearancePreferences {
  const AppearancePreferences({
    this.surfaceStyle = SurfaceStyle.solid,
    this.accent = AccentColor.green,
  });

  final SurfaceStyle surfaceStyle;
  final AccentColor accent;

  AppearancePreferences copyWith({
    SurfaceStyle? surfaceStyle,
    AccentColor? accent,
  }) => AppearancePreferences(
    surfaceStyle: surfaceStyle ?? this.surfaceStyle,
    accent: accent ?? this.accent,
  );

  Map<String, dynamic> toJson() => {
    'surfaceStyle': surfaceStyle.name,
    'accent': accent.name,
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
      );
}
