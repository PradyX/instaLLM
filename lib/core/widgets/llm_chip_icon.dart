import 'package:flutter/material.dart';

/// The app's one mark for a local model: a stack of planes, the way a model
/// file is drawn in every other tool that manages them.
///
/// Every place that marks the local model (the navigation shortcut, the
/// composer's model pill, the context page's no-model state) paints this, so
/// the glyph cannot drift apart between surfaces. Geometry is designed in a
/// 26 px box and scaled as a whole, which keeps the plane spacing and the
/// stroke weight matched at any size.
///
/// It replaced a chip outline with pins, which read as a crosshair instead of a
/// model at the 16 px the composer draws it.
class LlmChipIcon extends StatelessWidget {
  const LlmChipIcon({super.key, this.size = 26, this.color});

  /// Side of the square the glyph is drawn in.
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
        painter: _ModelStackPainter(color: resolved, scale: size / 26),
      ),
    );
  }
}

class _ModelStackPainter extends CustomPainter {
  const _ModelStackPainter({required this.color, required this.scale});

  final Color color;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = scale;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * unit
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = color;
    final centre = size.center(Offset.zero);

    Offset at(double x, double y) =>
        Offset(centre.dx + x * unit, centre.dy + y * unit);

    // The top plane is a closed diamond; the two below it are open chevrons, so
    // the mark reads as depth rather than three separate diamonds. Points are
    // given in the 26 px design box and moved to wherever the glyph is drawn.
    final top = Path()
      ..moveTo(at(13, 5.0).dx, at(13, 5.0).dy)
      ..lineTo(at(23, 10.0).dx, at(23, 10.0).dy)
      ..lineTo(at(13, 15.0).dx, at(13, 15.0).dy)
      ..lineTo(at(3, 10.0).dx, at(3, 10.0).dy)
      ..close();
    canvas.drawPath(top, stroke);

    for (final y in [13.5, 18.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(at(3, y).dx, at(3, y).dy)
          ..lineTo(at(13, y + 5).dx, at(13, y + 5).dy)
          ..lineTo(at(23, y).dx, at(23, y).dy),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_ModelStackPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.scale != scale;
}
