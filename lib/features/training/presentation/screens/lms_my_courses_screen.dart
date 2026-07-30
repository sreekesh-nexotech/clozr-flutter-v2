import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/lms_providers.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/learner_record.dart';
import '../../domain/lms_logic.dart';
import '../components/lms_header.dart';
import '../components/lms_progress_bar.dart';
import '../lms_nav.dart';

/// My Courses — the current user's progress header, an in-progress carousel
/// (with sequential module locking), a more-courses grid and an all-caught-up
/// state.
class LmsMyCoursesScreen extends ConsumerWidget {
  const LmsMyCoursesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(lmsRecordByIdProvider('me'));
    final courseOf = ref.watch(lmsCourseLookupProvider);

    final entries = <(CourseProgress, Course)>[
      for (final e in record.courses)
        if (courseOf(e.courseId) != null && courseOf(e.courseId)!.isPublished)
          (e, courseOf(e.courseId)!),
    ];
    final doneCount = entries.where((x) => LmsLogic.done(x.$1)).length;
    final avg = entries.isEmpty
        ? 0
        : (entries.map((x) => LmsLogic.pct(x.$1)).reduce((a, b) => a + b) / entries.length).round();
    final allDone = entries.isNotEmpty && doneCount == entries.length;
    final anyOver = entries.any((x) => LmsLogic.statusOf(x.$1, x.$2) == 'overdue');
    final headKey = allDone ? 'completed' : (anyOver ? 'overdue' : 'inprogress');

    final inProg = entries.where((x) => LmsLogic.statusOf(x.$1, x.$2) == 'inprogress').toList();
    final more = entries.where((x) => LmsLogic.statusOf(x.$1, x.$2) != 'inprogress').toList();

    void toast(String m) => ref.read(toastProvider.notifier).show(m);

    final children = <Widget>[
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 18.w),
        child: _progressCard(record, entries, doneCount, avg, headKey, allDone),
      ),
      if (allDone)
        Padding(
          padding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 0),
          child: _allCaughtUp(),
        ),
      for (final x in inProg) ..._inProgressBlock(context, x, toast),
      Padding(
        padding: EdgeInsets.fromLTRB(20.w, 22.h, 20.w, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('More courses', style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary)),
            SizedBox(height: 2.h),
            Text('Complete your assigned courses.',
                style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
          ],
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(18.w, 12.h, 18.w, 0),
        child: _moreGrid(context, more),
      ),
    ];

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          LmsHeader(
            onBack: () => lmsBack(context),
            title: Text('My courses',
                style: AppText.custom(size: 22, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(top: 16.h, bottom: 40.h),
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressCard(
    LearnerRecord record,
    List<(CourseProgress, Course)> entries,
    int doneCount,
    int avg,
    String headKey,
    bool allDone,
  ) {
    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.all(16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('My progress', style: AppText.custom(size: 16, weight: FontWeight.w800, color: AppColors.textPrimary)),
                    SizedBox(height: 2.h),
                    Text('$doneCount of ${entries.length} courses completed',
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ],
                ),
              ),
              SizedBox(width: 10.w),
              StatusPill.meta(StatusMeta$.lms[headKey]!),
            ],
          ),
          SizedBox(height: 13.h),
          Row(
            children: [
              Expanded(child: LmsProgressBar(value: avg / 100, color: allDone ? AppColors.success : AppColors.warning, height: 8)),
              SizedBox(width: 10.w),
              Text('$avg%', style: AppText.custom(size: 13, weight: FontWeight.w800, color: AppColors.textPrimary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _allCaughtUp() {
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.symmetric(horizontal: 22.w, vertical: 34.h),
      child: Column(
        children: [
          Container(
            width: 66.r,
            height: 66.r,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.tintAmber, borderRadius: BorderRadius.circular(20.r)),
            child: Icon(PhosphorIconsFill.trophy, size: 32.sp, color: AppColors.warningDeep),
          ),
          SizedBox(height: 14.h),
          Text("You're All Caught Up!", style: AppText.custom(size: 18, weight: FontWeight.w800, color: AppColors.textPrimary)),
          SizedBox(height: 7.h),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 260.w),
            child: Text(
              "You've completed all your modules and your training is 100% up to date. Great job staying ahead of the curve!",
              textAlign: TextAlign.center,
              style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted, height: 1.55),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _inProgressBlock(BuildContext context, (CourseProgress, Course) x, void Function(String) toast) {
    final e = x.$1;
    final c = x.$2;
    final nextIdx = e.mods.indexWhere((m) => m < 100);
    final idx = nextIdx < 0 ? 0 : nextIdx;
    return [
      Padding(
        padding: EdgeInsets.fromLTRB(20.w, 22.h, 20.w, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.title, style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary)),
                  SizedBox(height: 2.h),
                  Text('Module ${idx + 1} - ${c.modules[idx].title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                ],
              ),
            ),
            SizedBox(width: 10.w),
            if (c.deadline.isNotEmpty)
              Text('Deadline: ${c.deadline}',
                  style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textMuted)),
          ],
        ),
      ),
      SizedBox(
        height: 178.h,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(18.w, 12.h, 18.w, 4.h),
          itemCount: c.modules.length,
          separatorBuilder: (_, __) => SizedBox(width: 12.w),
          itemBuilder: (context, i) => _moduleCard(context, e, c, i, toast),
        ),
      ),
    ];
  }

  Widget _moduleCard(BuildContext context, CourseProgress e, Course c, int i, void Function(String) toast) {
    final locked = LmsLogic.lockedAt(e, c, i);
    final p = i < e.mods.length ? e.mods[i] : 0;
    return GestureDetector(
      onTap: () {
        if (locked) {
          toast('Complete the previous module first');
        } else {
          context.push('${Routes.lmsPlayer}?id=${c.id}&m=$i');
        }
      },
      child: Opacity(
        opacity: locked ? 0.55 : 1,
        child: Container(
          width: 252.w,
          decoration: BoxDecoration(color: c.tint, borderRadius: BorderRadius.circular(14.r)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 118.h,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(c.icon, size: 38.sp, color: c.accent.withOpacity(0.45)),
                    if (!locked)
                      Container(
                        width: 42.w,
                        height: 42.w,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: const Color(0xFF101828).withOpacity(0.18), blurRadius: 12, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: Icon(PhosphorIconsFill.play, size: 18.sp, color: AppColors.navy),
                      )
                    else
                      Container(
                        width: 42.w,
                        height: 42.w,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.textPrimary.withOpacity(0.55),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(PhosphorIconsFill.lock, size: 18.sp, color: AppColors.white),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 12.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LmsProgressBar(
                      value: p / 100,
                      color: p >= 100 ? AppColors.success : AppColors.warningDeep,
                      height: 5,
                      track: AppColors.white.withOpacity(0.75),
                    ),
                    SizedBox(height: 8.h),
                    Text('Module ${i + 1} - ${c.modules[i].title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 12, weight: FontWeight.w700, color: const Color(0xFF2A2C31))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moreGrid(BuildContext context, List<(CourseProgress, Course)> more) {
    final rows = <Widget>[];
    for (int i = 0; i < more.length; i += 2) {
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _moreCard(context, more[i])),
          SizedBox(width: 12.w),
          Expanded(child: i + 1 < more.length ? _moreCard(context, more[i + 1]) : const SizedBox()),
        ],
      ));
      if (i + 2 < more.length) rows.add(SizedBox(height: 12.h));
    }
    return Column(children: rows);
  }

  Widget _moreCard(BuildContext context, (CourseProgress, Course) x) {
    final c = x.$2;
    final st = LmsLogic.statusOf(x.$1, c);
    return ClozrCard(
      radius: 14,
      padding: EdgeInsets.zero,
      onTap: () => context.push('${Routes.lmsPlayer}?id=${c.id}&m=0'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 96.h,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: c.tint,
                      alignment: Alignment.center,
                      child: Icon(c.icon, size: 30.sp, color: c.accent.withOpacity(0.5)),
                    ),
                  ),
                  Positioned(
                    top: 9.h,
                    right: 9.w,
                    child: StatusPill.meta(StatusMeta$.lms[st]!),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 12.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  SizedBox(height: 2.h),
                  Text(c.sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
