import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../application/providers/lms_providers.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/lms_activity.dart';
import '../../domain/lms_logic.dart';
import '../components/lms_course_card.dart';
import '../components/lms_footer.dart';
import '../components/lms_header.dart';

/// Training Overview — stat tiles, top courses, recent activity and the
/// new-course CTA.
class LmsOverviewScreen extends ConsumerWidget {
  const LmsOverviewScreen({super.key});

  void _openCourse(BuildContext context, Course c) {
    if (c.isPublished) {
      context.push('${Routes.lmsCourseDetail}?id=${c.id}');
    } else {
      context.push('${Routes.lmsBuilder}?id=${c.id}');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(lmsCoursesProvider);
    final records = ref.watch(lmsRecordsProvider);
    final activity = ref.watch(lmsActivityProvider);

    final learners = records.where((r) => r.rid != 'me').length;
    final allEntries = [for (final r in records) ...r.courses];
    final avgAll = allEntries.isEmpty
        ? 0
        : (allEntries.map(LmsLogic.pct).reduce((a, b) => a + b) / allEntries.length).round();

    final stats = <(IconData, String, String)>[
      (PhosphorIconsFill.bookOpenText, courses.length.toString().padLeft(2, '0'), 'Total Courses'),
      (PhosphorIconsFill.student, learners.toString().padLeft(2, '0'), 'Total Learners'),
      (PhosphorIconsFill.chartLineUp, '$avgAll%', 'Avg. completion'),
    ];

    final topCourses = [...courses]
      ..sort((a, b) => a.status == b.status ? 0 : (a.isPublished ? -1 : 1));
    final top3 = topCourses.take(3).toList();

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          LmsHeader(
            onBack: () => context.canPop() ? context.pop() : context.go(Routes.dashboard),
            leading: Container(
              width: 38.w,
              height: 38.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.tintNavy, borderRadius: BorderRadius.circular(11.r)),
              child: Icon(PhosphorIconsFill.graduationCap, size: 20.sp, color: AppColors.navy),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Training',
                    style: AppText.custom(size: 20, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4, height: 1.1)),
                Text('Overview of courses, learners & activity',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 40.h),
              children: [
                Row(
                  children: [
                    for (int i = 0; i < stats.length; i++) ...[
                      if (i > 0) SizedBox(width: 10.w),
                      Expanded(child: _statTile(stats[i])),
                    ],
                  ],
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(2.w, 20.h, 2.w, 11.h),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('All Courses', style: AppText.sectionTitle()),
                      GestureDetector(
                        onTap: () => context.go(Routes.lmsCourses),
                        child: Text('View all Courses',
                            style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.blueBright)),
                      ),
                    ],
                  ),
                ),
                for (int i = 0; i < top3.length; i++) ...[
                  if (i > 0) SizedBox(height: 11.h),
                  LmsCourseCard.from(
                    course: top3[i],
                    records: records,
                    onTap: () => _openCourse(context, top3[i]),
                    onEdit: () => context.push('${Routes.lmsBuilder}?id=${top3[i].id}'),
                  ),
                ],
                SizedBox(height: 16.h),
                _activityCard(activity),
              ],
            ),
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

  Widget _statTile((IconData, String, String) t) {
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
                decoration: BoxDecoration(color: AppColors.tintNavy, borderRadius: BorderRadius.circular(9.r)),
                child: Icon(t.$1, size: 15.sp, color: AppColors.navy),
              ),
              Flexible(
                child: Text(t.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: AppText.custom(size: 19, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Text(t.$3,
              style: AppText.custom(size: 11, weight: FontWeight.w600, color: AppColors.textMuted2, height: 1.25)),
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
                style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
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
                    decoration: BoxDecoration(color: a.dot, shape: BoxShape.circle),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textBodyMuted, height: 1.4),
                            children: [
                              TextSpan(
                                text: '${a.who} ',
                                style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary),
                              ),
                              TextSpan(text: a.what),
                            ],
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(a.time,
                            style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
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
