import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../domain/entities/app_notification.dart';

/// A single notification row: icon chip, title/body, urgent pill + category ·
/// time meta, deep-link affordance, unread dot, overflow menu.
class NotificationRow extends StatelessWidget {
  const NotificationRow({
    super.key,
    required this.notif,
    required this.onOpen,
    required this.onMenu,
  });

  final AppNotification notif;
  final VoidCallback onOpen;
  final VoidCallback onMenu;

  String get _targetLabel {
    switch (notif.targetKind) {
      case 'lead':
        return 'Open lead';
      case 'payment':
        return 'Open payment';
      case 'followup':
        return 'Open follow-up';
      case 'opstask':
        return 'Open task';
      case 'ticket':
        return 'Open ticket';
      case 'quote':
        return 'Open quote';
      case 'project':
        return 'Open project';
      case 'list':
        return 'Open';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: Container(
        margin: EdgeInsets.only(bottom: 8.h),
        padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 14.h),
        decoration: BoxDecoration(
          color: notif.unread ? AppColors.white : AppColors.white,
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: AppColors.borderCardSoft),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38.w,
              height: 38.w,
              decoration: BoxDecoration(color: notif.iconBg, borderRadius: BorderRadius.circular(11.r)),
              child: Icon(notif.icon, size: 19.sp, color: notif.iconColor),
            ),
            SizedBox(width: 11.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notif.title,
                      style: AppText.custom(
                          size: 14,
                          weight: notif.unread ? FontWeight.w700 : FontWeight.w600,
                          color: AppColors.textPrimary)),
                  SizedBox(height: 3.h),
                  Text(notif.body,
                      style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted2)
                          .copyWith(height: 1.45)),
                  SizedBox(height: 8.h),
                  // The meta line is "Urgent · Category · time … Open X →".
                  // The left cluster is Expanded rather than followed by a
                  // Spacer: a Spacer only distributes slack, so once the
                  // natural widths exceeded the row (Urgent + a long category
                  // + a long target label) it overflowed. Expanded hands the
                  // cluster exactly the space left by the trailing action —
                  // identical layout when everything fits — and the category
                  // ellipsizes instead of overflowing when it does not.
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            if (notif.urgent) ...[
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
                                decoration: BoxDecoration(color: AppColors.tintRed, borderRadius: BorderRadius.circular(7.r)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(PhosphorIconsFill.warning, size: 10.sp, color: AppColors.error),
                                    SizedBox(width: 4.w),
                                    Text('Urgent',
                                        style: AppText.custom(size: 10.5, weight: FontWeight.w800, color: AppColors.error)),
                                  ],
                                ),
                              ),
                              SizedBox(width: 8.w),
                            ],
                            Flexible(
                              child: Text(notif.categoryLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.custom(size: 11, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                            ),
                            SizedBox(width: 6.w),
                            Text('·', style: AppText.custom(size: 11, weight: FontWeight.w500, color: const Color(0xFFC2C6CD))),
                            SizedBox(width: 6.w),
                            Text(notif.time,
                                style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                          ],
                        ),
                      ),
                      if (notif.hasTarget) ...[
                        SizedBox(width: 8.w),
                        Text('$_targetLabel →',
                            style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.blueBright)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 4.w),
            Column(
              children: [
                Container(
                  width: 8.w,
                  height: 8.w,
                  decoration: BoxDecoration(
                    color: notif.unread ? AppColors.blueBright : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(height: 6.h),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onMenu,
                  child: SizedBox(
                    width: 30.w,
                    height: 30.w,
                    child: Icon(PhosphorIconsBold.dotsThreeVertical, size: 16.sp, color: AppColors.textPlaceholder),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
