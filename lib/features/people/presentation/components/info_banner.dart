import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

/// The blue info banner used atop the Teams and Roles lists: info glyph beside a
/// rich explanatory line (support **bold** emphasis via [spans]).
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.spans});

  final List<InlineSpan> spans;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 11.h),
      decoration: BoxDecoration(color: AppColors.blueSubtle, borderRadius: BorderRadius.circular(12.r)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 1.h),
            child: Icon(PhosphorIconsRegular.info, size: 16.sp, color: AppColors.blueBright),
          ),
          SizedBox(width: 9.w),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: AppText.custom(size: 12, weight: FontWeight.w500, color: const Color(0xFF35507C), height: 1.5),
                children: spans,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
