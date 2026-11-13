import 'package:flutter/material.dart';
import 'package:installm/core/theme/appearance_surfaces.dart';

/// One of the three shortcuts at the top of the rail.
///
/// It is an icon over its label on the rail itself, with no tile around it:
/// the accent icon and the label carry the target, the same way the Voice
/// mode entry below does.
class NavigationShortcutTile extends StatelessWidget {
  const NavigationShortcutTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Widget icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = BorderRadius.circular(12);
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: radius,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconTheme(
                  data: IconThemeData(size: 26, color: colors.primary),
                  child: icon,
                ),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                      letterSpacing: 0,
                      color: colors.onSurface.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Models shortcut's mark: a rounded square holding a smaller one.
class NavigationModelsIcon extends StatelessWidget {
  const NavigationModelsIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final color =
        IconTheme.of(context).color ?? Theme.of(context).colorScheme.primary;
    return CustomPaint(
      size: const Size.square(26),
      painter: _ModelsIconPainter(color),
    );
  }
}

class _ModelsIconPainter extends CustomPainter {
  const _ModelsIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final fill = Paint()..color = color;
    final outer = RRect.fromRectAndRadius(
      Rect.fromCenter(center: size.center(Offset.zero), width: 19, height: 19),
      const Radius.circular(5),
    );
    canvas.drawRRect(outer, stroke);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: size.center(Offset.zero), width: 7, height: 7),
        const Radius.circular(2),
      ),
      fill,
    );
  }

  @override
  bool shouldRepaint(_ModelsIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// One title line, with a clipped accent stripe on the selected conversation.
class NavigationChatTile extends StatelessWidget {
  const NavigationChatTile({
    super.key,
    required this.leading,
    required this.title,
    required this.selected,
    required this.onPressed,
    this.trailing,
  });

  final Widget leading;
  final String title;
  final bool selected;
  final VoidCallback? onPressed;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = selected ? colors.primary : colors.onSurfaceVariant;
    final radius = BorderRadius.circular(12);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected
              ? colors.primaryContainer.withValues(alpha: 0.5)
              : Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (selected)
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  width: 4,
                  child: ColoredBox(color: colors.primary),
                ),
              InkWell(
                onTap: onPressed,
                borderRadius: radius,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                    child: Row(
                      children: [
                        IconTheme(
                          data: IconThemeData(size: 18, color: foreground),
                          child: leading,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: onPressed == null
                                  ? foreground.withValues(alpha: 0.38)
                                  : foreground,
                            ),
                          ),
                        ),
                        if (trailing != null) ...[
                          const SizedBox(width: 8),
                          trailing!,
                        ],
                      ],
                    ),
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

/// The Voice mode entry above the chat search.
///
/// It sits directly on the rail, without a tile or card: the orb and the two
/// lines are the target, and only an open page tints the row.
class NavigationVoiceEntry extends StatelessWidget {
  const NavigationVoiceEntry({
    super.key,
    required this.selected,
    required this.onPressed,
  });

  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = BorderRadius.circular(14);
    final muted = colors.onSurfaceVariant;
    final scale = (MediaQuery.textScalerOf(context).scale(13) / 13).clamp(
      1.0,
      1.2,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected
              ? appearanceSurfaceColor(
                  context,
                  Color.alphaBlend(
                    colors.primary.withValues(alpha: 0.12),
                    colors.surfaceContainerLow,
                  ),
                )
              : Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            borderRadius: radius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 78),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Row(
                  children: [
                    _VoiceOrb(scale: scale),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Voice mode',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: onPressed == null
                                  ? colors.onSurface.withValues(alpha: 0.38)
                                  : colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Talk, hands free',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 13,
                              letterSpacing: 0,
                              color: colors.onSurface.withValues(alpha: 0.66),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 24 * scale,
                      color: selected
                          ? colors.primary
                          : muted.withValues(alpha: 0.9),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Companion orb at rail size: one accent sphere with its two-dot face.
class _VoiceOrb extends StatelessWidget {
  const _VoiceOrb({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final size = 56 * scale;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _VoiceOrbPainter(colors.primary)),
    );
  }
}

class _VoiceOrbPainter extends CustomPainter {
  const _VoiceOrbPainter(this.primary);

  final Color primary;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final bounds = Rect.fromCircle(center: centre, radius: radius);

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.38, -0.44),
          radius: 1.0,
          colors: [
            Color.alphaBlend(Colors.white.withValues(alpha: 0.5), primary),
            primary,
            Color.alphaBlend(Colors.black.withValues(alpha: 0.3), primary),
          ],
          stops: const [0, 0.62, 1],
        ).createShader(bounds),
    );

    // A soft rim and a thin outline keep the sphere from looking like a flat
    // circle sitting on the rail.
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.18),
          ],
          stops: const [0, 0.66, 1],
        ).createShader(bounds),
    );
    canvas.drawCircle(
      centre,
      radius - radius * 0.03,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.07
        ..color = Color.alphaBlend(
          Colors.black.withValues(alpha: 0.35),
          primary,
        ),
    );

    // One small highlight, top left, the way the page's orb is lit.
    canvas.drawOval(
      Rect.fromCenter(
        center: centre.translate(-radius * 0.3, -radius * 0.46),
        width: radius * 0.62,
        height: radius * 0.34,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.2),
    );

    // Two dots and a short bar, not a smile: at this size a curve reads as
    // an emoji sticker rather than the page's orb. The face flips to light
    // ink on a dark accent, where a dark face would vanish. Everything is
    // proportional so the same painter works at 34 and at 56 px.
    final ink = Paint()
      ..color = primary.computeLuminance() > 0.4
          ? const Color(0xCC2A1630)
          : Colors.white.withValues(alpha: 0.85);
    canvas.drawCircle(
      centre.translate(-radius * 0.25, -radius * 0.15),
      radius * 0.085,
      ink,
    );
    canvas.drawCircle(
      centre.translate(radius * 0.25, -radius * 0.15),
      radius * 0.085,
      ink,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: centre.translate(0, radius * 0.19),
          width: radius * 0.46,
          height: radius * 0.11,
        ),
        Radius.circular(radius * 0.055),
      ),
      ink,
    );
  }

  @override
  bool shouldRepaint(_VoiceOrbPainter oldDelegate) =>
      oldDelegate.primary != primary;
}
