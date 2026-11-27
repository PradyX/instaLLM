import 'package:flutter/material.dart';

/// The app's one mark for an LLM: a brain inside a chip package.
///
/// Every place that marks the local model (the navigation shortcut, the
/// composer's model pill, the context page's no-model state) paints this, so
/// the glyph cannot drift apart between surfaces. Geometry is designed in a
/// 24 px box and scaled as a whole, which keeps the pin spacing and the stroke
/// weight matched at any size.
class LlmChipIcon extends StatelessWidget {
  const LlmChipIcon({super.key, this.size = 26, this.color});

  /// Side of the square the mark is drawn in.
  final double size;

  /// Overrides the ambient icon colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved =
        color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.primary;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _LlmChipPainter(color: resolved, scale: size / _designBox),
      ),
    );
  }
}

/// Side of the square the mark's coordinates are written in.
const double _designBox = 24;

/// The brain curves, in the 24 px design box.
///
/// Placed at 0.58 of the box and drawn inside a scaled canvas, so the chip
/// keeps its own weight while the brain's hairline thins with it.
final Path _brainPath = Path()
  ..moveTo(12, 18)
  ..lineTo(12, 5)
  ..moveTo(15, 13)
  ..arcToPoint(
    const Offset(12, 9),
    radius: const Radius.circular(4.17),
    clockwise: true,
  )
  ..arcToPoint(
    const Offset(9, 13),
    radius: const Radius.circular(4.17),
    clockwise: true,
  )
  ..moveTo(17.707, 6.294)
  ..arcToPoint(
    const Offset(12, 5),
    radius: const Radius.circular(3),
    largeArc: true,
    clockwise: false,
  )
  ..arcToPoint(
    const Offset(6.293, 6.294),
    radius: const Radius.circular(3),
    largeArc: true,
    clockwise: false,
  )
  ..moveTo(17.996, 5.125)
  ..arcToPoint(
    const Offset(20.522, 10.895),
    radius: const Radius.circular(4),
    clockwise: true,
  )
  ..moveTo(18, 18)
  ..arcToPoint(
    const Offset(20, 10.535),
    radius: const Radius.circular(4),
    clockwise: false,
  )
  ..moveTo(19.967, 17.482)
  ..arcToPoint(
    const Offset(12, 18),
    radius: const Radius.circular(4),
    largeArc: true,
    clockwise: true,
  )
  ..arcToPoint(
    const Offset(4.033, 17.482),
    radius: const Radius.circular(4),
    largeArc: true,
    clockwise: true,
  )
  ..moveTo(6, 18)
  ..arcToPoint(
    const Offset(4, 10.535),
    radius: const Radius.circular(4),
    clockwise: true,
  )
  ..moveTo(6.004, 5.125)
  ..arcToPoint(
    const Offset(3.478, 10.895),
    radius: const Radius.circular(4),
    clockwise: false,
  );

/// How much of the box the brain takes, inside the package.
const double _brainScale = 0.58;

class _LlmChipPainter extends CustomPainter {
  const _LlmChipPainter({required this.color, required this.scale});

  final Color color;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = color;

    // Pins first, so the package covers their inner ends. Two a side: one arm
    // each way disappeared into the package at the pill's 18 px, and three
    // merged into a hatch.
    line.strokeWidth = 1.9;
    final pins = Path();
    for (final arm in const [9.0, 15.0]) {
      pins
        ..moveTo(arm, 1.2)
        ..lineTo(arm, 3.1)
        ..moveTo(arm, 20.9)
        ..lineTo(arm, 22.8)
        ..moveTo(1.2, arm)
        ..lineTo(3.1, arm)
        ..moveTo(20.9, arm)
        ..lineTo(22.8, arm);
    }
    canvas.drawPath(pins, line);

    line.strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.8, 3.8, 16.4, 16.4),
        const Radius.circular(4),
      ),
      line,
    );

    // The brain is drawn in the box's own units inside a scaled canvas, which
    // thins its strokes along with the shape instead of crowding the package.
    canvas
      ..save()
      ..translate(_designBox / 2, _designBox / 2)
      ..scale(_brainScale)
      ..translate(-_designBox / 2, -_designBox / 2);
    line.strokeWidth = 2.5;
    canvas.drawPath(_brainPath, line);
    canvas
      ..restore()
      ..restore();
  }

  @override
  bool shouldRepaint(_LlmChipPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.scale != scale;
}
