import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';

/// One donut slice.
class DonutSegment {
  final double value;
  final Color color;
  const DonutSegment(this.value, this.color);
}

/// A thick-ring donut matching the prototype's SVG donuts (r44 / stroke20 on a
/// 120 viewBox): a soft grey track under proportional coloured arcs starting at
/// 12 o'clock. Zero-total renders just the track.
class DonutChart extends StatelessWidget {
  const DonutChart({super.key, required this.segments, required this.size});

  final List<DonutSegment> segments;
  final double size; // already scaled (e.g. 148.w)

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _DonutPainter(segments)),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.segments);
  final List<DonutSegment> segments;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final radius = s * 44 / 120;
    final stroke = s * 20 / 120;
    final center = Offset(s / 2, s / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = AppColors.borderCardSoft,
    );

    final total = segments.fold<double>(0, (a, b) => a + b.value);
    if (total <= 0) return;

    var start = -math.pi / 2;
    for (final seg in segments) {
      if (seg.value <= 0) continue;
      final sweep = seg.value / total * 2 * math.pi;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = seg.color,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.segments != segments;
}
