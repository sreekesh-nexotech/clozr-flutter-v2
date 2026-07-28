import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

/// The always-visible LMS search input (46px, grey inset ring over the screen
/// background) used on All Courses and Learners. Distinct from the core
/// expanding [SearchField]; the LMS design shows a persistent field.
class LmsSearchField extends StatelessWidget {
  const LmsSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46.h,
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      decoration: BoxDecoration(
        color: AppColors.bgScreen,
        borderRadius: BorderRadius.circular(13.r),
        border: Border.all(color: const Color(0xFFE6E7EA)),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsRegular.magnifyingGlass, size: 18.sp, color: AppColors.textPlaceholder),
          SizedBox(width: 10.w),
          Expanded(
            child: TextField(
              controller: controller,
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
        ],
      ),
    );
  }
}
