import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../domain/entities/conversation.dart';
import '../messages_tokens.dart';

/// One chat bubble — outgoing (right, blue) or incoming (left, white), with an
/// optional TEMPLATE badge and, for outgoing messages, read/sent ticks.
/// Mirrors design lines 5780–5789.
class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, this.onRetry});

  final ChatMessage message;

  /// Tapped when an outgoing bubble that the server rejected offers a retry.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final m = message;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        mainAxisAlignment: m.mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 282.w),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 9.h),
              decoration: BoxDecoration(
                color: m.mine ? AppColors.tintBlue : AppColors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14.r),
                  topRight: Radius.circular(14.r),
                  bottomLeft: Radius.circular(m.mine ? 14.r : 4.r),
                  bottomRight: Radius.circular(m.mine ? 4.r : 14.r),
                ),
                border: Border.all(
                  color: m.mine ? MessagesColors.myBubbleBorder : AppColors.borderCardSoft,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(m.text,
                      style: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textBody)
                          .copyWith(height: 1.5)),
                  if (m.tpl) ...[
                    SizedBox(height: 6.h),
                    _templateBadge(),
                  ],
                  SizedBox(height: 3.h),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: m.mine && m.failed
                        ? [_failedAffordance()]
                        : [
                            Text(m.time,
                                style: AppText.custom(size: 10, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                            if (m.mine) ...[
                              SizedBox(width: 4.w),
                              Icon(PhosphorIconsRegular.checks,
                                  size: 13.sp,
                                  color: m.status == 'read' ? AppColors.blueBright : AppColors.textPlaceholder),
                            ],
                          ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Failed-send affordance: a red "Not delivered · Retry" the user can tap to
  /// re-fire the message (honest about a server rejection — audit M3).
  Widget _failedAffordance() {
    return GestureDetector(
      onTap: onRetry,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsFill.warningCircle, size: 12.sp, color: AppColors.error),
          SizedBox(width: 4.w),
          Text('Not delivered · Retry',
              style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.error)),
        ],
      ),
    );
  }

  Widget _templateBadge() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
      decoration: BoxDecoration(color: AppColors.tintGreen, borderRadius: BorderRadius.circular(6.r)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsFill.sealCheck, size: 10.sp, color: AppColors.success),
          SizedBox(width: 4.w),
          Text('TEMPLATE',
              style: AppText.custom(size: 9.5, weight: FontWeight.w700, color: AppColors.success, letterSpacing: 0.4)),
        ],
      ),
    );
  }
}
