import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/entities/reward.dart';
import '../rewards_tokens.dart';
import 'reward_progress_bar.dart';

/// A single rewards goal card: header (title + date + status pill), a "to
/// achieve" progress block, a "you'll get" reward block, and an optional
/// collapsible list of past periods. Mirrors design lines 4949–4996.
class RewardGoalCard extends StatelessWidget {
  const RewardGoalCard({
    super.key,
    required this.goal,
    required this.expanded,
    required this.onTogglePast,
  });

  final RewardGoal goal;
  final bool expanded;
  final VoidCallback onTogglePast;

  @override
  Widget build(BuildContext context) {
    return ClozrCard(
      padding: EdgeInsets.zero,
      radius: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            _body(),
            if (goal.hasPast) _pastToggle(),
            if (goal.hasPast && expanded)
              for (final row in goal.past) _pastRow(row),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 15.h, 16.w, 13.h),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.bgLight, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(goal.title,
                    style: AppText.custom(size: 15.5, weight: FontWeight.w800, color: AppColors.textPrimary)),
                SizedBox(height: 4.h),
                Row(
                  children: [
                    Icon(PhosphorIconsRegular.calendarBlank, size: 12.sp, color: AppColors.textPlaceholder),
                    SizedBox(width: 5.w),
                    Text(goal.date, style: AppText.caption(color: AppColors.textMuted)),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: 10.w),
          _pill(),
        ],
      ),
    );
  }

  Widget _body() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 13.h, 16.w, 15.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RewardOverline(icon: PhosphorIconsRegular.target, label: 'To achieve'),
          SizedBox(height: 8.h),
          Text(goal.achieveTitle,
              style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 2.h),
          Text(goal.achieveSub, style: AppText.caption(color: AppColors.textMuted)),
          SizedBox(height: 11.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(goal.progLeft,
                    style: AppText.custom(size: 13.5, weight: FontWeight.w800, color: AppColors.textPrimary)),
              ),
              SizedBox(width: 10.w),
              Text(goal.progRight,
                  style: AppText.custom(size: 12, weight: FontWeight.w700, color: RewardsColors.muted)),
            ],
          ),
          SizedBox(height: 7.h),
          RewardProgressBar(pct: goal.progPct),
          Container(
            height: 1,
            margin: EdgeInsets.only(top: 15.h, bottom: 13.h),
            color: AppColors.bgLight,
          ),
          const RewardOverline(icon: PhosphorIconsRegular.gift, label: "You'll get"),
          SizedBox(height: 10.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: goal.rwBg, borderRadius: BorderRadius.circular(12.r)),
                child: Icon(goal.rwIcon, size: 19.sp, color: goal.rwColor),
              ),
              SizedBox(width: 11.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 7.w,
                      runSpacing: 4.h,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(goal.rwTitle,
                            style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                        _valueChip(goal.rwChip),
                      ],
                    ),
                    SizedBox(height: 3.h),
                    Text(goal.rwDesc,
                        style: AppText.caption(color: AppColors.textMuted).copyWith(height: 1.5)),
                  ],
                ),
              ),
            ],
          ),
          if (goal.hasPending) ...[
            SizedBox(height: 11.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 1.h),
                  child: Icon(PhosphorIconsFill.hourglassMedium, size: 13.sp, color: AppColors.warningDeep),
                ),
                SizedBox(width: 7.w),
                Expanded(
                  child: Text(goal.pending,
                      style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.warningDeep)
                          .copyWith(height: 1.45)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _pastToggle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTogglePast,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.bgLight, width: 1)),
        ),
        child: Row(
          children: [
            Icon(expanded ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown,
                size: 11.sp, color: RewardsColors.muted),
            SizedBox(width: 7.w),
            Text('Past periods (${goal.past.length})',
                style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
          ],
        ),
      ),
    );
  }

  Widget _pastRow(RewardPastRow row) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      decoration: const BoxDecoration(
        color: RewardsColors.pastRowBg,
        border: Border(top: BorderSide(color: AppColors.bgLight, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(row.period,
                style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textSecondary)),
          ),
          SizedBox(width: 10.w),
          Text(row.result,
              style: AppText.custom(
                  size: 12,
                  weight: FontWeight.w700,
                  color: row.paid ? AppColors.success : AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _valueChip(String label) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: AppColors.bgScreen,
        borderRadius: BorderRadius.circular(7.r),
        border: Border.all(color: RewardsColors.chipBorder, width: 1),
      ),
      child: Text(label,
          style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textLabelAlt)),
    );
  }

  Widget _pill() {
    late final Color bg;
    late final Color fg;
    late final IconData icon;
    Border? border;
    switch (goal.pill) {
      case RewardPillKind.locked:
        bg = AppColors.bgChipGrey;
        fg = AppColors.textLabelAlt;
        icon = PhosphorIconsFill.lock;
        break;
      case RewardPillKind.achieved:
        bg = AppColors.white;
        fg = AppColors.success;
        icon = PhosphorIconsBold.checkCircle;
        border = Border.all(color: RewardsColors.achievedBorder, width: 1);
        break;
      case RewardPillKind.approved:
        bg = AppColors.tintBlue;
        fg = AppColors.blueBright;
        icon = PhosphorIconsFill.sealCheck;
        break;
    }
    final label = switch (goal.pill) {
      RewardPillKind.locked => 'Locked',
      RewardPillKind.achieved => 'Achieved',
      RewardPillKind.approved => 'Approved',
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 11.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9999),
        border: border,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.sp, color: fg),
          SizedBox(width: 5.w),
          Text(label, style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}
