import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/status_meta.dart';
import '../lms_style.dart';
import 'lms_progress_bar.dart';

/// The Learners list card: avatar + name/role, aggregate status pill + course
/// count, overall progress bar, next-deadline label and a Nudge button.
class LmsLearnerCard extends StatelessWidget {
  const LmsLearnerCard({
    super.key,
    required this.name,
    required this.initials,
    required this.avatarColor,
    required this.role,
    required this.statusKey,
    required this.pct,
    required this.coursesLabel,
    required this.deadlineLabel,
    required this.overdue,
    required this.onTap,
    required this.onNudge,
  });

  final String name;
  final String initials;
  final Color avatarColor;
  final String role;
  final String statusKey;
  final int pct;
  final String coursesLabel;
  final String deadlineLabel;
  final bool overdue;
  final VoidCallback onTap;
  final VoidCallback onNudge;

  @override
  Widget build(BuildContext context) {
    final meta = StatusMeta$.lms[statusKey]!;

    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.all(14.r),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialsAvatar(
                initials: initials,
                size: 42,
                background: avatarColor,
                foreground: AppColors.white,
                fontSize: 15,
              ),
              SizedBox(width: 11.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 1.h),
                    Text(role, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusPill.meta(meta),
                  SizedBox(height: 4.h),
                  Text(coursesLabel,
                      style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                ],
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(child: LmsProgressBar(value: pct / 100, color: LmsStyle.barColor(statusKey))),
              SizedBox(width: 10.w),
              Text('$pct%',
                  style: AppText.custom(size: 12.5, weight: FontWeight.w800, color: AppColors.textPrimary)),
            ],
          ),
          SizedBox(height: 11.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(deadlineLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(
                        size: 12,
                        weight: overdue ? FontWeight.w700 : FontWeight.w500,
                        color: overdue ? AppColors.error : AppColors.textMuted)),
              ),
              SizedBox(width: 10.w),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onNudge,
                child: Container(
                  height: 34.h,
                  padding: EdgeInsets.symmetric(horizontal: 17.w),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: const Color(0xFFE6E7EA)),
                  ),
                  child: Text('Nudge',
                      style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textSecondary)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
