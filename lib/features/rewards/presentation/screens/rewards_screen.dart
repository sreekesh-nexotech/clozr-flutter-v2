import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../domain/entities/reward.dart';
import '../../application/providers/rewards_providers.dart';
import '../components/reward_goal_card.dart';
import '../components/reward_progress_bar.dart';
import '../rewards_tokens.dart';

/// My Rewards — a display screen: rewards profile + tier header, a refresh
/// note, the goal cards, and the Closer Track timeline. Recreates design lines
/// 4907–5031. No navigation besides back/drawer.
class RewardsScreen extends ConsumerWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rewardsControllerProvider);
    final data = state.data;
    final expanded = ref.watch(rewardsExpandedProvider);

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          _header(context),
          Expanded(
            child: state.loading
                ? const DetailSkeleton()
                : state.error != null
                    ? ErrorState.forError(
                        state.error!,
                        onRetry: () => ref.read(rewardsControllerProvider.notifier).reload(),
                      )
                    : ListView(
                        padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 110.h),
                        children: [
                          _profileCard(data.profile),
                          SizedBox(height: 12.h),
                          if (data.lastUpdated.isNotEmpty) _refreshNote(data.lastUpdated),
                          if (data.goals.isEmpty)
                            _goalsEmpty()
                          else
                            for (final goal in data.goals) ...[
                              SizedBox(height: 14.h),
                              RewardGoalCard(
                                goal: goal,
                                expanded: expanded.contains(goal.id),
                                onTogglePast: () => _toggle(ref, goal.id),
                              ),
                            ],
                          if (!data.closerTrack.isEmpty) ...[
                            SizedBox(height: 14.h),
                            _closerTrack(data.closerTrack),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  // ── Empty goals ──
  Widget _goalsEmpty() {
    return Padding(
      padding: EdgeInsets.only(top: 8.h),
      child: const EmptyState(
        icon: PhosphorIconsFill.trophy,
        title: 'No rewards yet',
        body: 'Your goals and rewards will appear here once your milestones are set up.',
      ),
    );
  }

  void _toggle(WidgetRef ref, String id) {
    final notifier = ref.read(rewardsExpandedProvider.notifier);
    final next = Set<String>.from(notifier.state);
    next.contains(id) ? next.remove(id) : next.add(id);
    notifier.state = next;
  }

  // ── Header ──
  Widget _header(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 54.h, 16.w, 12.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderCardSoft, width: 1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.canPop() ? context.pop() : context.go(Routes.home),
            child: Padding(
              padding: EdgeInsets.only(right: 4.w),
              child: Icon(PhosphorIconsBold.caretLeft, size: 22.sp, color: AppColors.textPrimary),
            ),
          ),
          Container(
            width: 38.w,
            height: 38.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.tintNavy, borderRadius: BorderRadius.circular(11.r)),
            child: Icon(PhosphorIconsFill.trophy, size: 20.sp, color: AppColors.navy),
          ),
          SizedBox(width: 10.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('My Rewards',
                  style: AppText.custom(
                      size: 20, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
              SizedBox(height: 2.h),
              Text('Goals & rewards · My progress',
                  style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Profile card ──
  Widget _profileCard(RewardProfile p) {
    return ClozrCard(
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48.w,
                height: 48.w,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
                child: Text(p.initials,
                    style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.white)),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary)),
                    SizedBox(height: 1.h),
                    Text(p.role,
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsFill.trophy, size: 15.sp, color: AppColors.warningDeep),
                      SizedBox(width: 5.w),
                      Text('${p.milestones}',
                          style: AppText.custom(size: 19, weight: FontWeight.w800, color: AppColors.textPrimary)),
                    ],
                  ),
                  SizedBox(height: 1.h),
                  Text('MILESTONES ACHIEVED',
                      style: AppText.custom(
                          size: 9, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.7)),
                ],
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Icon(PhosphorIconsBold.arrowElbowDownRight, size: 11.sp, color: AppColors.textPlaceholder),
              SizedBox(width: 5.w),
              Text('Reports to ',
                  style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              Text(p.reportsTo,
                  style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textSecondary)),
            ],
          ),
          SizedBox(height: 12.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 10.h),
            decoration: BoxDecoration(color: AppColors.tintGreen, borderRadius: BorderRadius.circular(12.r)),
            child: Row(
              children: [
                Container(
                  width: 30.w,
                  height: 30.w,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                  child: Icon(PhosphorIconsFill.crownSimple, size: 14.sp, color: AppColors.white),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CURRENT LEVEL',
                          style: AppText.custom(
                              size: 9.5, weight: FontWeight.w700, color: AppColors.textBodyMuted, letterSpacing: 0.7)),
                      SizedBox(height: 1.h),
                      Text(p.currentLevel,
                          style: AppText.custom(size: 13.5, weight: FontWeight.w800, color: AppColors.textPrimary)),
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

  // ── Refresh note ──
  Widget _refreshNote(String lastUpdated) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 11.h),
      decoration: BoxDecoration(color: AppColors.tintBlue, borderRadius: BorderRadius.circular(12.r)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 1.h),
            child: Icon(PhosphorIconsRegular.clock, size: 14.sp, color: AppColors.blueBright),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'Progress refreshes about every 6 hours — not live to the second. Last updated ',
                style: AppText.custom(size: 12, weight: FontWeight.w500, color: RewardsColors.refreshText)
                    .copyWith(height: 1.5),
                children: [
                  TextSpan(
                    text: lastUpdated,
                    style: AppText.custom(size: 12, weight: FontWeight.w700, color: RewardsColors.refreshText),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Closer Track ──
  Widget _closerTrack(CloserTrack track) {
    return ClozrCard(
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.steps, size: 17.sp, color: AppColors.textPrimary),
              SizedBox(width: 8.w),
              Text('Closer Track',
                  style: AppText.custom(size: 15.5, weight: FontWeight.w800, color: AppColors.textPrimary)),
            ],
          ),
          SizedBox(height: 2.h),
          Text('Level-wise journey · unlocks on achievement',
              style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
          SizedBox(height: 13.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 13.h),
            decoration: BoxDecoration(color: AppColors.bgScreen, borderRadius: BorderRadius.circular(13.r)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('UP NEXT',
                    style: AppText.custom(
                        size: 10, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.7)),
                SizedBox(height: 5.h),
                Text(track.upNextTitle,
                    style: AppText.custom(size: 14.5, weight: FontWeight.w800, color: AppColors.textPrimary)),
                SizedBox(height: 2.h),
                Text(track.upNextSub, style: AppText.caption(color: AppColors.textMuted)),
                SizedBox(height: 10.h),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(track.progLeft,
                          style: AppText.custom(size: 13, weight: FontWeight.w800, color: AppColors.textPrimary)),
                    ),
                    SizedBox(width: 10.w),
                    Text(track.progRight,
                        style: AppText.custom(size: 12, weight: FontWeight.w700, color: RewardsColors.muted)),
                  ],
                ),
                SizedBox(height: 7.h),
                RewardProgressBar(pct: track.pct, track: RewardsColors.trackBg),
              ],
            ),
          ),
          SizedBox(height: 16.h),
          for (final level in track.levels) _levelRow(level),
        ],
      ),
    );
  }

  Widget _levelRow(RewardLevel level) {
    final locked = level.kind == RewardLevelKind.locked;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24.w,
            child: Column(
              children: [
                _levelDot(level),
                if (level.hasLine)
                  Expanded(
                    child: Container(
                      width: 2.w,
                      margin: EdgeInsets.symmetric(vertical: 3.h),
                      color: RewardsColors.trackBg,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(level.title,
                            style: AppText.custom(
                                size: 14,
                                weight: FontWeight.w700,
                                color: locked ? AppColors.textPlaceholder : AppColors.textPrimary)),
                      ),
                      if (level.here) ...[
                        SizedBox(width: 7.w),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                          decoration: BoxDecoration(
                              color: AppColors.tintNavy, borderRadius: BorderRadius.circular(6.r)),
                          child: Text('YOU ARE HERE',
                              style: AppText.custom(
                                  size: 9, weight: FontWeight.w800, color: AppColors.navy, letterSpacing: 0.5)),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 2.h),
                  Text.rich(
                    TextSpan(
                      text: level.sub,
                      style: AppText.custom(
                          size: 12,
                          weight: FontWeight.w500,
                          color: locked ? AppColors.textPlaceholder : AppColors.textMuted),
                      children: level.hasTail
                          ? [
                              TextSpan(
                                text: level.subTail,
                                style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.success),
                              ),
                            ]
                          : null,
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

  Widget _levelDot(RewardLevel level) {
    switch (level.kind) {
      case RewardLevelKind.locked:
        return Container(
          width: 24.w,
          height: 24.w,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppColors.bgChipGrey, shape: BoxShape.circle),
          child: Icon(PhosphorIconsFill.lock, size: 11.sp, color: AppColors.textPlaceholder),
        );
      case RewardLevelKind.current:
        return Container(
          width: 24.w,
          height: 24.w,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.navy,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: AppColors.tintNavy, spreadRadius: 3.r, blurRadius: 0),
            ],
          ),
          child: Icon(PhosphorIconsFill.circle, size: 8.sp, color: AppColors.white),
        );
      case RewardLevelKind.done:
        return Container(
          width: 24.w,
          height: 24.w,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
          child: Icon(PhosphorIconsBold.check, size: 11.sp, color: AppColors.white),
        );
    }
  }
}
