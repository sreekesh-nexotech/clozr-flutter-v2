import 'package:flutter/material.dart';

/// A smooth area sparkline (Catmull-Rom → cubic bezier), matching the
/// prototype's `sparkPaths()` SVG generator: filled gradient under a 2px line.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 30,
    this.strokeWidth = 2,
  });

  final List<double> values;
  final Color color;
  final double height;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SparkPainter(values, color, strokeWidth)),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, this.strokeWidth);
  final List<double> values;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    const pad = 3.0;
    final w = size.width, h = size.height;
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV) == 0 ? 1 : (maxV - minV);

    final pts = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final x = pad + i * (w - 2 * pad) / (values.length - 1);
      final y = h - pad - ((values[i] - minV) / range) * (h - 2 * pad - 2);
      pts.add(Offset(x, y));
    }

    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = i > 0 ? pts[i - 1] : pts[i];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
      final c1 = Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
      final c2 = Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
      line.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }

    final area = Path.from(line)
      ..lineTo(pts.last.dx, h)
      ..lineTo(pts.first.dx, h)
      ..close();

    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.26), color.withOpacity(0)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.values != values || old.color != color;
}
