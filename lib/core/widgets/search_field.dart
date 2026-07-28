import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';

/// The expanding search field used on list screens: 46px tall, blue inset ring,
/// magnifier icon, and a close chip that collapses/clears it.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.onClose,
    this.hint = 'Search…',
    this.onChanged,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final VoidCallback onClose;
  final String hint;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46.h,
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      decoration: BoxDecoration(
        color: AppColors.bgScreen,
        borderRadius: BorderRadius.circular(13.r),
        border: Border.all(color: const Color(0xFFA6D1FF), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsRegular.magnifyingGlass, size: 18.sp, color: AppColors.textPlaceholder),
          SizedBox(width: 10.w),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              onChanged: onChanged,
              style: AppText.body(),
              cursorColor: AppColors.blueBright,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: AppText.body(color: AppColors.textPlaceholder),
              ),
            ),
          ),
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: 26.w,
              height: 26.w,
              decoration: BoxDecoration(
                color: const Color(0xFFECEDEF),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(PhosphorIconsBold.x, size: 12.sp, color: AppColors.textLabelAlt),
            ),
          ),
        ],
      ),
    );
  }
}
