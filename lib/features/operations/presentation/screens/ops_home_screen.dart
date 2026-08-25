import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/kpi_card.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/segmented_control.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../auth/application/providers/auth_providers.dart';
import '../../application/providers/ops_dashboard_providers.dart';
import '../../application/providers/ops_tasks_providers.dart';
import '../../application/providers/projects_providers.dart';
import '../../domain/entities/ops_kpis.dart';
import '../../domain/entities/ops_task.dart';
import '../../domain/entities/project.dart';

/// Operations Home — the staff dashboard: a 2×2 KPI grid, a sortable "My Tasks"
/// list, a "Top Tasks Needing Attention" list and a completed-by-priority grid.
class OpsHomeScreen extends ConsumerWidget {
  const OpsHomeScreen({super.key});

  /// Sort order for the Priority segment.
  ///
  /// `Urgent` belongs here: [priorityKey] folds the API's "urgent"/"critical"
  /// into it, and the org's own catalog uses it. It was missing, and the sort
  /// looked its rank up with `!` — so choosing Priority with a single urgent
  /// task assigned to you threw a null-check error mid-build and took the whole
  /// dashboard down with it.
  static const _priRank = {'Urgent': 0, 'High': 1, 'Medium': 2, 'Low': 3};

  /// A priority's rank, with anything unrecognised sorted last rather than
  /// crashing — the catalog is the org's to change.
  static int _rankOf(String priority) => _priRank[priority] ?? _priRank.length;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(opsTasksProvider);
    final projectsAsync = ref.watch(projectsProvider);
    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          _header(),
          Expanded(child: _content(context, ref, tasksAsync, projectsAsync)),
        ],
      ),
    );
  }

  /// Gates the dashboard on both sources: a skeleton while either loads and an
  /// error state (with retry) if either fails, rather than a dashboard of zeros.
  Widget _content(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<OpsTask>> tasksAsync,
    AsyncValue<List<Project>> projectsAsync,
  ) {
    if (tasksAsync.isLoading || projectsAsync.isLoading) {
      return const ListSkeleton();
    }
    final err = tasksAsync.hasError
        ? tasksAsync.error
        : (projectsAsync.hasError ? projectsAsync.error : null);
    if (err != null) {
      final appErr = err is AppError
          ? err
          : const AppError(type: AppErrorType.unknown, message: 'Something went wrong. Please try again.');
      return ErrorState.forError(appErr, onRetry: () {
        ref.invalidate(opsTasksProvider);
        ref.invalidate(projectsProvider);
      });
    }

    final tasks = ref.watch(opsTasksListProvider);
    final projects = ref.watch(allProjectsProvider);
    final sort = ref.watch(opsSortProvider);

    final mineAll = tasks.where((t) => t.isMine).toList();
    final open = mineAll.where((t) => t.status == 'open' || t.status == 'working' || t.status == 'review').toList();
    final done = mineAll.where((t) => t.status == 'completed').toList();
    final total = mineAll.where((t) => t.status != 'cancelled').toList();
    final overdue = open.where((t) => taskDueDelta(t) < 0).toList();
    // Server-scoped (`ownership=me`) and counted as "still live", not "folds to
    // exactly `active`". Filtering the org-wide list on `isMine` here counted
    // only projects you *manage* whose status happened to fold to `active` —
    // `?view=list` strips `assignees`, so being on the team never registered.
    final activeProj = ref.watch(myOpenProjectsProvider);
    final donePct = total.isEmpty ? 0.0 : done.length / total.length;

    String projName(String id) =>
        projects.where((p) => p.id == id).map((p) => p.name).firstOrNull ?? 'No project';

    final myTasks = open.toList()
      ..sort((a, b) {
        if (sort == 'due') return a.endISO.compareTo(b.endISO);
        final r = _rankOf(a.pri).compareTo(_rankOf(b.pri));
        return r != 0 ? r : a.endISO.compareTo(b.endISO);
      });
    final attn = open.toList()..sort((a, b) => a.endISO.compareTo(b.endISO));

    void goTasks({String tab = 'all'}) {
      ref.read(myTasksFProvider.notifier).state = true;
      ref.read(otTabProvider.notifier).state = tab;
      context.go(Routes.opsTasks);
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
      children: [
        _kpiGrid(
          active: activeProj.length,
          overdue: overdue.length,
          done: done.length,
          total: total.length,
          donePct: donePct,
          // Trends and the cycle time come from the server or not at all — see
          // [opsKpisProvider]. Counts stay local so the grid never blanks.
          kpis: ref.watch(opsKpisProvider).valueOrNull,
          onActive: () {
            ref.read(myProjectsProvider.notifier).state = true;
            ref.read(projTabProvider.notifier).state = 'active';
            context.go(Routes.opsProjects);
          },
          onOverdue: () => goTasks(),
          onCompleted: () => goTasks(tab: 'completed'),
        ),
        SizedBox(height: 16.h),
        _myTasksCard(context, ref, myTasks, sort, projName, () => goTasks()),
        SizedBox(height: 16.h),
        _attnCard(context, attn, projName),
        SizedBox(height: 16.h),
        _gridCard(
          done,
          ref.watch(opsCompletedGridProvider).valueOrNull ?? const [],
          () => goTasks(tab: 'completed'),
        ),
      ],
    );
  }

  Widget _header() {
    return Container(
      padding: EdgeInsets.fromLTRB(18.w, 56.h, 18.w, 12.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: Column(
        children: [
          const AppHeaderBar(),
          SizedBox(height: 16.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Operations', style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                    SizedBox(height: 1.h),
                    Text('Dashboard', style: AppText.screenTitle()),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(bottom: 3.h),
                // Today, from the device clock. This was the literal string
                // "Thu, 9 Jul" — the prototype's frozen date, which read as
                // stale on every other day of the year.
                child: Text(DateFormat('EEE, d MMM').format(DateTime.now()),
                    style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The KPI grid.
  ///
  /// Counts are derived from the task and project lists this screen already
  /// loads. [kpis] adds what those lists cannot answer: the period-over-period
  /// trend on each card, and the average task cycle — which needs completion
  /// timestamps the task rows do not carry. Null (mock mode, still loading, or
  /// a 403 for a user without `view_dashboard`) simply means no chip and no
  /// cycle figure, rather than a placeholder standing in for one.
  Widget _kpiGrid({
    required int active,
    required int overdue,
    required int done,
    required int total,
    required double donePct,
    required OpsKpis? kpis,
    required VoidCallback onActive,
    required VoidCallback onOverdue,
    required VoidCallback onCompleted,
  }) {
    final cycle = kpis?.avgTaskCycle;
    final cycleDays = cycle?.days;
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: KpiCard(
                  icon: PhosphorIconsFill.briefcase,
                  iconColor: AppColors.success,
                  iconBg: AppColors.tintGreen,
                  value: '$active',
                  label: 'My Active Projects',
                  sub: "Projects I'm part of",
                  accent: AppColors.success,
                  trend: kpis?.activeProjects?.trendLabel,
                  trendUp: kpis?.activeProjects?.trendUp ?? true,
                  onTap: onActive,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: KpiCard(
                  icon: PhosphorIconsFill.warningCircle,
                  iconColor: AppColors.error,
                  iconBg: AppColors.tintRed,
                  value: '$overdue',
                  label: 'My Overdue Tasks',
                  sub: 'Past their due date',
                  accent: AppColors.error,
                  trend: kpis?.tasksOverdue?.trendLabel,
                  // More overdue tasks is worse, so the pill's colour is the
                  // inverse of the direction the arrow points.
                  trendUp: !(kpis?.tasksOverdue?.trendUp ?? true),
                  arrowUp: kpis?.tasksOverdue?.trendUp ?? false,
                  onTap: onOverdue,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12.h),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: KpiCard(
                  icon: PhosphorIconsFill.listChecks,
                  iconColor: AppColors.blueBright,
                  iconBg: AppColors.blueSubtle,
                  value: '$done / $total',
                  label: 'Tasks Completed',
                  sub: 'All my tasks, this period',
                  accent: AppColors.blueBright,
                  // No trend chip: §1 carries no completed-tasks figure, and
                  // the ratio beside it is already the whole story.
                  progress: donePct,
                  onTap: onCompleted,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: KpiCard(
                  icon: PhosphorIconsFill.clock,
                  iconColor: AppColors.success,
                  iconBg: AppColors.tintGreen,
                  // The server's figure or nothing: a cycle time needs the
                  // completion timestamps the task list does not return, so
                  // this was a constant standing in for a measurement.
                  value: cycleDays == null ? '—' : _trimDays(cycleDays),
                  unit: cycleDays == null ? null : 'days',
                  label: 'My Avg Task Cycle',
                  sub: 'Median completion time',
                  accent: AppColors.success,
                  trend: cycle?.trendLabel,
                  // A shorter cycle is better, so falling is the good direction.
                  trendUp: !(cycle?.trendUp ?? true),
                  arrowUp: cycle?.trendUp ?? false,
                  onTap: onCompleted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The My Tasks sub-label. Falls back to the bare "Open tasks" rather than a
  /// placeholder name when there is no session (mock mode).
  static String _openTasksFor(WidgetRef ref) {
    final name = ref.watch(sessionControllerProvider).user?.fullName.trim() ?? '';
    return name.isEmpty ? 'Open tasks' : 'Open tasks · $name';
  }

  /// "3.2" rather than "3.2 days" → "3" when the figure is whole.
  static String _trimDays(double days) =>
      days == days.roundToDouble() ? days.round().toString() : days.toStringAsFixed(1);

  Widget _myTasksCard(BuildContext context, WidgetRef ref, List<OpsTask> rows, String sort,
      String Function(String) projName, VoidCallback onViewMore) {
    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 4.h),
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
                    Text('My Tasks', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 1.h),
                    // The signed-in user, not the prototype's seed name — this
                    // card is "my tasks", so it named the wrong person for
                    // everyone but him.
                    Text(_openTasksFor(ref), style: AppText.caption(color: AppColors.textPlaceholder)),
                  ],
                ),
              ),
              SegmentedControl(
                options: const ['Priority', 'Due'],
                selectedIndex: sort == 'due' ? 1 : 0,
                onChanged: (i) => ref.read(opsSortProvider.notifier).state = i == 1 ? 'due' : 'priority',
              ),
            ],
          ),
          SizedBox(height: 4.h),
          if (rows.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 26.h),
              child: Center(
                child: Text("No open tasks — you're all caught up.",
                    style: AppText.captionStrong(color: AppColors.textPlaceholder)),
              ),
            )
          else
            for (final t in rows) _myTaskRow(context, t, projName),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onViewMore,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 13.h),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('View more', style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.blueBright)),
                  SizedBox(width: 6.w),
                  Icon(PhosphorIconsBold.arrowDown, size: 12.sp, color: AppColors.blueBright),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _myTaskRow(BuildContext context, OpsTask t, String Function(String) projName) {
    final delta = taskDueDelta(t);
    final overdue = delta < 0;
    final priColor = StatusMeta$.projectPriority[t.pri] ?? AppColors.textMuted;
    final meta = StatusMeta$.opsTask[t.status] ?? StatusMeta$.opsTask['open']!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('${Routes.opsTaskDetail}?id=${t.id}'),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
            SizedBox(height: 2.h),
            Text(projName(t.projId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption(color: AppColors.textPlaceholder)),
            SizedBox(height: 8.h),
            Row(
              children: [
                StatusPill(label: t.pri, color: priColor),
                SizedBox(width: 9.w),
                Text('Due ${t.end.replaceAll(' 2026', '')}',
                    style: AppText.custom(
                        size: 12,
                        weight: overdue ? FontWeight.w700 : FontWeight.w600,
                        color: overdue ? AppColors.error : AppColors.textMuted2)),
                const Spacer(),
                StatusPill.meta(meta),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _attnCard(BuildContext context, List<OpsTask> rows, String Function(String) projName) {
    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 6.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Top Tasks Needing Attention',
              style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 1.h),
          Text('Closest due dates first', style: AppText.caption(color: AppColors.textPlaceholder)),
          SizedBox(height: 4.h),
          for (final t in rows) _attnRow(context, t, projName),
        ],
      ),
    );
  }

  Widget _attnRow(BuildContext context, OpsTask t, String Function(String) projName) {
    final d = taskDueDelta(t);
    final priColor = StatusMeta$.projectPriority[t.pri] ?? AppColors.textMuted;
    final (Color bg, Color fg) = d < 0
        ? (AppColors.tintRed, AppColors.error)
        : (d <= 3 ? (AppColors.tintAmber, AppColors.warningDeep) : (AppColors.tintGreen, AppColors.success));
    final label = d < 0 ? '${-d}d over' : (d == 0 ? 'Today' : '${d}d');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('${Routes.opsTaskDetail}?id=${t.id}'),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  SizedBox(height: 2.h),
                  Text(projName(t.projId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption(color: AppColors.textPlaceholder)),
                ],
              ),
            ),
            SizedBox(width: 10.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusPill(label: t.pri, color: priColor),
                SizedBox(height: 5.h),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7.r)),
                  child: Text(label, style: AppText.custom(size: 11, weight: FontWeight.w800, color: fg)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Completed tasks by priority, split by whether they landed before or after
  /// their due date.
  ///
  /// [rows] is the server's own split. When it is unavailable the same split is
  /// derived from [done] via [OpsTask.completedLate] — which is only possible
  /// now that the task mapper reads `act_end_date`. Before that, this card put
  /// every completed task in BEFORE DUE and a hard-coded zero in AFTER DUE.
  Widget _gridCard(
    List<OpsTask> done,
    List<OpsCompletedRow> rows,
    VoidCallback onRow,
  ) {
    final grid = rows.isNotEmpty
        ? rows
        : [
            // The server names the priorities it knows; falling back, the three
            // the task list uses are all there are to count.
            for (final pri in const ['High', 'Medium', 'Low'])
              OpsCompletedRow(
                priority: pri,
                beforeDue: done
                    .where((t) => t.pri == pri && t.completedLate != true)
                    .length,
                afterDue: done
                    .where((t) => t.pri == pri && t.completedLate == true)
                    .length,
              ),
          ];
    return _gridCardBody(grid, onRow);
  }

  Widget _gridCardBody(List<OpsCompletedRow> grid, VoidCallback onRow) {
    Widget headCell(String label, {TextAlign align = TextAlign.start}) => Text(label,
        textAlign: align,
        style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.6));

    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tasks Completed Grid',
              style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 1.h),
          Text('By priority, this period', style: AppText.caption(color: AppColors.textPlaceholder)),
          SizedBox(height: 14.h),
          Container(
            padding: EdgeInsets.only(bottom: 9.h),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
            child: Row(
              children: [
                Expanded(child: headCell('PRIORITY')),
                SizedBox(width: 82.w, child: headCell('BEFORE DUE', align: TextAlign.center)),
                SizedBox(width: 82.w, child: headCell('AFTER DUE', align: TextAlign.center)),
              ],
            ),
          ),
          for (final row in grid) _gridRow(row, onRow),
        ],
      ),
    );
  }

  Widget _gridRow(OpsCompletedRow row, VoidCallback onTap) {
    final pri = row.priority;
    final priColor = StatusMeta$.projectPriority[pri] ?? AppColors.textMuted;
    Widget badge(int n, {required bool bad}) => Container(
          width: 26.w,
          height: 26.w,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bad ? AppColors.tintRed : AppColors.tintGreen,
            shape: BoxShape.circle,
          ),
          child: Text('$n', style: AppText.custom(size: 12, weight: FontWeight.w800, color: bad ? AppColors.error : AppColors.success)),
        );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10.h),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
        child: Row(
          children: [
            Expanded(child: Align(alignment: Alignment.centerLeft, child: StatusPill(label: pri, color: priColor))),
            SizedBox(width: 82.w, child: Center(child: badge(row.beforeDue, bad: false))),
            SizedBox(width: 82.w, child: Center(child: badge(row.afterDue, bad: true))),
          ],
        ),
      ),
    );
  }
}
