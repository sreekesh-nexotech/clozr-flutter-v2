import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../../app/router/routes.dart';
import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_text_styles.dart';
import '../../../application/providers/dashboard_providers.dart';
import '../../../domain/entities/dash_colors.dart';
import '../../../domain/entities/dashboard_models.dart';
import '../attention_card.dart';
import '../dash_area_trend.dart';
import '../dash_bars.dart';
import '../dash_employee_row.dart';
import '../dash_kpi_card.dart';
import '../dash_section_card.dart';
import '../dash_segmented.dart';

const _stuckChips = [
  ('stale', 'Stale Leads'),
  ('quotes', 'Quotes'),
  ('payments', 'Payments'),
  ('wonnc', 'Won-NC'),
];

/// The CRM manager dashboard panel (team + period chips): KPIs, lead funnel,
/// lead-inflow trend, attention 2×2, lead sources, stuck items and employee
/// performance.
class CrmPanel extends ConsumerWidget {
  const CrmPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardDataProvider);
    final srcMode = ref.watch(dashSourceModeProvider);
    final stuckIdx = _stuckChips.indexWhere((c) => c.$1 == ref.watch(dashStuckChipProvider));
    final stuckKey = _stuckChips[stuckIdx < 0 ? 0 : stuckIdx].$1;
    final stuckRows = data.crmStuck[stuckKey] ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashKpiGrid(kpis: data.crmKpis, onTapKpi: (k) => context.go(k.route)),
        SizedBox(height: 16.h),
        DashSectionCard(
          title: 'Lead Funnel',
          subtitle: 'Lead stages across the pipeline',
          child: Padding(
            padding: EdgeInsets.only(top: 16.h),
            child: DashBars(bars: data.crmFunnel, chartHeight: 138, gradient: true, dimLast: true, labelFontSize: 10.5),
          ),
        ),
        SizedBox(height: 16.h),
        DashSectionCard(
          title: 'Lead Inflow trend',
          subtitle: 'Lead created vs Won lead',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 10.h),
              Row(
                children: [
                  const DashTrendLegend(color: DashColors.green, label: 'Lead Won'),
                  SizedBox(width: 16.w),
                  const DashTrendLegend(color: DashColors.blue, label: 'Lead created'),
                ],
              ),
              SizedBox(height: 10.h),
              DashAreaTrend(
                trend: data.crmInflow,
                colorA: DashColors.blue, // created
                colorB: DashColors.green, // won
                fillA: 0.22,
                fillB: 0.26,
                height: 118,
              ),
            ],
          ),
        ),
        SizedBox(height: 22.h),
        _attentionHeader(),
        SizedBox(height: 11.h),
        _attentionGrid(context, data.crmAttention),
        SizedBox(height: 16.h),
        _sources(context, data, srcMode, ref),
        SizedBox(height: 16.h),
        _stuck(context, stuckIdx < 0 ? 0 : stuckIdx, stuckRows, ref),
        SizedBox(height: 16.h),
        _employees(context, data.crmEmployees),
      ],
    );
  }

  Widget _attentionHeader() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 2.w),
      child: Row(
        children: [
          Icon(PhosphorIconsFill.warningCircle, size: 16.sp, color: DashColors.amber),
          SizedBox(width: 7.w),
          Text('Attention Needed', style: AppText.custom(size: 16, weight: FontWeight.w700, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _attentionGrid(BuildContext context, List<DashAttentionCard> cards) {
    return DashTwoColGrid(
      children: [for (final a in cards) AttentionCard(card: a, onTap: () => context.go(a.route))],
    );
  }

  Widget _sources(BuildContext context, DashboardData data, int mode, WidgetRef ref) {
    return DashSectionCard(
      title: 'Lead Sources',
      subtitle: 'Performance by source',
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 6.r),
      trailing: DashSegmented(
        options: const ['Leads', '₹ Value'],
        selectedIndex: mode,
        onChanged: (i) => ref.read(dashSourceModeProvider.notifier).state = i,
      ),
      child: Padding(
        padding: EdgeInsets.only(top: 4.h),
        child: Column(children: [for (final s in data.crmSources) _sourceRow(context, s, mode)]),
      ),
    );
  }

  Widget _sourceRow(BuildContext context, DashSource s, int mode) {
    final primary = mode == 1 ? s.closed : '${s.leads}';
    final primarySub = mode == 1 ? 'closed' : 'leads';
    return DashHairlineRow(
      onTap: () => context.go(Routes.leads),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(s.name, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    if (s.up != null) ...[
                      SizedBox(width: 7.w),
                      Container(
                        width: 20.w,
                        height: 20.w,
                        decoration: BoxDecoration(
                          color: s.up! ? DashColors.tintGreen : DashColors.tintRed,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(s.up! ? PhosphorIconsBold.arrowUp : PhosphorIconsBold.arrowDown,
                            size: 10.sp, color: s.up! ? DashColors.green : DashColors.red),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 3.h),
                Text(s.metaLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
              ],
            ),
          ),
          SizedBox(width: 10.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(primary, style: AppText.custom(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
              SizedBox(height: 2.h),
              Text(primarySub, style: AppText.custom(size: 10.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stuck(BuildContext context, int idx, List<DashStuckRow> rows, WidgetRef ref) {
    return DashSectionCard(
      title: 'Stuck Items',
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 6.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 12.h),
          DashChipRow(
            labels: [for (final c in _stuckChips) c.$2],
            selectedIndex: idx,
            onChanged: (i) => ref.read(dashStuckChipProvider.notifier).state = _stuckChips[i].$1,
          ),
          SizedBox(height: 2.h),
          if (rows.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 24.h),
              child: Center(
                child: Text('Nothing stuck here.',
                    style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
              ),
            )
          else
            for (final r in rows)
              DashHairlineRow(
                onTap: () => context.go(Routes.leads),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                          SizedBox(height: 2.h),
                          Text(r.sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                        ],
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(r.amt, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                        SizedBox(height: 3.h),
                        Text(r.age, style: AppText.custom(size: 11, weight: FontWeight.w700, color: DashColors.red)),
                      ],
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _employees(BuildContext context, List<DashCrmEmployee> emps) {
    return DashSectionCard(
      title: 'Employee performance',
      subtitle: 'Team activity this period',
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 4.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 4.h),
          for (final e in emps)
            DashEmployeeRow(
              rid: e.rid,
              sub: e.metaLine,
              onTap: () => context.go(Routes.members),
              trailing: DashTrailingValue(primary: e.closed, caption: e.last),
            ),
          DashViewMore(label: 'View more', icon: PhosphorIconsBold.arrowDown, onTap: () => context.go(Routes.members)),
        ],
      ),
    );
  }
}
