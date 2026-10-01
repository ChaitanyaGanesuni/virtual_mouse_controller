import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A quiet line-drawn lotus used as the app's only ornament.
class Lotus extends StatelessWidget {
  const Lotus({super.key, this.size = 40, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size(size, size * 0.62),
      painter: _LotusPainter(color ?? Theme.of(context).colorScheme.primary),
    ),
  );
}

class _LotusPainter extends CustomPainter {
  _LotusPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, size.width / 40)
      ..strokeCap = StrokeCap.round;
    final base = Offset(size.width / 2, size.height * 0.92);
    // Five petals fanning out from the base.
    for (final angle in [-56.0, -28.0, 0.0, 28.0, 56.0]) {
      final len = size.height * (angle == 0 ? 0.9 : (angle.abs() < 30 ? 0.78 : 0.6));
      final width = size.width * 0.13;
      canvas.save();
      canvas.translate(base.dx, base.dy);
      canvas.rotate(angle * math.pi / 180);
      final petal = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(width, -len * 0.5, 0, -len)
        ..quadraticBezierTo(-width, -len * 0.5, 0, 0);
      canvas.drawPath(petal, paint);
      canvas.restore();
    }
    canvas.drawLine(Offset(size.width * 0.18, base.dy), Offset(size.width * 0.82, base.dy), paint);
  }

  @override
  bool shouldRepaint(_LotusPainter old) => old.color != color;
}
