import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
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
import '../lms_nav.dart';
import '../lms_style.dart';

/// Learner Detail — profile + aggregate counts, per-course progress and an
/// activity log.
class LmsLearnerDetailScreen extends ConsumerWidget {
  const LmsLearnerDetailScreen({super.key});

  static const _audit = <(Color, String, String)>[
    (AppColors.blueBright, 'Assigned Site Safety Induction', '2 Jul, 10:04 AM'),
    (AppColors.success, 'Completed a module in CRM Fundamentals', '30 Jun, 4:18 PM'),
    (AppColors.warning, 'Nudge sent by Manoj Varma', '28 Jun, 9:12 AM'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rid = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final record = ref.watch(lmsRecordByIdProvider(rid));
    final courseOf = ref.watch(lmsCourseLookupProvider);
    final load = lmsCombine([
      ref.watch(lmsRecordsControllerProvider),
      ref.watch(lmsCoursesControllerProvider),
    ]);
    final person = LmsPeople.of(rid);
    final agg = LmsLogic.aggStatus(record, courseOf);
    final rolePill = LmsStyle.rolePill(person.role);

    final counts = <(String, String)>[
      ('Assigned', '${record.courses.length}'),
      ('Completed', '${record.courses.where(LmsLogic.done).length}'),
      ('Overdue', '${record.courses.where((e) => LmsLogic.statusOf(e, courseOf(e.courseId)) == 'overdue').length}'),
    ];

    void toast(String m) => ref.read(toastProvider.notifier).show(m);

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          LmsHeader(
            onBack: () => lmsBack(context),
            title: Text('Learner',
                style: AppText.custom(size: 20, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
          ),
          Expanded(
            child: load.loading
                ? const DetailSkeleton()
                : load.error != null
                    ? ErrorState.forError(load.error!, onRetry: () => reloadLms(ref))
                    : record.courses.isEmpty
                        ? const EmptyState(
                            icon: PhosphorIconsRegular.student,
                            title: 'No training record',
                            body: 'This learner has no assigned courses yet.',
                          )
                        : ListView(
              padding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 40.h),
              children: [
                ClozrCard(
                  radius: 16,
                  padding: EdgeInsets.all(16.r),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          InitialsAvatar(initials: person.initials, size: 56, background: person.color, foreground: AppColors.white, fontSize: 15),
                          SizedBox(width: 13.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(person.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary)),
                                SizedBox(height: 5.h),
                                Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                                      decoration: BoxDecoration(color: rolePill.bg, borderRadius: BorderRadius.circular(8.r)),
                                      child: Text(person.role,
                                          style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: rolePill.fg)),
                                    ),
                                    SizedBox(width: 7.w),
                                    StatusPill.meta(StatusMeta$.lms[agg]!),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 15.h),
                      Row(
                        children: [
                          for (int i = 0; i < counts.length; i++) ...[
                            if (i > 0) SizedBox(width: 8.w),
                            Expanded(child: _countTile(counts[i])),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 14.h),
                _coursesCard(record, courseOf),
                SizedBox(height: 14.h),
                _activityCard(),
              ],
            ),
          ),
          LmsFooter(
            child: Row(
              children: [
                Expanded(child: LmsGhostButton(label: 'Assign course', onTap: () => toast('Assign course'))),
                SizedBox(width: 10.w),
                Expanded(
                  child: LmsCtaButton(
                    label: 'Nudge',
                    icon: PhosphorIconsFill.bellRinging,
                    onTap: () => toast('Reminder sent to ${person.firstName}'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _countTile((String, String) t) {
    return Container(
      padding: EdgeInsets.all(10.r),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.bgScreen, borderRadius: BorderRadius.circular(11.r)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.$2, style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary)),
          SizedBox(height: 1.h),
          Text(t.$1, style: AppText.custom(size: 11, weight: FontWeight.w600, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _coursesCard(LearnerRecord record, Course? Function(String) courseOf) {
    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 8.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 4.h),
            child: Text('Courses', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
          for (final e in record.courses) _courseRow(e, courseOf),
        ],
      ),
    );
  }

  Widget _courseRow(CourseProgress e, Course? Function(String) courseOf) {
    final c = courseOf(e.courseId);
    if (c == null) return const SizedBox.shrink();
    final st = LmsLogic.statusOf(e, c);
    final pct = LmsLogic.pct(e);
    final overdue = st == 'overdue';
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.bgLight))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              SizedBox(width: 9.w),
              StatusPill.meta(StatusMeta$.lms[st]!),
            ],
          ),
          SizedBox(height: 9.h),
          Row(
            children: [
              Expanded(child: LmsProgressBar(value: pct / 100, color: LmsStyle.barColor(st), height: 6)),
              SizedBox(width: 9.w),
              Text('$pct%', style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.textMuted2)),
            ],
          ),
          SizedBox(height: 6.h),
          Text(c.deadline.isNotEmpty ? 'Deadline: ${c.deadline}' : 'No deadline',
              style: AppText.custom(
                  size: 11.5,
                  weight: overdue ? FontWeight.w700 : FontWeight.w500,
                  color: overdue ? AppColors.error : AppColors.textPlaceholder)),
        ],
      ),
    );
  }

  Widget _activityCard() {
    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 8.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 4.h),
            child: Text('Recent activity', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
          for (final a in _audit)
            Container(
              padding: EdgeInsets.symmetric(vertical: 9.h),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.bgLight))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8.w,
                    height: 8.w,
                    margin: EdgeInsets.only(top: 5.h),
                    decoration: BoxDecoration(color: a.$1, shape: BoxShape.circle),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.$2, style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textSecondary, height: 1.4)),
                        SizedBox(height: 2.h),
                        Text(a.$3, style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
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
