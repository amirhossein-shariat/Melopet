import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Placeholder Melopet logo (a paw inside a blood drop). Replace with the
/// real brand logo later — only this widget and the launcher icons change.
class MelopetLogo extends StatelessWidget {
  final double size;
  final bool withText;
  const MelopetLogo({super.key, this.size = 72, this.withText = false});

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: MP.brandGradient,
        borderRadius: BorderRadius.circular(size * .3),
        boxShadow: [BoxShadow(color: MP.pink.withValues(alpha: .5), blurRadius: size * .35, offset: Offset(0, size * .1))],
      ),
      child: CustomPaint(painter: _LogoPainter()),
    );
    if (!withText) return mark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(height: size * .18),
        Text(
          'ملوپت',
          style: TextStyle(fontSize: size * .36, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary),
        ),
        Text(
          'MELOPET VETERINARY LAB',
          style: TextStyle(
            fontSize: size * .12,
            letterSpacing: 2,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .55),
          ),
        ),
      ],
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final white = Paint()..color = Colors.white;
    // drop
    final drop = Path()
      ..moveTo(w * .5, w * .14)
      ..cubicTo(w * .5, w * .14, w * .22, w * .46, w * .22, w * .6)
      ..arcToPoint(Offset(w * .78, w * .6), radius: Radius.circular(w * .28), clockwise: false)
      ..cubicTo(w * .78, w * .46, w * .5, w * .14, w * .5, w * .14)
      ..close();
    canvas.drawPath(drop, white..color = Colors.white.withValues(alpha: .95));
    // paw
    final paw = Paint()..color = MP.pinkDeep;
    canvas.drawOval(Rect.fromCenter(center: Offset(w * .5, w * .68), width: w * .2, height: w * .16), paw);
    for (final a in [-.9, -.3, .3, .9]) {
      final dx = sin(a) * w * .15;
      final dy = -cos(a) * w * .13;
      canvas.drawCircle(Offset(w * .5 + dx, w * .61 + dy), w * .045, paw);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
