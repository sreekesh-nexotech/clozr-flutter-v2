import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/config/constants.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_header_bar.dart';

/// The white top block of the Dashboard screen: the shared brand header
/// (logo/workspace + messages + bell, from [AppHeaderBar]) over a greeting
/// row ("Good morning, Manoj Varma") and the date. Clears the 56px status bar
/// and carries the prototype's 1px bottom hairline.
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderCardSoft, width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(18.w, 56.h, 18.w, 10.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppHeaderBar(),
          SizedBox(height: 16.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Good morning,',
                        style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                    SizedBox(height: 1.h),
                    Text('Manoj Varma',
                        style: AppText.custom(size: 24, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5)),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(bottom: 3.h),
                child: Text(AppConstants.headerDate,
                    style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
