import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/lms_providers.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/learner_record.dart';
import '../../domain/lms_logic.dart';
import '../components/lms_footer.dart';
import '../components/lms_header.dart';
import '../components/lms_progress_bar.dart';
import '../lms_nav.dart';

/// Video Lesson — the player card (play/pause, progress, Expand, Play Next),
/// resources, description and the Mark-as-Completed action → certificate card
/// when the whole course finishes.
class LmsPlayerScreen extends ConsumerStatefulWidget {
  const LmsPlayerScreen({super.key});

  @override
  ConsumerState<LmsPlayerScreen> createState() => _LmsPlayerScreenState();
}

class _LmsPlayerScreenState extends ConsumerState<LmsPlayerScreen> {
  int? _idx;
  bool _playing = false;

  void _toast(String m) => ref.read(toastProvider.notifier).show(m);

  void _togglePlay(String courseId, CourseProgress entry, int idx) {
    if (!_playing && (idx < entry.mods.length ? entry.mods[idx] : 0) < 35) {
      ref.read(lmsRecordsControllerProvider.notifier).setModule('me', courseId, idx, 35);
    }
    setState(() => _playing = !_playing);
  }

  void _markDone(String courseId, int idx) {
    ref.read(lmsRecordsControllerProvider.notifier).setModule('me', courseId, idx, 100);
    setState(() => _playing = false);
    _toast('Module completed');
  }

  void _playNext(Course c, CourseProgress entry, int idx) {
    if (idx >= c.modules.length - 1) {
      _toast('This is the last module');
      return;
    }
    if (LmsLogic.lockedAt(entry, c, idx + 1)) {
      _toast('Mark this module as completed first');
      return;
    }
    setState(() {
      _idx = idx + 1;
      _playing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = GoRouterState.of(context).uri.queryParameters;
    // Fall back to the learner's first in-progress course when the player is
    // opened without a lesson context (e.g. a direct deep link).
    final courseId = (query['id']?.isNotEmpty ?? false) ? query['id']! : 'LC-01';
    _idx ??= int.tryParse(query['m'] ?? '0') ?? 0;

    final course = ref.watch(lmsCourseByIdProvider(courseId));
    final record = ref.watch(lmsRecordByIdProvider('me'));
    final entry = record.entryFor(courseId);
    final load = lmsCombine([
      ref.watch(lmsCoursesControllerProvider),
      ref.watch(lmsRecordsControllerProvider),
    ]);

    if (course == null || entry == null) {
      return Container(
        color: AppColors.bgScreen,
        child: Column(
          children: [
            LmsHeader(onBack: () => lmsBack(context), title: Text('Lesson', style: AppText.h1())),
            Expanded(
              child: load.loading
                  ? const DetailSkeleton()
                  : load.error != null
                      ? ErrorState.forError(load.error!, onRetry: () => reloadLms(ref))
                      : const EmptyState(
                          icon: PhosphorIconsRegular.playCircle,
                          title: 'Lesson not found',
                          body: 'This lesson is no longer available, or you are not enrolled in this course.',
                        ),
            ),
          ],
        ),
      );
    }

    final idx = _idx!.clamp(0, course.modules.length - 1);
    final m = course.modules[idx];
    final p = idx < entry.mods.length ? entry.mods[idx] : 0;
    final moduleDone = p >= 100;
    final courseDone = LmsLogic.done(entry);
    final coursePct = LmsLogic.pct(entry);
    final completedModules = entry.mods.where((x) => x >= 100).length;
    final hasNext = idx < course.modules.length - 1;

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          LmsHeader(
            onBack: () => lmsBack(context),
            title: Text(course.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.custom(size: 20, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 40.h),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text('$completedModules of ${course.modules.length} modules completed',
                          style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textMuted)),
                    ),
                    if (course.deadline.isNotEmpty)
                      Text('Deadline: ${course.deadline}',
                          style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                  ],
                ),
                SizedBox(height: 9.h),
                Row(
                  children: [
                    Expanded(child: LmsProgressBar(value: coursePct / 100, color: courseDone ? AppColors.success : AppColors.warning)),
                    SizedBox(width: 10.w),
                    Text('$coursePct%', style: AppText.custom(size: 12.5, weight: FontWeight.w800, color: AppColors.textPrimary)),
                  ],
                ),
                SizedBox(height: 16.h),
                _playerCard(course, m, idx, p, moduleDone),
                if (hasNext)
                  GestureDetector(
                    onTap: () => _playNext(course, entry, idx),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(4.w, 13.h, 4.w, 2.h),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('Play Next', style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textSecondary)),
                          SizedBox(width: 6.w),
                          Icon(PhosphorIconsBold.caretRight, size: 14.sp, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                if (m.res.isNotEmpty) ...[
                  SizedBox(height: 14.h),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8.w,
                    runSpacing: 8.h,
                    children: [
                      Text('Resources :', style: AppText.custom(size: 15, weight: FontWeight.w800, color: AppColors.textPrimary)),
                      for (final r in m.res)
                        GestureDetector(
                          onTap: () => _toast('Opening $r'),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(PhosphorIconsFill.filePdf, size: 15.sp, color: AppColors.error),
                              SizedBox(width: 6.w),
                              Text(r,
                                  style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.blueBright)
                                      .copyWith(decoration: TextDecoration.underline)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
                SizedBox(height: 13.h),
                Text(course.desc,
                    style: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textLabelAlt, height: 1.65)),
                if (courseDone) ...[
                  SizedBox(height: 18.h),
                  _certificateCard(),
                ],
              ],
            ),
          ),
          LmsFooter(
            child: moduleDone
                ? Container(
                    height: 50.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.tintGreen, borderRadius: BorderRadius.circular(14.r)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsFill.checkCircle, size: 18.sp, color: AppColors.success),
                        SizedBox(width: 8.w),
                        Text('Module completed', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.success)),
                      ],
                    ),
                  )
                : LmsCtaButton(
                    label: 'Mark as Completed',
                    icon: PhosphorIconsBold.check,
                    onTap: () => _markDone(courseId, idx),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _playerCard(Course course, CourseModule m, int idx, int p, bool moduleDone) {
    final entry = ref.read(lmsRecordByIdProvider('me')).entryFor(course.id)!;
    return GestureDetector(
      onTap: () => _togglePlay(course.id, entry, idx),
      child: Container(
        height: 210.h,
        decoration: BoxDecoration(color: course.tint, borderRadius: BorderRadius.circular(16.r)),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Center(child: Icon(course.icon, size: 56.sp, color: course.accent.withOpacity(0.35))),
            Center(
              child: Container(
                width: 56.w,
                height: 56.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(18.r),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF101828).withOpacity(0.22), blurRadius: 18, offset: const Offset(0, 6)),
                  ],
                ),
                child: Icon(_playing ? PhosphorIconsFill.pause : PhosphorIconsFill.play, size: 24.sp, color: AppColors.navy),
              ),
            ),
            Positioned(
              top: 10.h,
              right: 10.w,
              child: GestureDetector(
                onTap: () => _toast('Fullscreen opens in the real app'),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                  decoration: BoxDecoration(color: AppColors.white.withOpacity(0.85), borderRadius: BorderRadius.circular(9.r)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Expand', style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.textSecondary)),
                      SizedBox(width: 6.w),
                      Icon(PhosphorIconsBold.arrowsOutSimple, size: 12.sp, color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14.w,
              right: 14.w,
              bottom: 34.h,
              child: LmsProgressBar(
                value: p / 100,
                color: moduleDone ? AppColors.success : AppColors.warningDeep,
                height: 6,
                track: AppColors.white.withOpacity(0.8),
              ),
            ),
            Positioned(
              left: 14.w,
              bottom: 11.h,
              child: Text('Module ${idx + 1} - ${m.title}',
                  style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: const Color(0xFF2A2C31))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _certificateCard() {
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.symmetric(horizontal: 22.w, vertical: 28.h),
      child: Column(
        children: [
          Container(
            width: 62.r,
            height: 62.r,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.tintAmber, borderRadius: BorderRadius.circular(19.r)),
            child: Icon(PhosphorIconsFill.trophy, size: 30.sp, color: AppColors.warningDeep),
          ),
          SizedBox(height: 12.h),
          Text('Course completed!', style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary)),
          SizedBox(height: 6.h),
          Text('All modules are done. Your certificate is ready.',
              textAlign: TextAlign.center,
              style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted, height: 1.5)),
          SizedBox(height: 14.h),
          GestureDetector(
            onTap: () => _toast('Certificate downloaded'),
            child: Container(
              height: 42.h,
              padding: EdgeInsets.symmetric(horizontal: 18.w),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(12.r)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsFill.downloadSimple, size: 15.sp, color: AppColors.white),
                  SizedBox(width: 7.w),
                  Text('Download certificate', style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
