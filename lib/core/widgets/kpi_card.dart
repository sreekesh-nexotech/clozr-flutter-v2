import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import 'sparkline.dart';

/// A dashboard KPI card: icon chip + trend pill, big number + unit, label,
/// sub-label and a bleeding sparkline at the bottom. Used across CRM Home and
/// the manager dashboards (2×2 grid).
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.value,
    required this.label,
    required this.sub,
    required this.accent,
    this.unit,
    this.trend,
    this.trendUp = true,
    this.spark,
    this.progress,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String value;
  final String label;
  final String sub;
  final Color accent;
  final String? unit;
  final String? trend;
  final bool trendUp;
  final List<double>? spark;
  final double? progress; // 0..1 → renders a progress bar instead of a sparkline
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(14.r),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: AppColors.borderCardSoft),
          boxShadow: [
            BoxShadow(color: const Color(0xFF101828).withOpacity(0.04), blurRadius: 2, offset: const Offset(0, 1)),
            BoxShadow(color: const Color(0xFF101828).withOpacity(0.05), blurRadius: 24, offset: const Offset(0, 10)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 34.w,
                  height: 34.w,
                  decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10.r)),
                  child: Icon(icon, size: 18.sp, color: iconColor),
                ),
                if (trend != null) _trendPill(),
              ],
            ),
            SizedBox(height: 12.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: AppText.kpiNumber()),
                if (unit != null) ...[
                  SizedBox(width: 3.w),
                  Text(unit!, style: AppText.captionStrong(color: AppColors.textPlaceholder)),
                ],
              ],
            ),
            SizedBox(height: 2.h),
            Text(label, style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textBodyMuted)),
            SizedBox(height: 1.h),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.micro()),
            SizedBox(height: 8.h),
            if (progress != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(999.r),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7.h,
                  backgroundColor: AppColors.borderCardSoft,
                  valueColor: AlwaysStoppedAnimation(accent),
                ),
              )
            else if (spark != null)
              Padding(
                padding: EdgeInsets.only(top: 0),
                child: Sparkline(values: spark!, color: accent, height: 30.h),
              ),
          ],
        ),
      ),
    );
  }

  Widget _trendPill() {
    final up = trendUp;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: up ? AppColors.tintGreen : AppColors.tintRed,
        borderRadius: BorderRadius.circular(7.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? PhosphorIconsBold.arrowUp : PhosphorIconsBold.arrowDown,
              size: 11.sp, color: up ? AppColors.success : AppColors.error),
          SizedBox(width: 3.w),
          Text(trend!,
              style: AppText.custom(size: 11, weight: FontWeight.w700, color: up ? AppColors.success : AppColors.error)),
        ],
      ),
    );
  }
}
