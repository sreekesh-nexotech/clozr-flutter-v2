import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../domain/entities/member.dart';

/// Tone per role — drives the role pill colour. Mirrors the prototype's
/// `ROLETONE` map.
const Map<String, Color> kRoleTone = {
  'System Admin': AppColors.pending,
  'Executive Leadership': AppColors.blueBright,
  'Manager': AppColors.success,
  'Sales executive': AppColors.teal,
  'Viewer': Color(0xFF6C6C6C),
};

Color roleTone(String role) => kRoleTone[role] ?? const Color(0xFF6C6C6C);

({String label, Color color}) memberStatusMeta(String status) => switch (status) {
      'active' => (label: 'Active', color: AppColors.success),
      'inactive' => (label: 'Inactive', color: AppColors.textMuted),
      _ => (label: 'Invited', color: AppColors.warningDeep),
    };

/// The Members list card — navy avatar + name/email on top, status pill on the
/// right, then a role pill + scope, a full-width "Reports to …" row and the
/// member's team.
class MemberCard extends StatelessWidget {
  const MemberCard({super.key, required this.member, required this.onTap});

  final Member member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final st = memberStatusMeta(member.status);
    return ClozrCard(
      radius: 14,
      padding: EdgeInsets.all(13.r),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(
                initials: member.initials,
                size: 46,
                radius: 13,
                background: AppColors.navy,
                fontSize: 14,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(member.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 2.h),
                    Text(member.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              StatusPill(label: st.label, color: st.color),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.only(top: 11, bottom: 11)),
          Row(
            children: [
              _rolePill(member.role),
              SizedBox(width: 8.w),
              Flexible(
                child: Text(member.scope,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          _metaRow(PhosphorIconsRegular.treeStructure, 'Reports to ${member.reportsTo}'),
          SizedBox(height: 6.h),
          _metaRow(PhosphorIconsRegular.usersThree, member.team),
        ],
      ),
    );
  }

  Widget _rolePill(String role) {
    final tone = roleTone(role);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: tone.withOpacity(0.082),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6.w, height: 6.w, decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
          SizedBox(width: 6.w),
          Text(role, style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: tone)),
        ],
      ),
    );
  }

  Widget _metaRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 12.sp, color: AppColors.textPlaceholder),
        SizedBox(width: 5.w),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted2)),
        ),
      ],
    );
  }
}
