import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../domain/entities/customer.dart';

/// The Customers list card — mirrors the lead card: rounded-square avatar,
/// name/company/project on the left, status pill / value / time on the right,
/// then a team-avatar row and a call button below a hairline.
class CustomerCard extends StatelessWidget {
  const CustomerCard({super.key, required this.customer, required this.onTap, required this.onCall});

  final Customer customer;
  final VoidCallback onTap;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final meta = StatusMeta$.customer[customer.status] ?? StatusMeta$.customer['active']!;
    final teamIds = customer.team.take(2).toList();
    final more = customer.team.length - teamIds.length;

    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 62.w,
                  height: 62.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(15.r)),
                  child: Text(customer.initials,
                      style: AppText.custom(size: 17, weight: FontWeight.w700, color: AppColors.navy, letterSpacing: 0.4)),
                ),
                SizedBox(width: 13.w),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(customer.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.custom(size: 17, weight: FontWeight.w700, color: AppColors.textPrimary)),
                            SizedBox(height: 4.h),
                            Text(customer.company ?? '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.body(color: AppColors.textMuted2)),
                            SizedBox(height: 3.h),
                            Text(customer.project,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                          ],
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          StatusPill.meta(meta),
                          SizedBox(height: 5.h),
                          Text(customer.value,
                              style: AppText.custom(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
                          SizedBox(height: 5.h),
                          Text(customer.time,
                              style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 14)),
          Row(
            children: [
              AvatarStack(
                size: 26,
                items: [for (final id in teamIds) (MockUsers.of(id).initials, MockUsers.of(id).color)],
              ),
              SizedBox(width: 9.w),
              Text(more > 0 ? '+$more more' : 'Team',
                  style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
              SizedBox(width: 12.w),
              Expanded(
                child: GestureDetector(
                  onTap: onCall,
                  child: Container(
                    height: 48.h,
                    decoration: BoxDecoration(color: AppColors.blueCta, borderRadius: BorderRadius.circular(12.r)),
                    child: Icon(PhosphorIconsFill.phone, size: 19.sp, color: AppColors.navy),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
