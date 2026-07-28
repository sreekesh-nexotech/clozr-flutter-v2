import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';

/// Temporary screen shown for routes whose real UI is built in a later module
/// pass. Never shipped — every stub is replaced by its module implementation.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgScreen,
      padding: EdgeInsets.only(top: 56.h),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 66.r,
              height: 66.r,
              decoration: BoxDecoration(
                color: AppColors.borderCardSoft,
                borderRadius: BorderRadius.circular(19.r),
              ),
              child: Icon(PhosphorIcons.wrench(), size: 30.sp, color: AppColors.textPlaceholder),
            ),
            SizedBox(height: 16.h),
            Text(title, style: AppText.sectionTitle()),
            SizedBox(height: 6.h),
            Text('Screen coming in this build', style: AppText.caption()),
          ],
        ),
      ),
    );
  }
}
