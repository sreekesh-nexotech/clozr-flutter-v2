import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../domain/entities/dashboard_models.dart';

/// A two-series filled area/line trend (Lead Inflow, Ticket Flow). Each series
/// is drawn as a straight polyline (matching the prototype's SVG path) with a
/// soft gradient fill below. Axis labels render underneath.
class DashAreaTrend extends StatelessWidget {
  const DashAreaTrend({
    super.key,
    required this.trend,
    required this.colorA,
    required this.colorB,
    this.fillA = 0.22,
    this.fillB = 0.26,
    this.height = 118,
  });

  final DashTrend trend;
  final Color colorA;
  final Color colorB;
  final double fillA;
  final double fillB;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height.h,
          child: CustomPaint(
            painter: _TrendPainter(trend, colorA, colorB, fillA, fillB),
            size: Size.infinite,
          ),
        ),
        SizedBox(height: 6.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final l in trend.axisLabels)
              Text(l, style: AppText.custom(size: 10.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
          ],
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.trend, this.colorA, this.colorB, this.fillA, this.fillB);
  final DashTrend trend;
  final Color colorA;
  final Color colorB;
  final double fillA;
  final double fillB;

  @override
  void paint(Canvas canvas, Size size) {
    _draw(canvas, size, trend.seriesA, colorA, fillA);
    _draw(canvas, size, trend.seriesB, colorB, fillB);
  }

  void _draw(Canvas canvas, Size size, List<double> values, Color color, double fill) {
    if (values.length < 2) return;
    final w = size.width, h = size.height;
    const topPad = 8.0, botPad = 8.0;
    final range = (trend.max - trend.min) == 0 ? 1 : (trend.max - trend.min);

    final pts = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final x = i * w / (values.length - 1);
      final norm = ((values[i] - trend.min) / range).clamp(0.0, 1.0);
      final y = topPad + (1 - norm) * (h - topPad - botPad);
      pts.add(Offset(x, y));
    }

    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      line.lineTo(pts[i].dx, pts[i].dy);
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
          colors: [color.withOpacity(fill), color.withOpacity(0)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => old.trend != trend;
}

/// A small legend swatch (line + label) for the trend charts.
class DashTrendLegend extends StatelessWidget {
  const DashTrendLegend({super.key, required this.color, required this.label, this.dot = false});
  final Color color;
  final String label;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot
            ? Container(width: 8.w, height: 8.w, decoration: BoxDecoration(color: color, shape: BoxShape.circle))
            : Container(
                width: 14.w,
                height: 3.h,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2.r)),
              ),
        SizedBox(width: dot ? 5.w : 6.w),
        Text(label, style: AppText.custom(size: dot ? 11 : 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
      ],
    );
  }
}
