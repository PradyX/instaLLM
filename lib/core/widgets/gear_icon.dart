import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The app's settings mark: a thin cog with eight rounded teeth and a hole.
///
/// Material's `settings` glyphs are heavier than the app's line icons, so this
/// one is painted from a single shape instead of looked up in the icon font:
/// a closed outline whose radius rises and falls eight times, with a plain
/// circle in the middle. Geometry is designed in a 24 dp box and scaled as a
/// whole, so the stroke weight and the tooth size stay in proportion at any
/// size the caller asks for.
class GearIcon extends StatelessWidget {
  const GearIcon({super.key, this.size = 22, this.color});

  /// Side of the square the cog is drawn in.
  final double size;

  /// Overrides the ambient icon colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved =
        color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _GearPainter(color: resolved, scale: size / 24),
      ),
    );
  }
}

class _GearPainter extends CustomPainter {
  const _GearPainter({required this.color, required this.scale});

  final Color color;
  final double scale;

  /// Designed in 24 dp: the teeth reach 10.4, the valleys sit at 6.2, the hole
  /// is 3.2, and eight teeth is the count every settings cog in the app uses.
  static const double _outer = 10.4;
  static const double _inner = 6.2;
  static const double _hole = 3.2;
  static const int _teeth = 8;

  /// Samples around one turn of the outline. Enough that the cubic segments
  /// between them read as one smooth curve.
  static const int _samples = 96;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final points = <Offset>[
      for (var index = 0; index < _samples; index++)
        _point(index / _samples * 2 * math.pi, centre),
    ];

    // Catmull-Rom through the samples, as cubic segments: a plain line loop
    // would show the teeth as facets.
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 0; index < _samples; index++) {
      final previous = points[(index - 1 + _samples) % _samples];
      final current = points[index];
      final next = points[(index + 1) % _samples];
      final after = points[(index + 2) % _samples];
      path.cubicTo(
        current.dx + (next.dx - previous.dx) / 6,
        current.dy + (next.dy - previous.dy) / 6,
        next.dx - (after.dx - current.dx) / 6,
        next.dy - (after.dy - current.dy) / 6,
        next.dx,
        next.dy,
      );
    }
    path.close();

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9 * scale
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = color;

    canvas.drawPath(path, paint);
    canvas.drawCircle(centre, _hole * scale, paint);
  }

  /// One point of the outline: a cosine wave around the circle, raised to 0.55
  /// so the teeth keep round tops instead of pointed ones.
  Offset _point(double angle, Offset centre) {
    final wave = math
        .pow(0.5 + 0.5 * math.cos(_teeth * angle), 0.55)
        .toDouble();
    final radius = (_inner + (_outer - _inner) * wave) * scale;
    return centre + Offset(math.cos(angle), math.sin(angle)) * radius;
  }

  @override
  bool shouldRepaint(_GearPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.scale != scale;
}
