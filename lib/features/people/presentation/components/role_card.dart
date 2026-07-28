import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/entities/role.dart';

/// A Roles & permissions card — shield glyph + name/LOCKED badge + member
/// count, a description, the visibility scope, and a wrap of capability chips.
class RoleCard extends StatelessWidget {
  const RoleCard({
    super.key,
    required this.role,
    required this.memberCount,
    required this.onTap,
    this.onDelete,
  });

  final Role role;
  final int memberCount;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final countLabel = '$memberCount ${memberCount == 1 ? 'member' : 'members'}';
    return ClozrCard(
      radius: 14,
      padding: EdgeInsets.all(14.r),
      onTap: onTap,
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
                child: Icon(PhosphorIconsRegular.shieldCheck, size: 19.sp, color: AppColors.navy),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(role.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                        ),
                        SizedBox(width: 8.w),
                        _badge(role.locked),
                      ],
                    ),
                    SizedBox(height: 2.h),
                    Text(countLabel, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ],
                ),
              ),
              if (!role.locked && onDelete != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onDelete,
                  child: SizedBox(
                    width: 34.w,
                    height: 34.w,
                    child: Icon(PhosphorIconsRegular.trash, size: 17.sp, color: AppColors.error),
                  ),
                ),
            ],
          ),
          SizedBox(height: 10.h),
          Text(role.desc,
              style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted2, height: 1.5)),
          SizedBox(height: 9.h),
          Row(
            children: [
              Icon(PhosphorIconsRegular.eye, size: 13.sp, color: AppColors.textPlaceholder),
              SizedBox(width: 6.w),
              Flexible(
                child: Text(role.scope,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Wrap(
            spacing: 6.w,
            runSpacing: 6.h,
            children: [for (final c in role.caps) _capChip(c)],
          ),
        ],
      ),
    );
  }

  Widget _badge(bool locked) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: locked ? AppColors.bgChipGrey : AppColors.blueSubtle,
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Text(locked ? 'LOCKED' : 'CUSTOM',
          style: AppText.custom(
              size: 9.5, weight: FontWeight.w700, color: locked ? AppColors.textMuted : AppColors.blueBright, letterSpacing: 0.5)),
    );
  }

  Widget _capChip(String label) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(color: AppColors.blueSubtle, borderRadius: BorderRadius.circular(7.r)),
      child: Text(label, style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: const Color(0xFF35507C))),
    );
  }
}
