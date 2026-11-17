import 'package:flutter/material.dart';

/// The app's one mark for an LLM: a chip outline with its pins.
///
/// Every place that marks the local model (the navigation shortcut, the
/// composer's model pill, the context page's no-model state) paints this, so
/// the glyph cannot drift apart between surfaces. Geometry is designed in a
/// 26 px box and scaled as a whole, which keeps the pin spacing and the stroke
/// weight matched at any size.
class LlmChipIcon extends StatelessWidget {
  const LlmChipIcon({super.key, this.size = 26, this.color});

  /// Side of the square the chip is drawn in.
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
        painter: _LlmChipPainter(color: resolved, scale: size / 26),
      ),
    );
  }
}

class _LlmChipPainter extends CustomPainter {
  const _LlmChipPainter({required this.color, required this.scale});

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
    final fill = Paint()..color = color;
    final centre = size.center(Offset.zero);

    // Pins first, so the body covers their inner ends. One arm a side at every
    // size: the rail and the composer pill then paint the same mark, and three
    // arms a side smudge together below the rail's size.
    const pins = [0.0];
    for (final offset in pins) {
      final pin = offset * unit;
      canvas.drawLine(
        Offset(centre.dx + pin, centre.dy - 12.4 * unit),
        Offset(centre.dx + pin, centre.dy - 7.6 * unit),
        stroke,
      );
      canvas.drawLine(
        Offset(centre.dx + pin, centre.dy + 7.6 * unit),
        Offset(centre.dx + pin, centre.dy + 12.4 * unit),
        stroke,
      );
      canvas.drawLine(
        Offset(centre.dx - 12.4 * unit, centre.dy + pin),
        Offset(centre.dx - 7.6 * unit, centre.dy + pin),
        stroke,
      );
      canvas.drawLine(
        Offset(centre.dx + 7.6 * unit, centre.dy + pin),
        Offset(centre.dx + 12.4 * unit, centre.dy + pin),
        stroke,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: centre, width: 15 * unit, height: 15 * unit),
        Radius.circular(4 * unit),
      ),
      stroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: centre, width: 5 * unit, height: 5 * unit),
        Radius.circular(1.2 * unit),
      ),
      fill,
    );
  }

  @override
  bool shouldRepaint(_LlmChipPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.scale != scale;
}
