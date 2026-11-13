import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../../app/router/routes.dart';
import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_text_styles.dart';
import '../../../../../core/widgets/status_pill.dart';
import '../../../application/dash_navigation.dart';
import '../../../application/providers/dashboard_providers.dart';
import '../../../domain/entities/dash_colors.dart';
import '../../../domain/entities/dashboard_models.dart';
import '../dash_area_trend.dart';
import '../dash_bars.dart';
import '../dash_donut.dart';
import '../dash_employee_row.dart';
import '../dash_kpi_card.dart';
import '../dash_section_card.dart';

/// The Helpdesk manager dashboard panel: KPIs, tickets-by-category bars, stacked
/// SLA + priority donuts, tickets needing attention, ticket-flow trend and
/// employee performance.
class HelpPanel extends ConsumerWidget {
  const HelpPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardDataProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashKpiGrid(
            kpis: data.helpKpis,
            // `period=1` → the tab's created window (see dashPeriodLink).
            onTapKpi: (k) =>
                dashGo(context, ref, dashPeriodLink(ref, k.route))),
        SizedBox(height: 16.h),
        DashSectionCard(
          title: 'Tickets by Category',
          subtitle: 'All tickets, this period',
          child: Padding(
            padding: EdgeInsets.only(top: 16.h),
            child: DashBars(
                bars: data.helpCategories,
                // A category bar opens Tickets on that category.
                // Tickets created in the period, of that category.
                onTapBar: (b) => dashGo(
                    context,
                    ref,
                    dashPeriodLink(
                        ref,
                        b.id.isEmpty
                            ? '${Routes.tickets}?all=1&period=1'
                            : '${Routes.tickets}?all=1&cat=${b.id}&period=1')),
                chartHeight: 122,
                labelFontSize: 11),
          ),
        ),
        SizedBox(height: 16.h),
        _slaPriority(context, data, ref),
        SizedBox(height: 16.h),
        _attention(context, ref, data.helpAttention),
        SizedBox(height: 16.h),
        _flowTrend(data),
        SizedBox(height: 16.h),
        _employees(context, ref, data.helpRoster),
      ],
    );
  }

  Widget _slaPriority(BuildContext context, DashboardData data, WidgetRef ref) {
    return DashSectionCard(
      title: 'SLA Status & Priority Mix',
      subtitle: 'Open & recent tickets',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 16.h),
          _centered('SLA Status'),
          DashDonut(
              parts: data.helpSla,
              // Each slice is an SLA bucket of the Tickets drawer.
              onTapPart: (p) =>
                  // Open tickets of the period in that SLA state.
                  dashGo(
                      context,
                      ref,
                      dashPeriodLink(ref,
                          '${Routes.tickets}?all=1&open=1&period=1${_slaQuery(p)}'))),
          Container(
              margin: EdgeInsets.only(top: 14.h, bottom: 2.h),
              height: 1,
              color: AppColors.borderCardSoft),
          SizedBox(height: 14.h),
          _centered('Priority Mix'),
          DashDonut(
              parts: data.helpPriority,
              // Priority names are the drawer's own option ids.
              onTapPart: (p) => dashGo(
                  context,
                  ref,
                  dashPeriodLink(ref,
                      '${Routes.tickets}?all=1&open=1&pri=${p.label}&period=1'))),
        ],
      ),
    );
  }

  /// The Tickets drawer's SLA bucket for a donut slice: Breached is the
  /// "Breaching" view the KPI also opens; the others are drawer radios.
  static String _slaQuery(DashDonutPart p) => switch (p.label.toLowerCase()) {
        'breached' => '&breaching=1',
        'at risk' => '&sla=risk',
        'within sla' => '&sla=ontrack',
        _ => '',
      };

  Widget _centered(String label) => Center(
        child: Text(label,
            style: AppText.custom(
                size: 13,
                weight: FontWeight.w700,
                color: AppColors.textSecondary)),
      );

  Widget _attention(
      BuildContext context, WidgetRef ref, List<DashTicketAttn> rows) {
    return DashSectionCard(
      title: 'Tickets Needing Attention',
      subtitle: 'Breached, paused & at-risk',
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 6.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 4.h),
          if (rows.isEmpty)
            // Webapp TicketsAttentionCard: "Nothing needs attention".
            Padding(
              padding: EdgeInsets.symmetric(vertical: 28.h),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsFill.checkCircle,
                        size: 28.sp, color: DashColors.green),
                    SizedBox(height: 8.h),
                    Text('Nothing needs attention',
                        style: AppText.custom(
                            size: 13.5,
                            weight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    SizedBox(height: 2.h),
                    Text('No breached, paused or at-risk tickets.',
                        style: AppText.custom(
                            size: 12,
                            weight: FontWeight.w500,
                            color: AppColors.textPlaceholder)),
                  ],
                ),
              ),
            ),
          for (final t in rows)
            DashHairlineRow(
              // The ticket itself (webapp `openTicket`); the list without an id.
              onTap: () => dashGo(
                  context,
                  ref,
                  t.issueId.isEmpty
                      ? '${Routes.tickets}?all=1'
                      : '${Routes.ticketDetail}?id=${t.issueId}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.tid,
                      style: AppText.custom(
                          size: 11.5,
                          weight: FontWeight.w700,
                          color: AppColors.textPlaceholder)),
                  SizedBox(height: 2.h),
                  Text(t.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(
                          size: 14,
                          weight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  SizedBox(height: 2.h),
                  Text(t.sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(
                          size: 12,
                          weight: FontWeight.w500,
                          color: AppColors.textMuted)),
                  SizedBox(height: 8.h),
                  Row(
                    children: [
                      _slaChip(t),
                      const Spacer(),
                      StatusPill(label: t.priority, color: t.priorityColor),
                    ],
                  ),
                ],
              ),
            ),
          DashViewMore(
              label: 'View all tickets',
              icon: PhosphorIconsBold.arrowRight,
              onTap: () => dashGo(context, ref, '${Routes.tickets}?all=1')),
        ],
      ),
    );
  }

  Widget _slaChip(DashTicketAttn t) {
    final IconData icon;
    final Color bg, fg;
    if (t.breached) {
      icon = PhosphorIconsFill.warning;
      bg = DashColors.tintRed;
      fg = DashColors.red;
    } else if (t.paused) {
      icon = PhosphorIconsFill.pause;
      bg = DashColors.chipGrey;
      fg = AppColors.textBodyMuted;
    } else {
      icon = PhosphorIconsRegular.clock;
      bg = DashColors.chipGrey;
      fg = AppColors.textBodyMuted;
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7.r)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11.sp, color: fg),
          SizedBox(width: 4.w),
          Text(t.slaLabel,
              style:
                  AppText.custom(size: 11, weight: FontWeight.w800, color: fg)),
        ],
      ),
    );
  }

  Widget _flowTrend(DashboardData data) {
    return DashSectionCard(
      title: 'Ticket Flow Trend',
      subtitle: 'Opened vs resolved',
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const DashTrendLegend(
              color: DashColors.red, label: 'Opened', dot: true),
          SizedBox(height: 4.h),
          const DashTrendLegend(
              color: DashColors.green, label: 'Resolved', dot: true),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(top: 12.h),
        child: DashAreaTrend(
          trend: data.helpFlow,
          colorA: DashColors.red, // opened
          colorB: DashColors.green, // resolved
          fillA: 0.16,
          fillB: 0.20,
          height: 104,
        ),
      ),
    );
  }

  Widget _employees(
      BuildContext context, WidgetRef ref, List<DashRosterRow> roster) {
    return DashSectionCard(
      title: 'Employee Performance',
      subtitle: 'Helpdesk workload across the team',
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 6.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 4.h),
          for (final e in roster)
            DashEmployeeRow(
              rid: e.rid,
              sub: e.sub,
              // That member's tickets (the row counts their open ones).
              onTap: () => dashGo(
                  context,
                  ref,
                  e.userId.isEmpty
                      ? '${Routes.tickets}?all=1'
                      : '${Routes.tickets}?all=1&assignee=${e.userId}'),
              trailing: DashStatChip(label: e.chipLabel, bad: e.chipBad),
            ),
          // Webapp `goReports`: the per-member figures live in Reports, which
          // every dashboard role can open (Members is admin-only).
          DashViewMore(
              label: 'View more',
              icon: PhosphorIconsBold.arrowDown,
              onTap: () => dashGo(context, ref, Routes.reports)),
        ],
      ),
    );
  }
}
