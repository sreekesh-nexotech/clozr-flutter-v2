import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../application/providers/dashboard_providers.dart';
import '../../domain/entities/dash_colors.dart';
import '../../domain/entities/dashboard_models.dart';

/// The dashboard team picker sheet ("Filter by team"). Selecting a team updates
/// [dashTeamProvider] (which re-labels the team chip) and closes.
Future<void> showDashTeamPicker(BuildContext context, WidgetRef ref, List<DashTeamOption> options) {
  final selected = ref.read(dashTeamProvider);
  return showClozrSheet<void>(
    context: context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(18.w, 6.h, 14.w, 12.h),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Filter by team',
                  style: AppText.custom(size: 17, weight: FontWeight.w700, color: AppColors.textPrimary)),
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: Container(
                  width: 32.w,
                  height: 32.w,
                  decoration: BoxDecoration(color: DashColors.chipGrey, borderRadius: BorderRadius.circular(9.r)),
                  child: Icon(PhosphorIconsBold.x, size: 15.sp, color: AppColors.textLabelAlt),
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 26.h),
            child: Column(
              children: [
                for (final o in options)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      // The member list is scoped to the team, so a member
                      // picked under the old one is no longer a valid filter —
                      // and `user_id` wins over `team_id`, so leaving it set
                      // would make the new team selection do nothing at all.
                      ref.read(dashMemberProvider.notifier).state = '';
                      ref.read(dashTeamProvider.notifier).state = o.id;
                      Navigator.of(ctx).pop();
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 14.h),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppColors.bgLight, width: 1)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(o.name,
                                    style: AppText.custom(size: 15, weight: FontWeight.w600, color: AppColors.textBody)),
                                SizedBox(height: 1.h),
                                Text(o.sub,
                                    style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                              ],
                            ),
                          ),
                          Icon(PhosphorIconsBold.check,
                              size: 17.sp, color: selected == o.id ? DashColors.green : Colors.transparent),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
