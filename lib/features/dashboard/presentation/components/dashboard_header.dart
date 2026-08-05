import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../auth/application/providers/auth_providers.dart';

/// Shown until `/me` resolves, and in mock mode where there is no session —
/// keeps the prototype build reading exactly as it did.
const _seedName = 'Manoj Varma';

/// "Good morning/afternoon/evening," by the device clock.
String _greeting(DateTime now) {
  if (now.hour < 12) return 'Good morning,';
  if (now.hour < 17) return 'Good afternoon,';
  return 'Good evening,';
}

/// The prototype's header date format ("Thu, 9 Jul"), against today's date.
String _headerDate(DateTime now) => DateFormat('EEE, d MMM').format(now);

/// The white top block of the Dashboard screen: the shared brand header
/// (logo/workspace + messages + bell, from [AppHeaderBar]) over a greeting
/// row ("Good morning, <signed-in user>") and today's date. Clears the 56px
/// status bar and carries the prototype's 1px bottom hairline.
class DashboardHeader extends ConsumerWidget {
  const DashboardHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).user;
    final name =
        (user?.fullName.trim().isNotEmpty ?? false) ? user!.fullName : _seedName;
    final now = DateTime.now();

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
                    Text(_greeting(now),
                        style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                    SizedBox(height: 1.h),
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 24, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5)),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(bottom: 3.h),
                child: Text(_headerDate(now),
                    style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
