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
        color: colors.primary.withValues(alpha: selected ? 0.8 : 0.3),
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
              colors.primary.withValues(alpha: selected ? 0.2 : 0.1),
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
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: selected ? colors.primary : muted,
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
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 0.95,
          colors: [
            Color.alphaBlend(
              Colors.white.withValues(alpha: 0.45),
              colors.primary,
            ),
            colors.primary,
            Color.alphaBlend(
              Colors.black.withValues(alpha: 0.22),
              colors.primary,
            ),
          ],
        ),
      ),
      child: const CustomPaint(painter: _VoiceFacePainter()),
    );
  }
}

class _VoiceFacePainter extends CustomPainter {
  const _VoiceFacePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = const Color(0xCC2A1630);
    final centre = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(centre.translate(-4.5, -2.5), 1.6, ink);
    canvas.drawCircle(centre.translate(4.5, -2.5), 1.6, ink);
    canvas.drawArc(
      Rect.fromCenter(center: centre.translate(0, 2), width: 11, height: 8),
      0.25,
      2.64,
      false,
      ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_VoiceFacePainter oldDelegate) => false;
}
