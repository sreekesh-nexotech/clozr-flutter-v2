import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/sparkline.dart';
import '../../domain/entities/dash_colors.dart';
import '../../domain/entities/dashboard_models.dart';

/// A dashboard KPI card. Unlike the core [KpiCard], the trend pill's colour
/// (green/red via [DashKpi.trendPositive]) is decoupled from its arrow
/// direction ([DashKpi.arrow]) — the prototype mixes them (e.g. an "up" green
/// pill with a down arrow). Renders a bleeding sparkline or a progress bar.
class DashKpiCard extends StatelessWidget {
  const DashKpiCard({super.key, required this.kpi, this.onTap});
  final DashKpi kpi;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasSpark = kpi.spark != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.hardEdge,
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
            Padding(
              padding: EdgeInsets.fromLTRB(14.r, 14.r, 14.r, hasSpark ? 8.h : 14.r),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 30.w,
                        height: 30.w,
                        decoration: BoxDecoration(color: kpi.iconBg, borderRadius: BorderRadius.circular(9.r)),
                        child: Icon(kpi.icon, size: 16.sp, color: kpi.accent),
                      ),
                      _trendPill(),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(kpi.value,
                          style: AppText.custom(size: 25, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.6)),
                      if (kpi.unit.isNotEmpty) ...[
                        SizedBox(width: 3.w),
                        Text(kpi.unit, style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                      ],
                    ],
                  ),
                  SizedBox(height: 2.h),
                  Text(kpi.label, style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textBodyMuted)),
                  SizedBox(height: 1.h),
                  Text(kpi.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.micro()),
                  if (kpi.progress != null)
                    Padding(
                      padding: EdgeInsets.only(top: 15.h),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999.r),
                        child: LinearProgressIndicator(
                          value: kpi.progress,
                          minHeight: 7.h,
                          backgroundColor: AppColors.borderCardSoft,
                          valueColor: AlwaysStoppedAnimation(kpi.accent),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (hasSpark)
              SizedBox(
                height: 30.h,
                width: double.infinity,
                child: Sparkline(values: kpi.spark!, color: kpi.accent, height: 30.h),
              ),
          ],
        ),
      ),
    );
  }

  Widget _trendPill() {
    final positive = kpi.trendPositive;
    final icon = switch (kpi.arrow) {
      DashTrendArrow.up => PhosphorIconsBold.arrowUp,
      DashTrendArrow.down => PhosphorIconsBold.arrowDown,
      DashTrendArrow.flat => PhosphorIconsBold.arrowRight,
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: positive ? DashColors.tintGreen : DashColors.tintRed,
        borderRadius: BorderRadius.circular(7.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11.sp, color: positive ? DashColors.green : DashColors.red),
          SizedBox(width: 3.w),
          Text(kpi.trend,
              style: AppText.custom(size: 11, weight: FontWeight.w700, color: positive ? DashColors.green : DashColors.red)),
        ],
      ),
    );
  }
}

/// The 2×2 KPI grid shared by all four panels.
class DashKpiGrid extends StatelessWidget {
  const DashKpiGrid({super.key, required this.kpis, required this.onTapKpi});
  final List<DashKpi> kpis;
  final void Function(DashKpi kpi) onTapKpi;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final gap = 12.w;
        final w = (c.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final k in kpis)
              SizedBox(width: w, child: DashKpiCard(kpi: k, onTap: () => onTapKpi(k))),
          ],
        );
      },
    );
  }
}
