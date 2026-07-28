import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/entities/conversation.dart';
import 'chat_avatar.dart';

/// One conversation in the Messages list: avatar (+online dot), name, time,
/// company, last-message preview, unread badge and the 24-hour window chip.
/// Mirrors design lines 5725–5742.
class ConversationRow extends StatelessWidget {
  const ConversationRow({super.key, required this.conversation, required this.onTap});

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    return ClozrCard(
      onTap: onTap,
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 13.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChatAvatar(initials: c.initials, online: c.online),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    ),
                    SizedBox(width: 8.w),
                    Text(c.lastTime,
                        style: AppText.custom(size: 11, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                  ],
                ),
                SizedBox(height: 1.h),
                Text(c.company, style: AppText.caption(color: AppColors.textMuted)),
                SizedBox(height: 4.h),
                Row(
                  children: [
                    Expanded(
                      child: Text(c.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted2)),
                    ),
                    if (c.hasUnread) ...[
                      SizedBox(width: 8.w),
                      _unreadBadge(c.unread),
                    ],
                  ],
                ),
                SizedBox(height: 7.h),
                _windowChip(c.windowOpen, c.windowLeft),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _unreadBadge(int count) {
    return Container(
      constraints: BoxConstraints(minWidth: 19.w),
      height: 19.h,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: 5.w),
      decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(10.r)),
      child: Text('$count',
          style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.white)),
    );
  }

  Widget _windowChip(bool open, String? windowLeft) {
    final color = open ? AppColors.success : AppColors.textLabelAlt;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: open ? AppColors.tintGreen : AppColors.bgChipGrey,
        borderRadius: BorderRadius.circular(7.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(open ? PhosphorIconsRegular.clock : PhosphorIconsRegular.lockSimple, size: 11.sp, color: color),
          SizedBox(width: 5.w),
          Text(open ? (windowLeft ?? '') : 'Window closed',
              style: AppText.custom(size: 11, weight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
