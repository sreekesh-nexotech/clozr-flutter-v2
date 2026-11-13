import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/status_meta.dart';
import '../../infrastructure/data_sources/local/lms_people.dart';
import '../lms_style.dart';
import 'lms_progress_bar.dart';

/// One webapp Learners table row as a card: initials + name, status pill,
/// role chip, ASSIGNED / COMPLETED / DEADLINE, the progress bar with %, and
/// the View · Nudge actions.
class LmsLearnerCard extends StatelessWidget {
  const LmsLearnerCard({
    super.key,
    required this.name,
    required this.rid,
    required this.role,
    required this.statusKey,
    required this.pct,
    required this.assigned,
    required this.completed,
    required this.deadlineLabel,
    required this.overdue,
    required this.onTap,
    required this.onNudge,
  });

  final String name;
  final String rid;
  final String role;
  final String statusKey;
  final int pct;
  final int assigned;
  final int completed;
  final String deadlineLabel;
  final bool overdue;
  final VoidCallback onTap;
  final VoidCallback onNudge;

  @override
  Widget build(BuildContext context) {
    final meta = StatusMeta$.lms[statusKey] ?? StatusMeta$.lms['notstarted']!;
    final person = LmsPeople.of(rid);

    Widget stat(String label, String value, {Color? color}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: AppText.custom(
                      size: 10.5,
                      weight: FontWeight.w700,
                      color: AppColors.textPlaceholder,
                      letterSpacing: 0.4)),
              SizedBox(height: 3.h),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.custom(
                      size: 13.5,
                      weight: FontWeight.w600,
                      color: color ?? AppColors.textPrimary)),
            ],
          ),
        );

    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.all(14.r),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(
                initials: person.initials,
                size: 40,
                background: person.color,
                foreground: AppColors.white,
                fontSize: 14,
              ),
              SizedBox(width: 11.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(
                            size: 14.5,
                            weight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    SizedBox(height: 4.h),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 9.w, vertical: 3.h),
                      decoration: BoxDecoration(
                        color: AppColors.borderCardSoft,
                        borderRadius: BorderRadius.circular(7.r),
                      ),
                      child: Text(role.isEmpty ? '—' : role,
                          style: AppText.custom(
                              size: 11.5,
                              weight: FontWeight.w700,
                              color: AppColors.textSecondary)),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              StatusPill.meta(meta),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              stat('ASSIGNED', '$assigned'),
              stat('COMPLETED', '$completed'),
              stat('DEADLINE', deadlineLabel,
                  color: overdue ? AppColors.error : null),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                  child: LmsProgressBar(
                      value: pct / 100, color: LmsStyle.barColor(statusKey))),
              SizedBox(width: 10.w),
              Text('$pct%',
                  style: AppText.custom(
                      size: 12.5,
                      weight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _action(
                onTap: onTap,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsRegular.eye,
                        size: 16.sp, color: AppColors.textSecondary),
                    SizedBox(width: 6.w),
                    Text('View',
                        style: AppText.custom(
                            size: 13,
                            weight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              _action(
                onTap: onNudge,
                child: Text('Nudge',
                    style: AppText.custom(
                        size: 13,
                        weight: FontWeight.w700,
                        color: AppColors.textSecondary)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action({required VoidCallback onTap, required Widget child}) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 34.h,
          padding: EdgeInsets.symmetric(horizontal: 15.w),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: const Color(0xFFE6E7EA)),
          ),
          child: child,
        ),
      );
}
