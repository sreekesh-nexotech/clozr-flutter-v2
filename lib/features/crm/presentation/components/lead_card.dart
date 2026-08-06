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
import '../../domain/entities/lead.dart';

/// The Leads list card — avatar (+ notif badge), name/company/project on the
/// left, status pill / value / time on the right, then a team-avatar row and a
/// call button below a hairline.
class LeadCard extends StatelessWidget {
  const LeadCard({
    super.key,
    required this.lead,
    required this.onTap,
    required this.onCall,
    this.status,
  });

  final Lead lead;

  /// The status pill to render. Pass the org's own stage (name + colour from
  /// `/crm/lead-statuses/`); omit it to fall back to the built-in vocabulary.
  final StatusMeta? status;

  final VoidCallback onTap;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final meta = status ?? StatusMeta$.lead[lead.status] ?? StatusMeta$.lead['new']!;
    final teamIds = lead.team.take(2).toList();
    final more = lead.team.length - teamIds.length;

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
                _avatar(),
                SizedBox(width: 13.w),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(lead.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.custom(size: 17, weight: FontWeight.w700, color: AppColors.textPrimary)),
                            SizedBox(height: 4.h),
                            Text(lead.company ?? '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.body(color: AppColors.textMuted2)),
                            SizedBox(height: 3.h),
                            Text(lead.project,
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
                          Text(lead.value,
                              style: AppText.custom(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
                          SizedBox(height: 5.h),
                          Text(lead.time,
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
              const Spacer(),
              // Compact fixed-size Call button — standardised to the smallest
              // width so it renders identically across every lead-card state
              // (#8), instead of a full-width bar that flexed with the row.
              GestureDetector(
                onTap: onCall,
                child: Container(
                  width: 52.w,
                  height: 48.h,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.blueCta, borderRadius: BorderRadius.circular(12.r)),
                  child: Icon(PhosphorIconsFill.phone, size: 19.sp, color: AppColors.navy),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _avatar() {
    final badge = lead.notif;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 62.w,
          height: 62.w,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(15.r)),
          child: Text(lead.initials,
              style: AppText.custom(size: 17, weight: FontWeight.w700, color: AppColors.navy, letterSpacing: 0.4)),
        ),
        if (badge > 0)
          Positioned(
            top: -6.h,
            right: -6.w,
            child: Container(
              constraints: BoxConstraints(minWidth: 22.w),
              height: 22.w,
              padding: EdgeInsets.symmetric(horizontal: 5.w),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(11.r),
                border: Border.all(color: AppColors.white, width: 2),
              ),
              child: Text('$badge',
                  style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.white)),
            ),
          ),
      ],
    );
  }
}
