import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../application/providers/lms_providers.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/lms_activity.dart';
import '../../domain/lms_logic.dart';
import '../components/lms_course_card.dart';
import '../components/lms_footer.dart';
import '../components/lms_header.dart';

/// Webapp `TrainingDashboardScreen`: the "Overview" heading, four KPI tiles
/// from `/lms/dashboard/stats/`, every course with a role filter, recent
/// activity and the New course action.
class LmsOverviewScreen extends ConsumerStatefulWidget {
  const LmsOverviewScreen({super.key});

  @override
  ConsumerState<LmsOverviewScreen> createState() => _LmsOverviewScreenState();
}

class _LmsOverviewScreenState extends ConsumerState<LmsOverviewScreen> {
  /// The All Courses role filter — 'all' or a role name. Client-side only.
  String _aud = 'all';

  @override
  void initState() {
    super.initState();
    // Figures are cached for the session, so a course published on the web
    // since the last visit would read stale — reload every time the screen
    // opens (after the first frame: invalidating inside initState crashes).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) reloadLms(ref);
    });
  }

  /// Pull-to-refresh: stats, courses, learner records and the activity feed.
  Future<void> _refresh() async {
    ref.invalidate(lmsStatsProvider);
    await settle([
      ref.read(lmsStatsProvider.future),
      ref.read(lmsCoursesControllerProvider.notifier).reload(),
      ref.read(lmsRecordsControllerProvider.notifier).reload(),
      ref.read(lmsActivityControllerProvider.notifier).reload(),
    ]);
  }

  void _openCourse(BuildContext context, Course c) {
    // Published or platform → detail; a tenant draft → the editor.
    if (c.isPublished || c.isGlobal) {
      context.push('${Routes.lmsCourseDetail}?id=${c.id}');
    } else {
      context.push('${Routes.lmsBuilder}?id=${c.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final courses = ref.watch(lmsCoursesProvider);
    final records = ref.watch(lmsRecordsProvider);
    final activity = ref.watch(lmsActivityProvider);
    final status = lmsCombine([
      ref.watch(lmsCoursesControllerProvider),
      ref.watch(lmsRecordsControllerProvider),
      ref.watch(lmsActivityControllerProvider),
    ]);

    // The server's own figures when the dashboard answers; otherwise the
    // derived ones. Counting locally under-reports on both ends: courses only
    // count the page that loaded, and learners come from an admin-only endpoint
    // that answers 403 — and therefore zero — for everyone else.
    final statsAsync = ref.watch(lmsStatsProvider);
    final server = statsAsync.valueOrNull;
    String dash(String v) => statsAsync.isLoading ? '—' : v;
    final learners = records.where((r) => r.rid != 'me').length;
    final allEntries = [for (final r in records) ...r.courses];
    final avgAll = allEntries.isEmpty
        ? 0
        : (allEntries.map(LmsLogic.pct).reduce((a, b) => a + b) /
                allEntries.length)
            .round();

    final totalCourses = server?.totalCourses ?? courses.length;
    final totalLearners = server?.totalLearners ?? learners;
    final avgCompletion = server?.avgCompletion ?? avgAll;

    final published =
        server?.publishedCourses ?? courses.where((c) => c.isPublished).length;
    final drafts =
        server?.draftCourses ?? courses.where((c) => !c.isPublished).length;

    final stats = <(IconData, String, String, String)>[
      (
        PhosphorIconsFill.bookOpenText,
        // No zero-padding: "4", not "04" (UI/UX audit #50).
        dash(totalCourses.toString()),
        'Total Courses',
        '$published published · $drafts draft'
      ),
      (
        PhosphorIconsFill.student,
        dash('$totalLearners'),
        'Total Learners',
        'Across all roles & teams'
      ),
      (
        PhosphorIconsFill.chartLineUp,
        dash('$avgCompletion%'),
        'Avg. completion',
        'Across published courses'
      ),
      (
        PhosphorIconsFill.clock,
        dash('${(server?.timeInvestedHours ?? 0).round()}'),
        'Total Time Invested',
        'Across all modules in hours'
      ),
    ];

    // Webapp audience filter: "All roles" + every role the courses use, sorted.
    final roles = <String>{for (final c in courses) ...c.roleNames}.toList()
      ..sort();
    final aud = roles.contains(_aud) ? _aud : 'all';
    final rows = [
      for (final c in courses)
        if (aud == 'all' || c.roleNames.contains(aud)) c,
    ];

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          LmsHeader(
            onBack: () =>
                context.canPop() ? context.pop() : context.go(Routes.dashboard),
            leading: Container(
              width: 38.w,
              height: 38.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: AppColors.tintNavy,
                  borderRadius: BorderRadius.circular(11.r)),
              child: Icon(PhosphorIconsFill.graduationCap,
                  size: 20.sp, color: AppColors.navy),
            ),
            title: Text('Training Dashboard',
                style: AppText.custom(
                    size: 20,
                    weight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.4)),
          ),
          Expanded(
            // Skeleton only for the first load: a reload over data already on
            // screen (pull-to-refresh, reopening) keeps the figures visible.
            child: status.loading && courses.isEmpty
                ? const ListSkeleton()
                : status.error != null
                    ? ErrorState.forError(status.error!,
                        onRetry: () => reloadLms(ref))
                    : AppRefresh(
                        onRefresh: _refresh,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 40.h),
                          children: [
                            Text('Overview',
                                style: AppText.custom(
                                    size: 20,
                                    weight: FontWeight.w800,
                                    color: AppColors.textPrimary)),
                            SizedBox(height: 3.h),
                            Text(
                                'Overview of all courses, learner progress, and training activity.',
                                style: AppText.custom(
                                    size: 13,
                                    weight: FontWeight.w500,
                                    color: AppColors.textMuted)),
                            SizedBox(height: 14.h),
                            for (int i = 0; i < stats.length; i += 2) ...[
                              if (i > 0) SizedBox(height: 10.h),
                              IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(child: _statTile(stats[i])),
                                    SizedBox(width: 10.w),
                                    Expanded(child: _statTile(stats[i + 1])),
                                  ],
                                ),
                              ),
                            ],
                            Padding(
                              padding:
                                  EdgeInsets.fromLTRB(2.w, 20.h, 2.w, 11.h),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('All Courses',
                                      style: AppText.sectionTitle()),
                                  _roleFilter(roles, aud),
                                ],
                              ),
                            ),
                            if (rows.isEmpty)
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: 18.h),
                                child: Text('No courses yet',
                                    textAlign: TextAlign.center,
                                    style: AppText.custom(
                                        size: 13,
                                        weight: FontWeight.w500,
                                        color: AppColors.textMuted)),
                              ),
                            for (int i = 0; i < rows.length; i++) ...[
                              if (i > 0) SizedBox(height: 11.h),
                              LmsCourseCard.from(
                                course: rows[i],
                                records: records,
                                onTap: () => _openCourse(context, rows[i]),
                                onEdit: () => context.push(
                                    '${Routes.lmsBuilder}?id=${rows[i].id}'),
                              ),
                            ],
                            // Webapp: "View all Courses" opens My Trainings.
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => context.push(Routes.lmsMy),
                              child: Padding(
                                padding:
                                    EdgeInsets.fromLTRB(2.w, 12.h, 2.w, 2.h),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text('View all Courses',
                                        style: AppText.custom(
                                            size: 13,
                                            weight: FontWeight.w600,
                                            color: AppColors.navy)),
                                    SizedBox(width: 6.w),
                                    Icon(PhosphorIconsBold.arrowRight,
                                        size: 14.sp, color: AppColors.navy),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: 16.h),
                            _activityCard(activity),
                          ],
                        )),
          ),
          LmsFooter(
            child: LmsCtaButton(
              label: 'New course',
              icon: PhosphorIconsBold.plus,
              onTap: () => context.push(Routes.lmsBuilder),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleFilter(List<String> roles, String aud) {
    return PopupMenuButton<String>(
      initialValue: aud,
      onSelected: (v) => setState(() => _aud = v),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'all', child: Text('All roles')),
        for (final r in roles) PopupMenuItem(value: r, child: Text(r)),
      ],
      child: Container(
        height: 34.h,
        padding: EdgeInsets.symmetric(horizontal: 11.w),
        decoration: BoxDecoration(
          color: AppColors.white,
          border: Border.all(color: AppColors.borderInput),
          borderRadius: BorderRadius.circular(9.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(aud == 'all' ? 'All roles' : aud,
                style: AppText.custom(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            SizedBox(width: 6.w),
            Icon(PhosphorIconsBold.caretDown,
                size: 12.sp, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _statTile((IconData, String, String, String) t) {
    return ClozrCard(
      radius: 14,
      padding: EdgeInsets.all(12.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 30.w,
                height: 30.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: AppColors.tintNavy,
                    borderRadius: BorderRadius.circular(9.r)),
                child: Icon(t.$1, size: 15.sp, color: AppColors.navy),
              ),
              Flexible(
                child: Text(t.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: AppText.custom(
                        size: 19,
                        weight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.4)),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Text(t.$3,
              style: AppText.custom(
                  size: 12,
                  weight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  height: 1.25)),
          SizedBox(height: 2.h),
          Text(t.$4,
              style: AppText.custom(
                  size: 11,
                  weight: FontWeight.w500,
                  color: AppColors.textMuted2,
                  height: 1.25)),
        ],
      ),
    );
  }

  Widget _activityCard(List<LmsActivity> activity) {
    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.all(16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 4.h),
            child: Text('Recent Activity',
                style: AppText.custom(
                    size: 15,
                    weight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ),
          if (activity.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 20.h),
              child: Text('No recent activity',
                  style: AppText.custom(
                      size: 13,
                      weight: FontWeight.w500,
                      color: AppColors.textPlaceholder)),
            ),
          for (final a in activity)
            Container(
              padding: EdgeInsets.symmetric(vertical: 9.h),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.bgLight)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8.w,
                    height: 8.w,
                    margin: EdgeInsets.only(top: 6.h),
                    decoration:
                        BoxDecoration(color: a.dot, shape: BoxShape.circle),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            style: AppText.custom(
                                size: 13,
                                weight: FontWeight.w500,
                                color: AppColors.textBodyMuted,
                                height: 1.4),
                            children: [
                              TextSpan(
                                text: '${a.who} ',
                                style: AppText.custom(
                                    size: 13,
                                    weight: FontWeight.w700,
                                    color: AppColors.textPrimary),
                              ),
                              TextSpan(text: a.what),
                            ],
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(a.time,
                            style: AppText.custom(
                                size: 11.5,
                                weight: FontWeight.w500,
                                color: AppColors.textPlaceholder)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
