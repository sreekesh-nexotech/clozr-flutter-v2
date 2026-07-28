import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

/// A circular navy initials avatar with an optional green "online" dot,
/// used by the conversation list rows and the chat header.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    super.key,
    required this.initials,
    required this.online,
    this.size = 46,
    this.fontSize = 14,
  });

  final String initials;
  final bool online;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final dot = (size * 0.24).clamp(10.0, 12.0);
    return SizedBox(
      width: size.w,
      height: size.w,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size.w,
            height: size.w,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
            child: Text(initials,
                style: AppText.custom(size: fontSize, weight: FontWeight.w700, color: AppColors.white)),
          ),
          if (online)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: dot.w,
                height: dot.w,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
