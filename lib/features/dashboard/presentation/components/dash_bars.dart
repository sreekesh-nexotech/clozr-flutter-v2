import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../domain/entities/dash_colors.dart';
import '../../domain/entities/dashboard_models.dart';

/// A row of vertical bars (Lead Funnel, Tickets by Category). The funnel uses a
/// navy top→bottom gradient with a dimmed final "Lost" bar; category bars are a
/// solid navy fill.
class DashBars extends StatelessWidget {
  const DashBars({
    super.key,
    required this.bars,
    required this.chartHeight,
    this.gradient = false,
    this.dimLast = false,
    this.maxBarWidth = 34,
    this.labelFontSize = 11,
  });

  final List<DashBar> bars;
  final double chartHeight;
  final bool gradient; // funnel navy gradient vs solid navy
  final bool dimLast; // fade the last bar (Lost)
  final double maxBarWidth;
  final double labelFontSize;

  @override
  Widget build(BuildContext context) {
    final maxCount = bars.fold<int>(1, (m, b) => b.count > m ? b.count : m);

    return SizedBox(
      height: chartHeight.h,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (int i = 0; i < bars.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 4.w),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${bars[i].count}',
                        style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textSecondary)),
                    SizedBox(height: 6.h),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: (bars[i].count / maxCount).clamp(0.06, 1.0),
                          child: Container(
                            constraints: BoxConstraints(maxWidth: maxBarWidth.w),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(gradient ? 7.r : 7.r),
                              gradient: gradient
                                  ? const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [DashColors.funnelTop, AppColors.navy],
                                    )
                                  : null,
                              color: gradient ? null : AppColors.navy,
                            ),
                            foregroundDecoration: (dimLast && i == bars.length - 1)
                                ? BoxDecoration(
                                    borderRadius: BorderRadius.circular(7.r),
                                    color: AppColors.white.withOpacity(0.45),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 6.h),
                    Text(bars[i].label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: AppText.custom(
                            size: labelFontSize, weight: FontWeight.w500, color: AppColors.textMuted, height: 1.15)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
