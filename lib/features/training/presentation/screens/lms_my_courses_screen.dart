import 'dart:async';

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
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/status_meta.dart';
import '../../application/providers/my_training_providers.dart';
import '../../domain/entities/my_course.dart';
import '../components/lms_header.dart';
import '../components/lms_progress_bar.dart';
import '../components/lms_search_field.dart';
import '../lms_nav.dart';

/// Webapp `MyTrainingsScreen`: the signed-in user's own published enrolments
/// (`GET /lms/my-courses/`) — search, the "My progress" card with Continue
/// learning, then "Courses in progress" and "Completed". Open to every user on
/// the LMS plan; never reads the admin-only course list.
class LmsMyCoursesScreen extends ConsumerStatefulWidget {
  const LmsMyCoursesScreen({super.key});

  @override
  ConsumerState<LmsMyCoursesScreen> createState() => _LmsMyCoursesScreenState();
}

class _LmsMyCoursesScreenState extends ConsumerState<LmsMyCoursesScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) ref.read(myCoursesSearchProvider.notifier).state = v.trim();
    });
  }

  void _open(String enrollmentId) =>
      context.push('${Routes.lmsPlayer}?enrollment=$enrollmentId');

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(myCoursesSearchProvider);
    final async = ref.watch(myCoursesProvider(search));
    // Keep the last page on screen while a new search loads (webapp
    // keepPreviousData), so the progress card does not flash to zero.
    final page = async.valueOrNull;

    Widget body;
    if (page == null && async.isLoading) {
      body = const ListSkeleton();
    } else if (page == null && async.hasError) {
      final e = async.error;
      body = ListView(children: [
        ErrorState.forError(
          e is AppError
              ? e
              : const AppError(
                  type: AppErrorType.unknown,
                  message: 'Something went wrong. Please try again.'),
          onRetry: () => ref.invalidate(myCoursesProvider(search)),
        ),
      ]);
    } else {
      body = RefreshIndicator(
        onRefresh: () => ref.refresh(myCoursesProvider(search).future),
        child: _content(page ?? const MyCoursesPage(results: []), search),
      );
    }

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          LmsHeader(
            onBack: () => lmsBack(context, fallback: Routes.lmsMy),
            title: Text('My Trainings',
                style: AppText.custom(
                    size: 22,
                    weight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.4)),
            bottom: LmsSearchField(
                controller: _searchCtrl,
                hint: 'Search courses..',
                onChanged: _onSearch),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _content(MyCoursesPage page, String search) {
    final results = page.results;
    final done = results.where((c) => c.isCompleted).length;
    final overall = results.isEmpty
        ? 0
        : (results.map((c) => c.completion).reduce((a, b) => a + b) /
                results.length)
            .round();
    final inProgress = results.where((c) => !c.isCompleted).toList();
    final completed = results.where((c) => c.isCompleted).toList();
    // The server can name a last-watched enrolment that is no longer listed
    // (its course went back to draft); resuming it would only reach "Course
    // not found.", so fall back to the first course still in progress.
    final lastWatched = page.lastWatchedEnrollmentId;
    final continueId =
        lastWatched != null && results.any((c) => c.enrollmentId == lastWatched)
            ? lastWatched
            : (inProgress.isEmpty ? null : inProgress.first.enrollmentId);
    final allDone = results.isNotEmpty && done == results.length;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('My progress',
                            style: AppText.custom(
                                size: 16,
                                weight: FontWeight.w800,
                                color: AppColors.textPrimary)),
                        SizedBox(height: 2.h),
                        Text('$done of ${results.length} courses completed',
                            style: AppText.custom(
                                size: 12.5,
                                weight: FontWeight.w500,
                                color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  if (results.isNotEmpty)
                    StatusPill.meta(
                        StatusMeta$.lms[allDone ? 'completed' : 'inprogress']!),
                ],
              ),
              if (continueId != null) ...[
                SizedBox(height: 12.h),
                GestureDetector(
                  onTap: () => _open(continueId),
                  child: Container(
                    height: 40.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: AppColors.navy,
                        borderRadius: BorderRadius.circular(10.r)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsFill.play,
                            size: 15.sp, color: AppColors.white),
                        SizedBox(width: 7.w),
                        Text('Continue learning',
                            style: AppText.custom(
                                size: 13.5,
                                weight: FontWeight.w700,
                                color: AppColors.white)),
                      ],
                    ),
                  ),
                ),
              ],
              SizedBox(height: 13.h),
              Row(
                children: [
                  Expanded(
                      child: LmsProgressBar(
                          value: overall / 100,
                          color: AppColors.warning,
                          height: 8)),
                  SizedBox(width: 10.w),
                  Text('$overall%',
                      style: AppText.custom(
                          size: 13,
                          weight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                ],
              ),
            ],
          ),
        ),
        if (results.isEmpty)
          EmptyState(
            icon: search.isEmpty
                ? PhosphorIconsFill.graduationCap
                : PhosphorIconsRegular.magnifyingGlass,
            title: search.isEmpty
                ? 'No training assigned to you yet'
                : 'No courses match your search',
            body: '',
          ),
        if (inProgress.isNotEmpty) ...[
          _sectionTitle('Courses in progress'),
          for (final c in inProgress) _card(c),
        ],
        if (completed.isNotEmpty) ...[
          _sectionTitle('Completed'),
          for (final c in completed) _card(c),
        ],
      ],
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: EdgeInsets.fromLTRB(2.w, 22.h, 2.w, 10.h),
        child: Text(t,
            style: AppText.custom(
                size: 17,
                weight: FontWeight.w800,
                color: AppColors.textPrimary)),
      );

  Widget _badge(String text, Color fg, Color bg, {bool dot = true}) =>
      Container(
        height: 24.h,
        padding: EdgeInsets.symmetric(horizontal: 9.w),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot) ...[
              Container(
                  width: 7.r,
                  height: 7.r,
                  decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
              SizedBox(width: 5.w),
            ],
            Text(text,
                style: AppText.custom(
                    size: 11.5, weight: FontWeight.w700, color: fg)),
          ],
        ),
      );

  /// Webapp `MyCourseCard`.
  Widget _card(MyCourse c) {
    final pct = c.completion.round();
    final bar = c.isCompleted
        ? AppColors.success
        : (c.isOverdue ? AppColors.error : AppColors.warning);
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: ClozrCard(
        radius: 14,
        padding: EdgeInsets.zero,
        onTap: () => _open(c.enrollmentId),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14.r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 150.h,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: c.thumbnailUrl.isEmpty
                          ? _noThumb()
                          : Image.network(c.thumbnailUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _noThumb()),
                    ),
                    if (c.isOverdue)
                      Positioned(
                          top: 10.h,
                          right: 10.w,
                          child: _badge(
                              'Overdue', AppColors.error, AppColors.tintRed)),
                    if (c.isCompleted)
                      Positioned(
                          top: 10.h,
                          right: 10.w,
                          child: _badge('Completed', AppColors.success,
                              AppColors.tintGreen)),
                    if (c.isMandatory)
                      Positioned(
                        bottom: 10.h,
                        left: 10.w,
                        child: _badge('Required', AppColors.textPrimary,
                            AppColors.white.withOpacity(0.92),
                            dot: false),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(14.r),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(PhosphorIconsFill.play,
                            size: 15.sp, color: AppColors.navy),
                        SizedBox(width: 9.w),
                        Expanded(
                            child: LmsProgressBar(
                                value: pct / 100, color: bar, height: 6)),
                        SizedBox(width: 9.w),
                        Text('$pct%',
                            style: AppText.custom(
                                size: 12,
                                weight: FontWeight.w700,
                                color: AppColors.textMuted)),
                      ],
                    ),
                    SizedBox(height: 9.h),
                    Text(c.title,
                        style: AppText.custom(
                            size: 14,
                            weight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    SizedBox(height: 4.h),
                    Text(
                        c.deadline == null
                            ? 'No deadline'
                            : 'Deadline: ${absoluteDate(c.deadline)}',
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
      ),
    );
  }

  Widget _noThumb() => Container(
        color: AppColors.blueSubtle,
        alignment: Alignment.center,
        child: Icon(PhosphorIconsFill.graduationCap,
            size: 34.sp, color: AppColors.navy),
      );
}
