import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../app/config/constants.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

/// Shown while the session is being restored at startup, so a returning user
/// never flashes the login screen before their saved session loads.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgScreen,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppConstants.brandName, style: AppText.logo()),
            SizedBox(height: 20.h),
            SizedBox(
              width: 22.r,
              height: 22.r,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.navy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
