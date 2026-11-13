import 'package:flutter/material.dart';
import 'package:installm/core/theme/appearance_surfaces.dart';

class NavigationShortcutTile extends StatelessWidget {
  const NavigationShortcutTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: colors.primary.withValues(alpha: 0.18)),
    );
    return Material(
      color: appearanceSurfaceColor(
        context,
        Color.alphaBlend(
          colors.primary.withValues(alpha: 0.06),
          colors.surfaceContainerLow,
        ),
      ),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        customBorder: shape,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 24, color: colors.primary),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      letterSpacing: 0,
                      color: colors.onSurfaceVariant,
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

/// The Voice mode doorway above the chat search.
///
/// It is a card rather than a chat row because it leaves the conversation
/// list entirely: a tinted surface, the orb's face and a one-line promise,
/// so it reads as the start of the rail instead of another chat.
class NavigationVoiceCard extends StatelessWidget {
  const NavigationVoiceCard({
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
    final radius = BorderRadius.circular(12);
    final shape = RoundedRectangleBorder(
      borderRadius: radius,
      side: BorderSide(
        color: colors.primary.withValues(alpha: selected ? 1.0 : 0.38),
      ),
    );
    final muted = colors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: appearanceSurfaceColor(
            context,
            Color.alphaBlend(
              colors.primary.withValues(alpha: selected ? 0.3 : 0.14),
              colors.surfaceContainerLow,
            ),
          ),
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            customBorder: shape,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 58),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
                child: Row(
                  children: [
                    const _VoiceOrb(),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Voice mode',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                              color: onPressed == null
                                  ? colors.onSurface.withValues(alpha: 0.38)
                                  : colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Talk, hands free',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 10.5,
                              letterSpacing: 0,
                              color: colors.onSurface.withValues(alpha: 0.62),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 21,
                      color: selected
                          ? colors.primary
                          : muted.withValues(alpha: 0.85),
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

/// The Companion orb at card size: one accent sphere with its two-dot face.
class _VoiceOrb extends StatelessWidget {
  const _VoiceOrb();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Keep the orb in proportion with the two lines beside it, but stop it
    // growing well before it would crowd the card at the largest text.
    final scale = (MediaQuery.textScalerOf(context).scale(13) / 13).clamp(
      1.0,
      1.25,
    );
    final size = 34 * scale;
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

    // A soft rim keeps the sphere from looking like a flat circle on the card.
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

    // One small highlight, top left, the way the page's orb is lit.
    canvas.drawOval(
      Rect.fromCenter(
        center: centre.translate(-radius * 0.3, -radius * 0.46),
        width: radius * 0.62,
        height: radius * 0.34,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.22),
    );

    // Two dots and a short bar, not a smile: at this size a curve reads as
    // an emoji sticker rather than the page's orb. The face flips to light
    // ink on a dark accent, where a dark face would vanish.
    final ink = Paint()
      ..color = primary.computeLuminance() > 0.4
          ? const Color(0xCC2A1630)
          : Colors.white.withValues(alpha: 0.85);
    canvas.drawCircle(centre.translate(-4.2, -2.8), 1.4, ink);
    canvas.drawCircle(centre.translate(4.2, -2.8), 1.4, ink);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: centre.translate(0, 3.2),
          width: 8,
          height: 1.9,
        ),
        const Radius.circular(1),
      ),
      ink,
    );
  }

  @override
  bool shouldRepaint(_VoiceOrbPainter oldDelegate) =>
      oldDelegate.primary != primary;
}
