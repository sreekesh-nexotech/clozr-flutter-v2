import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/lms_providers.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/learner_record.dart';
import '../../domain/lms_logic.dart';
import '../../infrastructure/data_sources/local/lms_people.dart';
import '../components/lms_footer.dart';
import '../components/lms_header.dart';
import '../components/lms_progress_bar.dart';
import '../components/lms_thumb.dart';
import '../lms_nav.dart';
import '../lms_style.dart';

/// Course Detail (admin) — banner, enrolment stat tiles, completion bar,
/// modules, assigned learners with per-row Nudge, description and actions.
class LmsCourseDetailScreen extends ConsumerWidget {
  const LmsCourseDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final course = ref.watch(lmsCourseByIdProvider(id));
    final records = ref.watch(lmsRecordsProvider);
    final load = lmsCombine([
      ref.watch(lmsCoursesControllerProvider),
      ref.watch(lmsRecordsControllerProvider),
    ]);

    if (course == null) {
      return Container(
        color: AppColors.bgScreen,
        child: Column(
          children: [
            LmsHeader(onBack: () => lmsBack(context), title: Text('Course', style: AppText.h1())),
            Expanded(
              child: load.loading
                  ? const DetailSkeleton()
                  : load.error != null
                      ? ErrorState.forError(load.error!, onRetry: () => reloadLms(ref))
                      : const EmptyState(
                          icon: PhosphorIconsRegular.bookOpenText,
                          title: 'Course not found',
                          body: 'This course may have been removed or is no longer available to you.',
                        ),
            ),
          ],
        ),
      );
    }

    final entries = <(String, CourseProgress)>[
      for (final r in records)
        if (r.entryFor(course.id) != null) (r.rid, r.entryFor(course.id)!),
    ];
    int countOf(String st) => entries.where((e) => LmsLogic.statusOf(e.$2, course) == st).length;
    final avg = entries.isEmpty
        ? 0
        : (entries.map((e) => LmsLogic.pct(e.$2)).reduce((a, b) => a + b) / entries.length).round();

    final metaLabel = StringBuffer('${course.modules.length} modules');
    if (course.deadline.isNotEmpty) metaLabel.write(' · Deadline ${course.deadline}');
    if (course.mandatory) metaLabel.write(' · Mandatory');

    final tiles = <(String, String, Color, Color, IconData)>[
      ('Enrolled', '${entries.length}', AppColors.blueBright, AppColors.blueSubtle, PhosphorIconsFill.usersThree),
      ('Completed', '${countOf('completed')}', AppColors.success, AppColors.tintGreen, PhosphorIconsFill.checkCircle),
      ('In progress', '${countOf('inprogress')}', AppColors.warningDeep, AppColors.tintAmber, PhosphorIconsFill.hourglassMedium),
      ('Overdue', '${countOf('overdue')}', AppColors.error, AppColors.tintRed, PhosphorIconsFill.warningCircle),
    ];

    void toast(String m) => ref.read(toastProvider.notifier).show(m);

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          LmsHeader(
            onBack: () => lmsBack(context),
            title: Text(course.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.custom(size: 19, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
            trailing: StatusPill.meta(LmsStyle.publishMeta(course.isPublished)),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 40.h),
              children: [
                LmsThumb(course: course, height: 128, iconSize: 46, radius: 13),
                Padding(
                  padding: EdgeInsets.fromLTRB(2.w, 10.h, 2.w, 0),
                  child: Text(course.sub, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(2.w, 3.h, 2.w, 0),
                  child: Text(metaLabel.toString(),
                      style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                ),
                SizedBox(height: 14.h),
                Row(
                  children: [
                    Expanded(child: _statTile(tiles[0])),
                    SizedBox(width: 10.w),
                    Expanded(child: _statTile(tiles[1])),
                  ],
                ),
                SizedBox(height: 10.h),
                Row(
                  children: [
                    Expanded(child: _statTile(tiles[2])),
                    SizedBox(width: 10.w),
                    Expanded(child: _statTile(tiles[3])),
                  ],
                ),
                SizedBox(height: 14.h),
                _completionCard(avg),
                SizedBox(height: 14.h),
                _modulesCard(course),
                SizedBox(height: 14.h),
                _learnersCard(context, ref, course, entries, toast),
                SizedBox(height: 14.h),
                ClozrCard(
                  radius: 16,
                  padding: EdgeInsets.all(16.r),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('About this course', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
                      SizedBox(height: 8.h),
                      Text(course.desc,
                          style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textLabelAlt, height: 1.6)),
                    ],
                  ),
                ),
                SizedBox(height: 14.h),
                GestureDetector(
                  onTap: () => toast('Course deleted'),
                  child: Container(
                    height: 48.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(14.r),
                      border: Border.all(color: const Color(0xFFF3D2D2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Delete the course', style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.error)),
                        SizedBox(width: 8.w),
                        Icon(PhosphorIconsRegular.trash, size: 16.sp, color: AppColors.error),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          LmsFooter(
            child: Row(
              children: [
                Expanded(
                  flex: 10,
                  child: LmsGhostButton(
                    label: 'Edit course',
                    icon: PhosphorIconsRegular.pencilSimple,
                    onTap: () => context.push('${Routes.lmsBuilder}?id=${course.id}'),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  flex: 12,
                  child: LmsCtaButton(label: 'Assign course', onTap: () => toast('Assign course')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile((String, String, Color, Color, IconData) t) {
    return ClozrCard(
      radius: 14,
      padding: EdgeInsets.all(12.r),
      child: Row(
        children: [
          Container(
            width: 30.w,
            height: 30.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: t.$4, borderRadius: BorderRadius.circular(9.r)),
            child: Icon(t.$5, size: 16.sp, color: t.$3),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.$2, style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary, height: 1.1)),
                Text(t.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 11, weight: FontWeight.w600, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _completionCard(int avg) {
    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.all(16.r),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Completion rate', style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
              Text('$avg%', style: AppText.custom(size: 14, weight: FontWeight.w800, color: AppColors.success)),
            ],
          ),
          SizedBox(height: 10.h),
          LmsProgressBar(value: avg / 100, color: AppColors.success, height: 8),
        ],
      ),
    );
  }

  Widget _modulesCard(Course course) {
    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 8.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 4.h),
            child: Text('Modules', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
          for (int i = 0; i < course.modules.length; i++)
            Container(
              padding: EdgeInsets.symmetric(vertical: 11.h),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.bgLight))),
              child: Row(
                children: [
                  SizedBox(
                    width: 18.w,
                    child: Text('${i + 1}.', style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textPlaceholder)),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Text(course.modules[i].title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textBody)),
                  ),
                  if (course.modules[i].res.isNotEmpty) ...[
                    SizedBox(width: 8.w),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
                      decoration: BoxDecoration(color: AppColors.blueSubtle, borderRadius: BorderRadius.circular(7.r)),
                      child: Text('${course.modules[i].res.length} PDF',
                          style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.blueBright)),
                    ),
                  ],
                  SizedBox(width: 8.w),
                  Text(course.modules[i].dur, style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _learnersCard(
    BuildContext context,
    WidgetRef ref,
    Course course,
    List<(String, CourseProgress)> entries,
    void Function(String) toast,
  ) {
    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 8.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 4.h),
            child: Text('Assigned learners', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
          for (final e in entries) _learnerRow(context, ref, course, e, toast),
        ],
      ),
    );
  }

  Widget _learnerRow(
    BuildContext context,
    WidgetRef ref,
    Course course,
    (String, CourseProgress) e,
    void Function(String) toast,
  ) {
    final rid = e.$1;
    final person = LmsPeople.of(rid);
    final st = LmsLogic.statusOf(e.$2, course);
    final pct = LmsLogic.pct(e.$2);
    final isYou = rid == 'me';
    final canNudge = st != 'completed' && !isYou;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isYou ? null : () => context.push('${Routes.lmsLearnerDetail}?id=$rid'),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 11.h),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.bgLight))),
        child: Row(
          children: [
            InitialsAvatar(initials: person.initials, size: 34, background: person.color, foreground: AppColors.white, fontSize: 11.5),
            SizedBox(width: 11.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${person.name}${isYou ? ' (You)' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  SizedBox(height: 5.h),
                  Row(
                    children: [
                      Expanded(child: LmsProgressBar(value: pct / 100, color: LmsStyle.barColor(st), height: 5)),
                      SizedBox(width: 8.w),
                      Text('$pct%', style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textMuted2)),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 10.w),
            StatusPill.meta(StatusMeta$.lms[st]!),
            if (canNudge) ...[
              SizedBox(width: 8.w),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => toast('Reminder sent to ${person.firstName}'),
                child: Container(
                  height: 30.h,
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(9.r),
                    border: Border.all(color: const Color(0xFFE6E7EA)),
                  ),
                  child: Text('Nudge', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textSecondary)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
