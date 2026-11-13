import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/course_admin_providers.dart';
import '../../application/providers/lms_providers.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/lms_activity.dart';
import '../../infrastructure/data_sources/local/lms_people.dart';
import '../../infrastructure/data_sources/remote/course_admin_remote_ds.dart';
import '../components/lms_assign_course_sheet.dart';
import '../components/lms_header.dart';
import '../components/lms_progress_bar.dart';
import '../lms_assign.dart';
import '../lms_course_actions.dart';
import '../lms_nav.dart';
import '../lms_style.dart';

/// Webapp `CourseDetailScreen`: header (status, Platform badge, modules,
/// audience / deadline / rules, Assign · Edit · Delete — or the read-only note
/// for a platform course), enrolment tiles + completion rate, assigned
/// learners with role / progress / status and View · Send reminder, the
/// description, modules and this course's recent activity. Always read fresh
/// from `GET /lms/courses/{id}/`.
class LmsCourseDetailScreen extends ConsumerWidget {
  const LmsCourseDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final async = ref.watch(courseDetailProvider(id));
    // A refetch that fails keeps the previous value; a 404 means the course
    // is gone, so it must not keep showing (with live buttons).
    final gone = async.error is AppError &&
        (async.error as AppError).type == AppErrorType.notFound;
    final course = gone ? null : async.valueOrNull;

    if (course == null) {
      final e = async.error;
      final missing =
          e == null || (e is AppError && e.type == AppErrorType.notFound);
      return Container(
        color: AppColors.bgScreen,
        child: Column(
          children: [
            LmsHeader(
                onBack: () => lmsBack(context, fallback: Routes.lmsCourses),
                title: Text('Course', style: AppText.h1())),
            Expanded(
              child: async.isLoading
                  ? const DetailSkeleton()
                  : Padding(
                      padding: EdgeInsets.all(24.r),
                      child: Text(
                        missing
                            ? 'Course not found.'
                            : (e is AppError ? e.message : 'Course not found.'),
                        style: AppText.custom(
                            size: 14,
                            weight: FontWeight.w500,
                            color: AppColors.textMuted),
                      ),
                    ),
            ),
          ],
        ),
      );
    }

    final learnersAsync = ref.watch(courseLearnerRowsProvider(course.id));
    final learners = learnersAsync.valueOrNull ?? const <CourseLearnerRow>[];
    final enrolled = learners.length;
    int count(String st) => learners.where((l) => l.status == st).length;
    final done = count('completed');
    final rate = enrolled == 0 ? 0 : (done / enrolled * 100).round();

    final tiles = <(String, int, Color, String)>[
      ('Enrolled', enrolled, AppColors.textPrimary, 'Learners assigned'),
      ('Completed', done, AppColors.success, 'Finished every module'),
      (
        'In progress',
        count('inprogress'),
        AppColors.warningDeep,
        'Currently learning'
      ),
      ('Overdue', count('overdue'), AppColors.error, 'Past the deadline'),
    ];

    Future<void> assign() async {
      final r = await showAssignCourseSheet(context,
          courses: [(course.id, course.title)]);
      if (r == null) return;
      ref.read(toastProvider.notifier).show(
          '"${r.courseTitle}" assigned to ${r.enrolled} learner${r.enrolled == 1 ? '' : 's'}');
      reloadLms(ref);
    }

    // Webapp: the dashboard feed filtered to this course's title, latest 4.
    final activity = ref
        .watch(lmsActivityProvider)
        .where((a) => a.courseTitle.isNotEmpty && a.courseTitle == course.title)
        .take(4)
        .toList();
    final activityLoading = ref.watch(lmsActivityControllerProvider).loading;

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          LmsHeader(
            onBack: () => lmsBack(context, fallback: Routes.lmsCourses),
            title: Text(course.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.custom(
                    size: 19,
                    weight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3)),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(courseDetailProvider(id));
                ref.invalidate(courseLearnerRowsProvider(course.id));
                ref.read(lmsActivityControllerProvider.notifier).reload();
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 40.h),
                children: [
                  _header(context, ref, course, assign),
                  SizedBox(height: 14.h),
                  for (int i = 0; i < tiles.length; i += 2) ...[
                    if (i > 0) SizedBox(height: 10.h),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _statTile(tiles[i])),
                          SizedBox(width: 10.w),
                          Expanded(child: _statTile(tiles[i + 1])),
                        ],
                      ),
                    ),
                  ],
                  SizedBox(height: 10.h),
                  _completionCard(rate),
                  SizedBox(height: 14.h),
                  _learnersCard(
                      context, ref, course, learnersAsync, learners, assign),
                  SizedBox(height: 14.h),
                  _descriptionCard(course),
                  SizedBox(height: 14.h),
                  _modulesCard(course),
                  SizedBox(height: 14.h),
                  _activityCard(activity, activityLoading),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaItem(IconData icon, String text) => Padding(
        padding: EdgeInsets.only(top: 5.h),
        child: Row(
          children: [
            Icon(icon, size: 14.sp, color: AppColors.textPlaceholder),
            SizedBox(width: 6.w),
            Expanded(
              child: Text(text,
                  style: AppText.custom(
                      size: 12,
                      weight: FontWeight.w600,
                      color: AppColors.textPlaceholder)),
            ),
          ],
        ),
      );

  Widget _header(BuildContext context, WidgetRef ref, Course course,
      Future<void> Function() assign) {
    final readOnly = course.isGlobal;
    final who = switch (course.audience) {
      'admins' => 'Admins only',
      'users' => 'Non-admin users',
      _ => 'Everyone'
    };
    final audience = readOnly
        ? '$who (provided by Clozr)'
        : (course.roleNames.isNotEmpty
            ? course.roleNames.join(', ')
            : (course.isUniversal ? 'All users' : 'No roles'));
    final deadline = course.deadline.isEmpty ? 'No deadline' : course.deadline;
    final rules =
        '${course.sequential ? 'Sequential modules' : 'Free order'}${course.mandatory ? ' · Mandatory' : ''}';
    final mods = course.modules.length;

    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.all(16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48.r,
                height: 48.r,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: AppColors.blueSubtle,
                    borderRadius: BorderRadius.circular(13.r)),
                child: Icon(PhosphorIconsRegular.bookOpen,
                    size: 24.sp, color: AppColors.navy),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(course.title,
                        style: AppText.custom(
                            size: 17,
                            weight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    SizedBox(height: 6.h),
                    Wrap(
                      spacing: 6.w,
                      runSpacing: 4.h,
                      children: [
                        StatusPill.meta(
                            LmsStyle.publishMeta(course.isPublished)),
                        if (readOnly)
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8.w, vertical: 3.h),
                            decoration: BoxDecoration(
                                color: AppColors.tintNavy,
                                borderRadius: BorderRadius.circular(6.r)),
                            child: Text('Platform',
                                style: AppText.custom(
                                    size: 11,
                                    weight: FontWeight.w700,
                                    color: AppColors.navy)),
                          ),
                      ],
                    ),
                    SizedBox(height: 6.h),
                    Text('$mods ${mods == 1 ? 'module' : 'modules'}',
                        style: AppText.custom(
                            size: 13,
                            weight: FontWeight.w600,
                            color: AppColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          _metaItem(PhosphorIconsRegular.usersThree, audience),
          _metaItem(
              PhosphorIconsRegular.calendarCheck, 'Complete by $deadline'),
          _metaItem(PhosphorIconsRegular.listChecks, rules),
          SizedBox(height: 14.h),
          if (readOnly)
            Text(
                'Provided by Clozr to every organization. You can track your team’s progress, but not edit it.',
                style: AppText.custom(
                    size: 13,
                    weight: FontWeight.w500,
                    color: AppColors.textMuted,
                    height: 1.5))
          else
            Row(
              children: [
                Expanded(
                    child: _button('Assign course', PhosphorIconsBold.plus,
                        false, assign)),
                SizedBox(width: 8.w),
                Expanded(
                  child: _button(
                      'Edit course',
                      PhosphorIconsBold.pencilSimple,
                      true,
                      () =>
                          context.push('${Routes.lmsBuilder}?id=${course.id}')),
                ),
                SizedBox(width: 8.w),
                Semantics(
                  label: 'Delete course',
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      // Webapp: confirm, delete, then back to Course builder.
                      if (await deleteCourseWithConfirm(context, ref, course) &&
                          context.mounted) {
                        context.go(Routes.lmsCourses);
                      }
                    },
                    child: Container(
                      width: 44.h,
                      height: 44.h,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(11.r),
                        border: Border.all(color: const Color(0xFFF3D2D2)),
                      ),
                      child: Icon(PhosphorIconsRegular.trash,
                          size: 17.sp, color: AppColors.error),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _button(
          String label, IconData icon, bool primary, VoidCallback onTap) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 44.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary ? AppColors.navy : AppColors.white,
            borderRadius: BorderRadius.circular(11.r),
            border: primary ? null : Border.all(color: AppColors.borderInput),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14.sp,
                  color: primary ? AppColors.white : AppColors.textSecondary),
              SizedBox(width: 6.w),
              Text(label,
                  style: AppText.custom(
                      size: 13.5,
                      weight: FontWeight.w700,
                      color:
                          primary ? AppColors.white : AppColors.textSecondary)),
            ],
          ),
        ),
      );

  Widget _statTile((String, int, Color, String) t) => ClozrCard(
        radius: 14,
        padding: EdgeInsets.all(13.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.$1.toUpperCase(),
                style: AppText.custom(
                    size: 11,
                    weight: FontWeight.w700,
                    color: AppColors.textPlaceholder,
                    letterSpacing: 0.4)),
            SizedBox(height: 4.h),
            Text('${t.$2}',
                style: AppText.custom(
                    size: 22, weight: FontWeight.w800, color: t.$3)),
            SizedBox(height: 2.h),
            Text(t.$4,
                style: AppText.custom(
                    size: 11.5,
                    weight: FontWeight.w500,
                    color: AppColors.textMuted)),
          ],
        ),
      );

  Widget _completionCard(int rate) => ClozrCard(
        radius: 14,
        padding: EdgeInsets.all(14.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('COMPLETION RATE',
                style: AppText.custom(
                    size: 11,
                    weight: FontWeight.w700,
                    color: AppColors.textPlaceholder,
                    letterSpacing: 0.4)),
            SizedBox(height: 4.h),
            Text('$rate%',
                style: AppText.custom(
                    size: 22,
                    weight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            SizedBox(height: 8.h),
            LmsProgressBar(
                value: rate / 100, color: AppColors.success, height: 7),
          ],
        ),
      );

  Widget _cardTitle(String t, {Widget? trailing}) => Padding(
        padding: EdgeInsets.only(bottom: 6.h),
        child: Row(
          children: [
            Expanded(
                child: Text(t,
                    style: AppText.custom(
                        size: 15,
                        weight: FontWeight.w700,
                        color: AppColors.textPrimary))),
            if (trailing != null) trailing,
          ],
        ),
      );

  Widget _learnersCard(
    BuildContext context,
    WidgetRef ref,
    Course course,
    AsyncValue<List<CourseLearnerRow>> async,
    List<CourseLearnerRow> learners,
    Future<void> Function() assign,
  ) {
    Widget body;
    if (async.isLoading && !async.hasValue) {
      body = Padding(
        padding: EdgeInsets.symmetric(vertical: 24.h),
        child: Center(
          child: Text('Loading learners…',
              style: AppText.custom(
                  size: 13,
                  weight: FontWeight.w500,
                  color: AppColors.textMuted)),
        ),
      );
    } else if (learners.isEmpty) {
      final e = async.error;
      body = Padding(
        padding: EdgeInsets.symmetric(vertical: 20.h),
        child: Column(
          children: [
            Icon(PhosphorIconsRegular.usersThree,
                size: 28.sp, color: AppColors.textPlaceholder),
            SizedBox(height: 8.h),
            Text(e is AppError ? e.message : 'No learners assigned yet',
                style: AppText.custom(
                    size: 14,
                    weight: FontWeight.w600,
                    color: AppColors.textMuted)),
            if (!course.isGlobal) ...[
              SizedBox(height: 10.h),
              SizedBox(
                  width: 170.w,
                  child: _button(
                      'Assign course', PhosphorIconsBold.plus, false, assign)),
            ],
          ],
        ),
      );
    } else {
      body = Column(children: [
        for (final l in learners) _learnerRow(context, ref, course, l)
      ]);
    }
    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 8.r),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_cardTitle('Assigned learners'), body]),
    );
  }

  Widget _learnerRow(
      BuildContext context, WidgetRef ref, Course course, CourseLearnerRow l) {
    final person = LmsPeople.of(l.rid);
    final bar = switch (l.status) {
      'completed' => AppColors.success,
      'overdue' => AppColors.error,
      'inprogress' => AppColors.warning,
      _ => AppColors.bgLight,
    };
    void open() => context.push('${Routes.lmsLearnerDetail}?id=${l.rid}');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: open,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 11.h),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.bgLight))),
        child: Column(
          children: [
            Row(
              children: [
                InitialsAvatar(
                    initials: person.initials,
                    size: 34,
                    background: person.color,
                    foreground: AppColors.white,
                    fontSize: 11.5),
                SizedBox(width: 11.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(
                              size: 13.5,
                              weight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      SizedBox(height: 3.h),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 7.w, vertical: 2.h),
                        decoration: BoxDecoration(
                            color: AppColors.bgLight,
                            borderRadius: BorderRadius.circular(6.r)),
                        child: Text(l.roleName.isEmpty ? '—' : l.roleName,
                            style: AppText.custom(
                                size: 11,
                                weight: FontWeight.w600,
                                color: AppColors.textMuted)),
                      ),
                    ],
                  ),
                ),
                StatusPill.meta(StatusMeta$.lms[l.status]!),
              ],
            ),
            SizedBox(height: 8.h),
            Row(
              children: [
                SizedBox(width: 45.w),
                Expanded(
                    child: LmsProgressBar(
                        value: l.pct / 100, color: bar, height: 5)),
                SizedBox(width: 8.w),
                Text('${l.pct}%',
                    style: AppText.custom(
                        size: 11,
                        weight: FontWeight.w700,
                        color: AppColors.textMuted2)),
                SizedBox(width: 10.w),
                _iconAction(PhosphorIconsRegular.eye, 'View learner', open),
                SizedBox(width: 6.w),
                _iconAction(
                    PhosphorIconsRegular.bellRinging,
                    'Send reminder',
                    () => nudgeLearner(context, ref,
                        rid: l.rid, courseId: course.id, firstName: l.name)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconAction(IconData icon, String label, VoidCallback onTap) =>
      Semantics(
        label: label,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 34.r,
            height: 30.r,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: const Color(0xFFE6E7EA)),
            ),
            child: Icon(icon, size: 16.sp, color: AppColors.textSecondary),
          ),
        ),
      );

  Widget _descriptionCard(Course course) {
    final desc = course.desc.trim().isNotEmpty
        ? course.desc
        : 'This course walks the team through ${course.title.toLowerCase()} with short video modules and attached resources.';
    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.all(16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('COURSE DESCRIPTION',
              style: AppText.custom(
                  size: 11,
                  weight: FontWeight.w700,
                  color: AppColors.textPlaceholder,
                  letterSpacing: 0.4)),
          SizedBox(height: 8.h),
          Text(desc,
              style: AppText.custom(
                  size: 13.5,
                  weight: FontWeight.w500,
                  color: AppColors.textLabelAlt,
                  height: 1.6)),
        ],
      ),
    );
  }

  Widget _modulesCard(Course course) {
    final mods = course.modules;
    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 8.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Modules',
              trailing: Text('${mods.length}',
                  style: AppText.custom(
                      size: 12,
                      weight: FontWeight.w700,
                      color: AppColors.textPlaceholder))),
          if (mods.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12.h),
              child: Text('No modules yet',
                  style: AppText.custom(
                      size: 13,
                      weight: FontWeight.w500,
                      color: AppColors.textMuted)),
            ),
          for (int i = 0; i < mods.length; i++)
            Container(
              padding: EdgeInsets.symmetric(vertical: 11.h),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : const Border(top: BorderSide(color: AppColors.bgLight)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34.r,
                    height: 34.r,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: AppColors.bgLight,
                        borderRadius: BorderRadius.circular(8.r)),
                    child: Icon(PhosphorIconsRegular.fileVideo,
                        size: 16.sp, color: AppColors.navy),
                  ),
                  SizedBox(width: 11.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${i + 1}. ${mods[i].title}',
                            style: AppText.custom(
                                size: 13.5,
                                weight: FontWeight.w600,
                                color: AppColors.textBody)),
                        SizedBox(height: 2.h),
                        Text(
                            '${mods[i].video ? mods[i].videoTitle : 'No lesson video yet'} · '
                            '${mods[i].res.length} ${mods[i].res.length == 1 ? 'resource' : 'resources'}',
                            style: AppText.custom(
                                size: 12,
                                weight: FontWeight.w500,
                                color: AppColors.textPlaceholder)),
                      ],
                    ),
                  ),
                  if (mods[i].video)
                    Semantics(
                      label: 'Lesson video uploaded',
                      child: Icon(PhosphorIconsFill.checkCircle,
                          size: 18.sp, color: AppColors.success),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _activityCard(List<LmsActivity> activity, bool loading) => ClozrCard(
        radius: 16,
        padding: EdgeInsets.all(16.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(PhosphorIconsRegular.clockCounterClockwise,
                    size: 16.sp, color: AppColors.navy),
                SizedBox(width: 7.w),
                Text('Recent activity',
                    style: AppText.custom(
                        size: 15,
                        weight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                SizedBox(width: 6.w),
                Tooltip(
                  message: 'Latest learner events on this course.',
                  triggerMode: TooltipTriggerMode.tap,
                  child: Icon(PhosphorIconsRegular.info,
                      size: 14.sp, color: AppColors.textPlaceholder),
                ),
              ],
            ),
            SizedBox(height: 10.h),
            if (activity.isEmpty)
              Text(
                  loading
                      ? 'Loading activity…'
                      : 'No recent activity for this course',
                  style: AppText.custom(
                      size: 13,
                      weight: FontWeight.w500,
                      color: AppColors.textMuted)),
            for (final a in activity)
              Padding(
                padding: EdgeInsets.only(bottom: 12.h),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 9.r,
                      height: 9.r,
                      margin: EdgeInsets.only(top: 5.h),
                      decoration:
                          BoxDecoration(color: a.dot, shape: BoxShape.circle),
                    ),
                    SizedBox(width: 11.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${a.who} ${a.what}'.trim(),
                              style: AppText.custom(
                                  size: 13.5,
                                  weight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                          SizedBox(height: 2.h),
                          Text(a.time,
                              style: AppText.custom(
                                  size: 12,
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
