import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../../app/router/routes.dart';
import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_text_styles.dart';
import '../../../../../core/widgets/status_pill.dart';
import '../../../application/providers/dashboard_providers.dart';
import '../../../domain/entities/dash_colors.dart';
import '../../../domain/entities/dashboard_models.dart';
import '../dash_donut.dart';
import '../dash_employee_row.dart';
import '../dash_kpi_card.dart';
import '../dash_section_card.dart';
import '../dash_segmented.dart';

const _projTabs = [('all', 'All active'), ('risk', 'At risk'), ('overdue', 'Overdue')];

/// The Operations manager dashboard panel: KPIs, project-status donut, overdue
/// tasks (₹ Value / Days toggle), active projects (segment filter + progress)
/// and employee performance.
///
/// The two toggled sections (Overdue Tasks segment, Active Projects segment) are
/// their own [ConsumerWidget]s watching only their toggle provider + a `.select`
/// on their slice of the bundle, so a segment tap repaints just that section
/// rather than the whole panel (and its fl_chart donut).
class OpsPanel extends ConsumerWidget {
  const OpsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardDataProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashKpiGrid(kpis: data.opsKpis, onTapKpi: (k) => context.go(k.route)),
        SizedBox(height: 16.h),
        DashSectionCard(
          title: 'Project Status',
          subtitle: 'All projects, this period',
          child: DashDonut(
            parts: data.opsStatus,
            totalLabel: 'Total',
            totalValue: '${data.opsStatus.fold<int>(0, (a, p) => a + p.count)}',
            onTapPart: (_) => context.go(Routes.opsProjects),
          ),
        ),
        SizedBox(height: 16.h),
        const _OverdueTasksSection(),
        SizedBox(height: 16.h),
        const _ActiveProjectsSection(),
        SizedBox(height: 16.h),
        _employees(context, data.opsRoster),
      ],
    );
  }

  Widget _employees(BuildContext context, List<DashRosterRow> roster) {
    return DashSectionCard(
      title: 'Employee Performance',
      subtitle: 'Delivery workload across the team',
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 6.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 4.h),
          for (final e in roster)
            DashEmployeeRow(
              rid: e.rid,
              sub: e.sub,
              onTap: () => context.go(Routes.opsTasks),
              trailing: DashStatChip(label: e.chipLabel, bad: e.chipBad),
            ),
          DashViewMore(label: 'View more', icon: PhosphorIconsBold.arrowDown, onTap: () => context.go(Routes.members)),
        ],
      ),
    );
  }
}

/// Overdue Tasks — repaints only on its ₹/Days toggle or a change to
/// `opsOverdue`.
class _OverdueTasksSection extends ConsumerWidget {
  const _OverdueTasksSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(dashOpsValueModeProvider); // 0 = Value, 1 = Days
    final tasks = ref.watch(dashboardDataProvider.select((d) => d.opsOverdue));

    return DashSectionCard(
      title: 'Overdue Tasks',
      subtitle: 'Most overdue first',
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 6.r),
      trailing: DashSegmented(
        options: const ['₹ Value', 'Days'],
        selectedIndex: mode,
        onChanged: (i) => ref.read(dashOpsValueModeProvider.notifier).state = i,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 4.h),
          for (final t in tasks)
            DashHairlineRow(
              onTap: () => context.go(Routes.opsTasks),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                        SizedBox(height: 2.h),
                        Text(t.sub,
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
                      Text(mode == 0 ? t.value : t.overdue,
                          style: AppText.custom(
                              size: 12.5, weight: FontWeight.w800, color: mode == 0 ? AppColors.textPrimary : DashColors.red)),
                      SizedBox(height: 3.h),
                      Text(mode == 0 ? t.overdue : t.value,
                          style: AppText.custom(
                              size: 11, weight: mode == 0 ? FontWeight.w700 : FontWeight.w600,
                              color: mode == 0 ? DashColors.red : AppColors.textPlaceholder)),
                    ],
                  ),
                ],
              ),
            ),
          DashViewMore(label: 'View all tasks', icon: PhosphorIconsBold.arrowRight, onTap: () => context.go(Routes.opsTasks)),
        ],
      ),
    );
  }
}

/// Active Projects — repaints only on its segment filter or a change to
/// `opsProjects`.
class _ActiveProjectsSection extends ConsumerWidget {
  const _ActiveProjectsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(dashActiveProjTabProvider);
    final all = ref.watch(dashboardDataProvider.select((d) => d.opsProjects));

    final rows = all.where((p) {
      switch (tab) {
        case 'risk':
          return p.tab == 'onhold';
        case 'overdue':
          return p.tab == 'active' && p.days < 0;
        default:
          return p.tab == 'active';
      }
    }).toList();
    final tabIdx = _projTabs.indexWhere((t) => t.$1 == tab);

    return DashSectionCard(
      title: 'Active Projects',
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 6.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 10.h),
          DashSegmented(
            options: [for (final t in _projTabs) t.$2],
            selectedIndex: tabIdx < 0 ? 0 : tabIdx,
            onChanged: (i) => ref.read(dashActiveProjTabProvider.notifier).state = _projTabs[i].$1,
          ),
          SizedBox(height: 2.h),
          if (rows.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 24.h),
              child: Center(
                child: Text('No projects in this view.',
                    style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
              ),
            )
          else
            for (final p in rows) _projectRow(context, p),
          DashViewMore(label: 'View more', icon: PhosphorIconsBold.arrowDown, onTap: () => context.go(Routes.opsProjects)),
        ],
      ),
    );
  }

  Widget _projectRow(BuildContext context, DashProjectRow p) {
    return DashHairlineRow(
      onTap: () => context.go(Routes.opsProjects),
      padding: EdgeInsets.symmetric(vertical: 13.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 2.h),
                    Text(p.owner,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                  ],
                ),
              ),
              SizedBox(width: 10.w),
              Text(p.value, style: AppText.custom(size: 13.5, weight: FontWeight.w800, color: AppColors.textPrimary)),
            ],
          ),
          SizedBox(height: 9.h),
          Row(
            children: [
              StatusPill(label: p.statusLabel, color: p.statusColor),
              SizedBox(width: 9.w),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999.r),
                  child: LinearProgressIndicator(
                    value: (p.progress / 100).clamp(0.0, 1.0),
                    minHeight: 6.h,
                    backgroundColor: DashColors.track,
                    valueColor: AlwaysStoppedAnimation(p.statusColor),
                  ),
                ),
              ),
              SizedBox(width: 9.w),
              Text('${p.progress}%', style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: DashColors.textMid)),
              SizedBox(width: 9.w),
              _daysChip(p.days),
            ],
          ),
        ],
      ),
    );
  }

  Widget _daysChip(int days) {
    final bad = days < 0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: bad ? DashColors.tintRed : DashColors.tintGreen,
        borderRadius: BorderRadius.circular(7.r),
      ),
      child: Text('${days}d',
          style: AppText.custom(size: 11, weight: FontWeight.w800, color: bad ? DashColors.red : DashColors.green)),
    );
  }
}
