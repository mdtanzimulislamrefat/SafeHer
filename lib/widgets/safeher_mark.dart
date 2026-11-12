import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The SafeHer mark: her (the amber dot) held by her circle of three.
/// Same geometry as tool/brand/make_brand.py, drawn in code so it is sharp at any size.
class SafeHerMark extends StatelessWidget {
  const SafeHerMark({super.key, this.size = 32, this.ring = SafeColors.plum, this.dot = SafeColors.amberMark});

  final double size;
  final Color ring;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'SafeHer',
      image: true,
      child: CustomPaint(size: Size.square(size), painter: _MarkPainter(ring, dot)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.ring, this.dot);

  final Color ring;
  final Color dot;

  // In a box where the ring's outer edge has radius 1: ring radius, stroke and dot radius.
  static const _r = 300 / 337, _stroke = 74 / 337, _dot = 118 / 337, _span = 84.0;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final unit = size.shortestSide / 2;
    final paint = Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke * unit
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: c, radius: _r * unit);
    for (final centre in const [-90.0, 30.0, 150.0]) {
      canvas.drawArc(rect, _rad(centre - _span / 2), _rad(_span), false, paint);
    }
    canvas.drawCircle(c, _dot * unit, Paint()..color = dot);
  }

  static double _rad(double deg) => deg * math.pi / 180;

  @override
  bool shouldRepaint(_MarkPainter old) => old.ring != ring || old.dot != dot;
}

/// Mark + "SafeHer" wordmark, for the Home header.
class SafeHerLogo extends StatelessWidget {
  const SafeHerLogo({super.key, this.height = 28});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SafeHerMark(size: height),
        SizedBox(width: height * 0.36),
        ExcludeSemantics(
          child: Text('SafeHer', style: SafeText.heading(height * 0.78, color: SafeColors.plum)),
        ),
      ],
    );
  }
}
