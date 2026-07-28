import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../data/mock/mock_users.dart';
import '../../domain/entities/dash_colors.dart';
import 'dash_section_card.dart';

/// A team-member row: navy initials avatar + name + sub line + a trailing
/// widget (a stat chip, or a two-line value). Shared by the Employee
/// Performance sections across the CRM / Operations / Helpdesk panels.
class DashEmployeeRow extends StatelessWidget {
  const DashEmployeeRow({
    super.key,
    required this.rid,
    required this.sub,
    required this.trailing,
    this.onTap,
  });

  final String rid;
  final String sub;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final user = MockUsers.of(rid);
    return DashHairlineRow(
      onTap: onTap,
      padding: EdgeInsets.symmetric(vertical: 11.h),
      child: Row(
        children: [
          InitialsAvatar(initials: user.initials, size: 34, background: AppColors.navy, fontSize: 12),
          SizedBox(width: 11.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 1.h),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
              ],
            ),
          ),
          SizedBox(width: 10.w),
          trailing,
        ],
      ),
    );
  }
}

/// A small tinted stat chip (e.g. "1 overdue", "2 breaches"). Red tint when
/// [bad], green tint otherwise.
class DashStatChip extends StatelessWidget {
  const DashStatChip({super.key, required this.label, required this.bad});
  final String label;
  final bool bad;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: bad ? DashColors.tintRed : DashColors.tintGreen,
        borderRadius: BorderRadius.circular(7.r),
      ),
      child: Text(label,
          style: AppText.custom(size: 11, weight: FontWeight.w800, color: bad ? DashColors.red : DashColors.green)),
    );
  }
}

/// A trailing two-line value (bold primary + grey caption), used by the CRM
/// employee row (closed value + last-activity time).
class DashTrailingValue extends StatelessWidget {
  const DashTrailingValue({super.key, required this.primary, required this.caption});
  final String primary;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(primary, style: AppText.custom(size: 13.5, weight: FontWeight.w800, color: AppColors.textPrimary)),
        SizedBox(height: 3.h),
        Text(caption, style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
      ],
    );
  }
}
