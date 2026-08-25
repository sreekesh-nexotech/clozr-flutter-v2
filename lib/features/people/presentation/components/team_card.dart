import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../data/mock/mock_users.dart';
import '../../domain/entities/member.dart';
import '../../domain/entities/team.dart';

/// The Teams list card — team glyph + name/zone/count, "Edit" and "Add"
/// buttons, then a hairline over the team lead and an overlapping member-avatar
/// stack.
class TeamCard extends StatelessWidget {
  const TeamCard({
    super.key,
    required this.team,
    required this.membersById,
    required this.onAdd,
    required this.onEdit,
  });

  final Team team;
  final Map<String, Member> membersById;
  final VoidCallback onAdd;
  final VoidCallback onEdit;

  Color _color(String id) => MockUsers.memberColors[id] ?? AppColors.navy;

  @override
  Widget build(BuildContext context) {
    final lead = membersById[team.lead];
    return ClozrCard(
      radius: 14,
      padding: EdgeInsets.all(14.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(11.r)),
                child: Icon(PhosphorIconsRegular.usersThree, size: 19.sp, color: AppColors.navy),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Ellipsised: the row now carries two buttons, so a long
                    // team name has less to work with than it used to.
                    Text(team.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 2.h),
                    Row(
                      children: [
                        Icon(PhosphorIconsRegular.mapPin, size: 11.sp, color: AppColors.textMuted),
                        SizedBox(width: 4.w),
                        Flexible(
                          child: Text('${team.zone} · ${team.countLabel}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              _editButton(),
              SizedBox(width: 8.w),
              _addButton(),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 12)),
          Row(
            children: [
              InitialsAvatar(
                initials: lead?.initials ?? '?',
                size: 34,
                background: _color(team.lead),
                fontSize: 11,
              ),
              SizedBox(width: 11.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lead?.name ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 1.h),
                    Text('TEAM LEAD',
                        style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.4)),
                  ],
                ),
              ),
              SizedBox(width: 10.w),
              AvatarStack(
                size: 28,
                overlap: 8,
                items: [
                  for (final id in team.members) (membersById[id]?.initials ?? '?', _color(id)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Icon-only, unlike "Add": a second labelled button would eat the width the
  /// team name needs, and the pencil sits in the same chrome so the pair still
  /// reads as one control group.
  Widget _editButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onEdit,
      child: Container(
        height: 34.h,
        width: 34.w,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9.r),
          border: Border.all(color: AppColors.borderCard),
        ),
        child: Icon(PhosphorIconsRegular.pencilSimple, size: 15.sp, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _addButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onAdd,
      child: Container(
        height: 34.h,
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9.r),
          border: Border.all(color: AppColors.borderCard),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsRegular.userPlus, size: 14.sp, color: AppColors.textSecondary),
            SizedBox(width: 5.w),
            Text('Add', style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textBody)),
          ],
        ),
      ),
    );
  }
}
