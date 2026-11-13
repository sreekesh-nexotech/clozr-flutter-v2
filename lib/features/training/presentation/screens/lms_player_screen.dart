import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/status_meta.dart';
import '../../application/providers/mandatory_block_provider.dart';
import '../../application/providers/my_training_providers.dart';
import '../../domain/entities/my_course.dart';
import '../components/lms_header.dart';
import '../components/lms_progress_bar.dart';
import '../components/lms_video_player.dart';
import '../lms_nav.dart';

/// Webapp `LessonPlayerScreen` (`/training/watch/:enrollment`): course
/// progress, the selected lesson's video, its resources and the "Course
/// content" rail with sequential locks — all from the learner's own
/// enrolment, so it works for every learner, admin or not.
class LmsPlayerScreen extends ConsumerStatefulWidget {
  const LmsPlayerScreen({super.key});

  @override
  ConsumerState<LmsPlayerScreen> createState() => _LmsPlayerScreenState();
}

class _LmsPlayerScreenState extends ConsumerState<LmsPlayerScreen> {
  String _selectedId = '';
  bool _blockCleared = false;

  static String _statusKey(String s) => switch (s) {
        'in_progress' => 'inprogress',
        'not_started' => 'notstarted',
        'completed' => 'completed',
        'overdue' => 'overdue',
        _ => 'notstarted',
      };

  static String _fmt(int s) =>
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  /// Webapp: lift the app-wide mandatory block once this course reaches 100%.
  void _maybeClearBlock(MyCourseDetail course) {
    if (_blockCleared || course.completion < 100) return;
    final block = ref.read(mandatoryBlockProvider);
    final listed = block.courses.any((c) => c.courseId == course.courseId);
    if (course.isMandatory || listed) {
      _blockCleared = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(mandatoryBlockProvider.notifier).clearBlock();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final enrollmentId =
        GoRouterState.of(context).uri.queryParameters['enrollment'] ?? '';
    final async = ref.watch(myCourseDetailProvider(enrollmentId));
    final course = async.valueOrNull;

    Widget header(String title, {bool gone = false}) => LmsHeader(
          onBack: () {
            // The list still holds the card that led here; drop it.
            if (gone) ref.read(myTrainingRefreshProvider.notifier).state++;
            lmsBack(context, fallback: Routes.lmsMy);
          },
          title: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.custom(
                  size: 20,
                  weight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.4)),
        );

    if (course == null) {
      final e = async.error;
      return Container(
        color: AppColors.bgScreen,
        child: Column(
          children: [
            header('Lesson player', gone: !async.isLoading),
            Expanded(
              child: async.isLoading
                  ? const DetailSkeleton()
                  : Padding(
                      padding: EdgeInsets.all(24.r),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            enrollmentId.isEmpty ||
                                    e == null ||
                                    (e is AppError &&
                                        e.type == AppErrorType.notFound)
                                ? 'Course not found.'
                                : (e is AppError
                                    ? e.message
                                    : 'Course not found.'),
                            style: AppText.custom(
                                size: 14,
                                weight: FontWeight.w500,
                                color: AppColors.textMuted),
                          ),
                          SizedBox(height: 16.h),
                          // A removed course is usually reached from a stale card or a
                          // link, where Back may lead nowhere useful.
                          GestureDetector(
                            onTap: () {
                              ref
                                  .read(myTrainingRefreshProvider.notifier)
                                  .state++;
                              context.go(Routes.lmsMy);
                            },
                            child: Container(
                              height: 42.h,
                              padding: EdgeInsets.symmetric(horizontal: 16.w),
                              decoration: BoxDecoration(
                                color: AppColors.white,
                                borderRadius: BorderRadius.circular(11.r),
                                border:
                                    Border.all(color: AppColors.borderInput),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(PhosphorIconsBold.arrowLeft,
                                      size: 15.sp,
                                      color: AppColors.textSecondary),
                                  SizedBox(width: 8.w),
                                  Text('Back to My Trainings',
                                      style: AppText.custom(
                                          size: 13.5,
                                          weight: FontWeight.w700,
                                          color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      );
    }

    _maybeClearBlock(course);
    final videos = course.videos;
    final firstOpen = videos.where((v) => v.isUnlocked && !v.isCompleted);
    final firstUnlocked = videos.where((v) => v.isUnlocked);
    final defaultId = firstOpen.isNotEmpty
        ? firstOpen.first.videoResourceId
        : (firstUnlocked.isNotEmpty
            ? firstUnlocked.first.videoResourceId
            : (videos.isEmpty ? '' : videos.first.videoResourceId));
    final activeId = _selectedId.isNotEmpty ? _selectedId : defaultId;
    final selected =
        videos.where((v) => v.videoResourceId == activeId).firstOrNull;
    final moduleOf = course.modules
        .where((m) => m.videos.any((v) => v.videoResourceId == activeId))
        .firstOrNull;
    final locked = selected != null && !selected.isUnlocked;
    final total = course.modules.fold<int>(0, (s, m) => s + m.totalVideos);
    final done = course.modules.fold<int>(0, (s, m) => s + m.completedVideos);
    final pct = course.completion.round();

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          header(course.title),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 40.h),
              children: [
                ClozrCard(
                  radius: 16,
                  padding: EdgeInsets.all(16.r),
                  child: Column(
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
                                Text('$done of $total lessons completed',
                                    style: AppText.custom(
                                        size: 12.5,
                                        weight: FontWeight.w500,
                                        color: AppColors.textMuted)),
                              ],
                            ),
                          ),
                          StatusPill.meta(
                              StatusMeta$.lms[_statusKey(course.status)]!),
                        ],
                      ),
                      SizedBox(height: 13.h),
                      Row(
                        children: [
                          Expanded(
                              child: LmsProgressBar(
                                  value: pct / 100,
                                  color: AppColors.warning,
                                  height: 8)),
                          SizedBox(width: 10.w),
                          Text('$pct%',
                              style: AppText.custom(
                                  size: 13,
                                  weight: FontWeight.w800,
                                  color: AppColors.textPrimary)),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 18.h),
                Text(course.title,
                    style: AppText.custom(
                        size: 18,
                        weight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                if (selected != null) ...[
                  SizedBox(height: 3.h),
                  Text(
                      '${moduleOf != null ? '${moduleOf.title} · ' : ''}${selected.title}',
                      style: AppText.custom(
                          size: 13,
                          weight: FontWeight.w500,
                          color: AppColors.textMuted)),
                ],
                SizedBox(height: 12.h),
                ClozrCard(
                  radius: 14,
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14.r),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _frame(course, selected, locked),
                        if (selected != null && !locked) _lessonMeta(selected),
                        if (selected != null && !locked && selected.hasVideo)
                          _resources(selected, course),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16.h),
                ClozrCard(
                    radius: 14,
                    padding: EdgeInsets.zero,
                    child: _rail(course, activeId, done, total)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dark(Widget child) => Container(
        constraints: BoxConstraints(minHeight: 200.h),
        color: const Color(0xFF0B1020),
        alignment: Alignment.center,
        padding: EdgeInsets.all(20.r),
        child: child,
      );

  Widget _darkText(String t, {double size = 14, double alpha = 0.82}) => Text(t,
      textAlign: TextAlign.center,
      style: AppText.custom(
          size: size,
          weight: FontWeight.w600,
          color: AppColors.white.withOpacity(alpha)));

  Widget _frame(MyCourseDetail course, MyCourseVideo? selected, bool locked) {
    if (selected == null || locked) {
      return _dark(Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
              locked
                  ? PhosphorIconsRegular.lock
                  : PhosphorIconsRegular.playCircle,
              size: 44.sp,
              color: AppColors.white.withOpacity(0.82)),
          SizedBox(height: 10.h),
          _darkText(locked ? 'This lesson is locked' : 'No lesson selected',
              size: 15),
          if (locked) ...[
            SizedBox(height: 6.h),
            _darkText('Complete the previous lessons to unlock this one.',
                size: 13, alpha: 0.6),
          ],
        ],
      ));
    }
    final view = ref.watch(
        videoViewProvider((selected.videoResourceId, course.enrollmentId)));
    return view.when(
      loading: () => _dark(_darkText('Loading video…', alpha: 0.7)),
      error: (e, _) => _dark(_darkText(
          e is AppError ? e.message : 'This video could not be loaded.')),
      data: (v) => v.videoUrl.isEmpty
          ? _dark(_darkText('This video could not be loaded.'))
          : LmsVideoPlayer(
              key: ValueKey(v.videoResourceId),
              view: v,
              enrollmentId: course.enrollmentId,
              onCompleted: () =>
                  ref.read(myTrainingRefreshProvider.notifier).state++,
            ),
    );
  }

  Widget _lessonMeta(MyCourseVideo v) => Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.borderCardSoft))),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12.w,
          runSpacing: 6.h,
          children: [
            Text(v.title,
                style: AppText.custom(
                    size: 14.5,
                    weight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            Text(_fmt(v.durationSeconds),
                style: AppText.custom(
                    size: 12.5,
                    weight: FontWeight.w500,
                    color: AppColors.textPlaceholder)),
            if (v.isCompleted)
              Container(
                height: 28.h,
                padding: EdgeInsets.symmetric(horizontal: 10.w),
                decoration: BoxDecoration(
                    color: AppColors.tintGreen,
                    borderRadius: BorderRadius.circular(8.r)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsFill.checkCircle,
                        size: 14.sp, color: AppColors.success),
                    SizedBox(width: 5.w),
                    Text('Completed',
                        style: AppText.custom(
                            size: 12.5,
                            weight: FontWeight.w700,
                            color: AppColors.success)),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _resources(MyCourseVideo v, MyCourseDetail course) {
    final res = ref
            .watch(videoViewProvider((v.videoResourceId, course.enrollmentId)))
            .valueOrNull
            ?.resources ??
        const [];
    if (res.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.borderCardSoft))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Resources',
              style: AppText.custom(
                  size: 13,
                  weight: FontWeight.w700,
                  color: AppColors.textMuted)),
          for (final r in res)
            GestureDetector(
              onTap: () => launchUrl(Uri.parse(r.fileUrl),
                  mode: LaunchMode.externalApplication),
              child: Padding(
                padding: EdgeInsets.only(top: 8.h),
                child: Row(
                  children: [
                    Icon(PhosphorIconsRegular.fileText,
                        size: 16.sp, color: AppColors.navy),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(r.title,
                          style: AppText.custom(
                              size: 14,
                              weight: FontWeight.w600,
                              color: AppColors.navy)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Webapp `CourseContentRail`.
  Widget _rail(MyCourseDetail course, String activeId, int done, int total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          decoration: const BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: AppColors.borderCardSoft))),
          child: Row(
            children: [
              Expanded(
                child: Text('Course content',
                    style: AppText.custom(
                        size: 15.5,
                        weight: FontWeight.w800,
                        color: AppColors.textPrimary)),
              ),
              Text('$done/$total done',
                  style: AppText.custom(
                      size: 12,
                      weight: FontWeight.w600,
                      color: AppColors.textPlaceholder)),
            ],
          ),
        ),
        for (final m in course.modules) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 4.h),
            child: Row(
              children: [
                Expanded(
                  child: Text(m.title.toUpperCase(),
                      style: AppText.custom(
                          size: 11.5,
                          weight: FontWeight.w700,
                          color: AppColors.textPlaceholder,
                          letterSpacing: 0.4)),
                ),
                if (m.isLocked)
                  Icon(PhosphorIconsRegular.lock,
                      size: 13.sp, color: AppColors.textPlaceholder),
              ],
            ),
          ),
          for (final v in m.videos) _railRow(v, v.videoResourceId == activeId),
        ],
        SizedBox(height: 8.h),
      ],
    );
  }

  Widget _railRow(MyCourseVideo v, bool active) {
    final locked = !v.isUnlocked;
    final (icon, color) = v.isCompleted
        ? (PhosphorIconsFill.checkCircle, AppColors.success)
        : locked
            ? (PhosphorIconsRegular.lock, AppColors.textPlaceholder)
            : active
                ? (PhosphorIconsFill.play, AppColors.navy)
                : (PhosphorIconsRegular.circle, AppColors.navy);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap:
          locked ? null : () => setState(() => _selectedId = v.videoResourceId),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: active ? AppColors.blueSubtle : Colors.transparent,
          border:
              Border.all(color: active ? AppColors.navy : Colors.transparent),
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17.sp, color: color),
            SizedBox(width: 11.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v.title,
                      style: AppText.custom(
                          size: 13,
                          weight: FontWeight.w600,
                          color: locked
                              ? AppColors.textPlaceholder
                              : AppColors.textPrimary)),
                  SizedBox(height: 2.h),
                  Text(_fmt(v.durationSeconds),
                      style: AppText.custom(
                          size: 11,
                          weight: FontWeight.w500,
                          color: AppColors.textPlaceholder)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
