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
    this.emptyTitle,
    this.emptyHint,
    this.onTapBar,
  });

  /// Tapping a bar (column, count and label) — the funnel and category charts
  /// open the list filtered to that bar.
  final void Function(DashBar bar)? onTapBar;

  /// When set, an all-zero chart reads as an empty state (webapp
  /// `FunnelChart`) instead of a flat row of zero-height bars.
  final String? emptyTitle;
  final String? emptyHint;

  final List<DashBar> bars;
  final double chartHeight;
  final bool gradient; // funnel navy gradient vs solid navy
  final bool dimLast; // fade the last bar (Lost)
  final double maxBarWidth;
  final double labelFontSize;

  @override
  Widget build(BuildContext context) {
    final maxCount = bars.fold<int>(1, (m, b) => b.count > m ? b.count : m);
    if (emptyTitle != null &&
        (bars.isEmpty || bars.every((b) => b.count == 0))) {
      return SizedBox(
        height: chartHeight.h,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emptyTitle!,
                  textAlign: TextAlign.center,
                  style: AppText.custom(
                      size: 14,
                      weight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              if (emptyHint != null) ...[
                SizedBox(height: 3.h),
                Text(emptyHint!,
                    textAlign: TextAlign.center,
                    style: AppText.custom(
                        size: 12,
                        weight: FontWeight.w500,
                        color: AppColors.textPlaceholder)),
              ],
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: chartHeight.h,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (int i = 0; i < bars.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTapBar == null ? null : () => onTapBar!(bars[i]),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.w),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // 12,345 → 12.3K so a big count never breaks across the
                      // narrow column; scaled down as a last resort.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(_count(bars[i].count),
                            maxLines: 1,
                            style: AppText.custom(
                                size: 12,
                                weight: FontWeight.w700,
                                color: AppColors.textSecondary)),
                      ),
                      SizedBox(height: 6.h),
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor:
                                (bars[i].count / maxCount).clamp(0.06, 1.0),
                            child: Container(
                              constraints:
                                  BoxConstraints(maxWidth: maxBarWidth.w),
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(gradient ? 7.r : 7.r),
                                gradient: gradient
                                    ? const LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          DashColors.funnelTop,
                                          AppColors.navy
                                        ],
                                      )
                                    : null,
                                color: gradient ? null : AppColors.navy,
                              ),
                              foregroundDecoration: (dimLast &&
                                      i == bars.length - 1)
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
                      // One line, shrunk to fit: "Negotiation" used to break
                      // mid-word ("Negotiatio / n") in a narrow column.
                      SizedBox(
                        height: (labelFontSize * 1.4).h,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(bars[i].label,
                              maxLines: 1,
                              softWrap: false,
                              textAlign: TextAlign.center,
                              style: AppText.custom(
                                  size: labelFontSize,
                                  weight: FontWeight.w500,
                                  color: AppColors.textMuted,
                                  height: 1.15)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _count(int n) {
  if (n >= 1000000) return '${_trim(n / 1000000)}M';
  if (n >= 10000) return '${_trim(n / 1000)}K';
  return '$n';
}

String _trim(double v) {
  final t = v.toStringAsFixed(1);
  return t.endsWith('.0') ? t.substring(0, t.length - 2) : t;
}
