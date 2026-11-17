import 'package:flutter/material.dart';
import 'package:installm/core/theme/appearance_preferences.dart';

/// One accent choice as a dot with its name underneath.
///
/// It deliberately has no card, border or gradient orb: the strip is the whole
/// control, and the only weight change is the ring and label on the selected
/// accent.
class AccentThemeTile extends StatelessWidget {
  const AccentThemeTile({
    super.key,
    required this.accent,
    required this.label,
    required this.selected,
    this.onSelected,
  });

  final AccentColor accent;
  final String label;
  final bool selected;
  final VoidCallback? onSelected;

  static const double dotSize = 30;
  static const double ringSize = 38;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      enabled: onSelected != null,
      onTap: onSelected,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: ringSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: dotSize,
                        height: dotSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _dotColor(theme.brightness),
                        ),
                      ),
                      if (selected)
                        Container(
                          width: ringSize,
                          height: ringSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colors.primary,
                              width: 1.75,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    letterSpacing: 0,
                    color: selected
                        ? colors.onSurface
                        : colors.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The accent's own colour, lifted a little in dark theme so it stays legible
  /// against the dark surface without turning into a gradient.
  Color _dotColor(Brightness brightness) => brightness == Brightness.dark
      ? Color.lerp(accent.seed, Colors.white, 0.18)!
      : accent.seed;
}
