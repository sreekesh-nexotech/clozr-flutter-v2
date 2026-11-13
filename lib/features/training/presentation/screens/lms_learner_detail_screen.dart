import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/api/user_directory.dart';
import '../../../../data/mock/status_meta.dart';
import '../../application/providers/course_admin_providers.dart';
import '../../infrastructure/data_sources/local/lms_people.dart';
import '../../infrastructure/data_sources/remote/course_admin_remote_ds.dart';
import '../components/lms_footer.dart';
import '../components/lms_header.dart';
import '../components/lms_progress_bar.dart';
import '../lms_assign.dart';
import '../lms_nav.dart';
import '../lms_style.dart';

/// Webapp `LearnerDetailScreen`, read from the same `GET /lms/learners/` row
/// as the list: header (initials, name, role chip, email, "Training deadline",
/// status pill), "Learner information", "Training progress" and the
/// "Assigned courses" note, with Nudge (all courses) and Assign course (this
/// learner only, pre-ticked). A user with no enrolments is "Learner not found."
class LmsLearnerDetailScreen extends ConsumerWidget {
  const LmsLearnerDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raw = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    // The course detail links by roster id, where `me` is yourself.
    final userId = raw == 'me' ? (UserDirectory.currentUserId ?? '') : raw;
    final async = ref.watch(learnerSummariesProvider);
    final learner =
        async.valueOrNull?.where((l) => l.userId == userId).firstOrNull;

    Widget body;
    if (async.isLoading && !async.hasValue) {
      body = const DetailSkeleton();
    } else if (async.hasError && !async.hasValue) {
      body = async.error is AppError
          ? ErrorState.forError(async.error! as AppError,
              onRetry: () => ref.invalidate(learnerSummariesProvider))
          : ErrorState(
              body: 'Could not load learners.',
              onRetry: () => ref.invalidate(learnerSummariesProvider));
    } else if (learner == null) {
      body = Center(
        child: Text('Learner not found.',
            style: AppText.custom(
                size: 14, weight: FontWeight.w600, color: AppColors.textMuted)),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => ref.refresh(learnerSummariesProvider.future),
        child: _details(learner),
      );
    }

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          LmsHeader(
            onBack: () => lmsBack(context, fallback: Routes.lmsLearners),
            title: Text(learner?.name ?? 'Learner',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.custom(
                    size: 20,
                    weight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.4)),
          ),
          Expanded(child: body),
          if (learner != null)
            LmsFooter(
              child: Row(
                children: [
                  Expanded(
                    child: LmsGhostButton(
                      label: 'Nudge',
                      icon: PhosphorIconsRegular.bellRinging,
                      onTap: () => nudgeAllCourses(context, ref,
                          userId: learner.userId, name: learner.name),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: LmsCtaButton(
                      label: 'Assign course',
                      icon: PhosphorIconsBold.plus,
                      onTap: () => assignFromLearners(context, ref,
                          only: AssignableUser(
                              id: learner.userId,
                              name: learner.name,
                              role: learner.roleName)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _details(LearnerSummary l) {
    final person = LmsPeople.of(l.rid);
    final role = l.roleName.isEmpty ? '—' : l.roleName;
    final deadlineText =
        l.deadline == null ? 'No deadline' : absoluteDate(l.deadline);
    final deadlineColor = l.overdue ? AppColors.error : AppColors.textPrimary;
    final meta = StatusMeta$.lms[l.status] ?? StatusMeta$.lms['notstarted']!;

    final info = <(String, String, Color?)>[
      ('Role', role, null),
      ('Email', l.email.isEmpty ? '—' : l.email, null),
      ('Courses assigned', '${l.assigned}', null),
      ('Courses completed', '${l.completed}', null),
      ('Deadline', deadlineText, deadlineColor),
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 40.h),
      children: [
        ClozrCard(
          radius: 16,
          padding: EdgeInsets.all(16.r),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialsAvatar(
                  initials: person.initials,
                  size: 56,
                  background: person.color,
                  foreground: AppColors.white,
                  fontSize: 18),
              SizedBox(width: 13.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.name,
                        style: AppText.custom(
                            size: 17,
                            weight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    SizedBox(height: 6.h),
                    Wrap(
                      spacing: 7.w,
                      runSpacing: 6.h,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10.w, vertical: 4.h),
                          decoration: BoxDecoration(
                              color: AppColors.borderCardSoft,
                              borderRadius: BorderRadius.circular(8.r)),
                          child: Text(role,
                              style: AppText.custom(
                                  size: 11.5,
                                  weight: FontWeight.w700,
                                  color: AppColors.textSecondary)),
                        ),
                        StatusPill.meta(meta),
                      ],
                    ),
                    SizedBox(height: 7.h),
                    Text(l.email.isEmpty ? '—' : l.email,
                        style: AppText.custom(
                            size: 13,
                            weight: FontWeight.w500,
                            color: AppColors.textMuted)),
                    SizedBox(height: 6.h),
                    Row(
                      children: [
                        Icon(PhosphorIconsRegular.calendarDots,
                            size: 13.sp, color: deadlineColor),
                        SizedBox(width: 5.w),
                        Flexible(
                          child: Text('Training deadline $deadlineText',
                              style: AppText.custom(
                                  size: 12,
                                  weight: FontWeight.w600,
                                  color: deadlineColor)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 14.h),
        ClozrCard(
          radius: 16,
          padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 6.r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Learner information',
                  style: AppText.custom(
                      size: 15,
                      weight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              SizedBox(height: 6.h),
              for (final f in info)
                Container(
                  padding: EdgeInsets.symmetric(vertical: 11.h),
                  decoration: const BoxDecoration(
                      border:
                          Border(bottom: BorderSide(color: AppColors.bgLight))),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(f.$1,
                            style: AppText.custom(
                                size: 13,
                                weight: FontWeight.w500,
                                color: AppColors.textMuted)),
                      ),
                      Flexible(
                        flex: 2,
                        child: Text(f.$2,
                            textAlign: TextAlign.right,
                            style: AppText.custom(
                                size: 13.5,
                                weight: FontWeight.w600,
                                color: f.$3 ?? AppColors.textPrimary)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: 14.h),
        ClozrCard(
          radius: 16,
          padding: EdgeInsets.all(16.r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Training progress',
                        style: AppText.custom(
                            size: 15,
                            weight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                  Text('${l.pct}%',
                      style: AppText.custom(
                          size: 15,
                          weight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                ],
              ),
              SizedBox(height: 11.h),
              LmsProgressBar(
                  value: l.pct / 100, color: LmsStyle.barColor(l.status)),
              SizedBox(height: 9.h),
              Text('${l.completed} of ${l.assigned} assigned courses completed',
                  style: AppText.custom(
                      size: 12.5,
                      weight: FontWeight.w500,
                      color: AppColors.textMuted)),
            ],
          ),
        ),
        SizedBox(height: 14.h),
        ClozrCard(
          radius: 16,
          padding: EdgeInsets.all(16.r),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36.r,
                height: 36.r,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: AppColors.borderCardSoft,
                    borderRadius: BorderRadius.circular(8.r)),
                child: Icon(PhosphorIconsRegular.bookOpen,
                    size: 17.sp, color: AppColors.navy),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Assigned courses',
                        style: AppText.custom(
                            size: 14,
                            weight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    SizedBox(height: 3.h),
                    Text(
                        '${l.completed} of ${l.assigned} completed. Open a course to see who has finished it, or use '
                        'Assign course to add another.',
                        style: AppText.custom(
                            size: 12.5,
                            weight: FontWeight.w500,
                            color: AppColors.textMuted,
                            height: 1.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
