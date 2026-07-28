import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../domain/entities/dash_colors.dart';
import '../../domain/entities/dashboard_models.dart';

/// A donut chart (fl_chart PieChart with a centre hole) over a grey track, plus
/// a legend of dot + label + count rows. Optionally a bold "Total" row with a
/// top hairline (project-status donut). Legend rows can be tapped.
class DashDonut extends StatelessWidget {
  const DashDonut({
    super.key,
    required this.parts,
    this.totalLabel,
    this.totalValue,
    this.onTapPart,
  });

  final List<DashDonutPart> parts;
  final String? totalLabel;
  final String? totalValue;
  final void Function(DashDonutPart part)? onTapPart;

  @override
  Widget build(BuildContext context) {
    final visible = parts.where((p) => p.count > 0).toList();
    final total = visible.fold<int>(0, (a, p) => a + p.count);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 14.h),
        Center(
          child: SizedBox(
            width: 148.w,
            height: 148.w,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Grey track behind the arcs.
                SizedBox(
                  width: 132.w,
                  height: 132.w,
                  child: PieChart(PieChartData(
                    sectionsSpace: 0,
                    centerSpaceRadius: 42.r,
                    startDegreeOffset: -90,
                    sections: [
                      PieChartSectionData(value: 1, color: DashColors.track, radius: 24.r, showTitle: false),
                    ],
                  )),
                ),
                SizedBox(
                  width: 132.w,
                  height: 132.w,
                  child: PieChart(PieChartData(
                    sectionsSpace: total == 0 ? 0 : 1.4,
                    centerSpaceRadius: 42.r,
                    startDegreeOffset: -90,
                    sections: [
                      for (final p in visible)
                        PieChartSectionData(
                          value: p.count.toDouble(),
                          color: p.color,
                          radius: 24.r,
                          showTitle: false,
                        ),
                    ],
                  )),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 6.h),
        for (final p in parts)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTapPart == null ? null : () => onTapPart!(p),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 7.h, horizontal: 2.w),
              child: Row(
                children: [
                  Container(
                    width: 9.w,
                    height: 9.w,
                    decoration: BoxDecoration(color: p.color, shape: BoxShape.circle),
                  ),
                  SizedBox(width: 9.w),
                  Expanded(
                    child: Text(p.label,
                        style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textBodyMuted)),
                  ),
                  Text('${p.count}',
                      style: AppText.custom(size: 13.5, weight: FontWeight.w800, color: AppColors.textPrimary)),
                ],
              ),
            ),
          ),
        if (totalLabel != null)
          Container(
            margin: EdgeInsets.only(top: 4.h),
            padding: EdgeInsets.fromLTRB(2.w, 10.h, 2.w, 3.h),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.bgLight, width: 1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(totalLabel!,
                      style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
                Text(totalValue ?? '$total',
                    style: AppText.custom(size: 13.5, weight: FontWeight.w800, color: AppColors.textPrimary)),
              ],
            ),
          ),
      ],
    );
  }
}
