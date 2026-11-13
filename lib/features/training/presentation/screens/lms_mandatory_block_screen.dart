import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/widgets/app_card.dart';
import '../../application/providers/mandatory_block_provider.dart';
import '../components/lms_footer.dart';

/// Webapp `BlockingTrainingScreen`: replaces every non-Training screen while a
/// mandatory course is unfinished. Lists each incomplete course with its %,
/// sends the learner to My Trainings, and offers an optimistic recheck.
class LmsMandatoryBlockScreen extends ConsumerWidget {
  const LmsMandatoryBlockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(mandatoryBlockProvider).courses;
    return Container(
      color: AppColors.bgScreen,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(18.w, 24.h, 18.w, 96.h),
            child: ClozrCard(
              radius: 18,
              padding: EdgeInsets.all(22.r),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56.r,
                    height: 56.r,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: AppColors.blueSubtle,
                        borderRadius: BorderRadius.circular(16.r)),
                    child: Icon(PhosphorIconsFill.graduationCap,
                        size: 26.sp, color: AppColors.navy),
                  ),
                  SizedBox(height: 16.h),
                  Text('Complete your required training',
                      style: AppText.custom(
                          size: 19,
                          weight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  SizedBox(height: 6.h),
                  Text(
                    'You have required training to finish before you can use the rest of Clozr. '
                    'Complete the course${courses.length == 1 ? '' : 's'} below to continue.',
                    style: AppText.custom(
                        size: 13.5,
                        weight: FontWeight.w500,
                        color: AppColors.textMuted,
                        height: 1.5),
                  ),
                  if (courses.isNotEmpty) SizedBox(height: 16.h),
                  for (final c in courses)
                    Container(
                      margin: EdgeInsets.only(bottom: 8.h),
                      padding: EdgeInsets.symmetric(
                          horizontal: 12.w, vertical: 11.h),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.borderCardSoft),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 34.r,
                            height: 34.r,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: AppColors.bgLight,
                                borderRadius: BorderRadius.circular(8.r)),
                            child: Icon(PhosphorIconsRegular.bookOpen,
                                size: 16.sp, color: AppColors.navy),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Text(c.title,
                                style: AppText.custom(
                                    size: 14,
                                    weight: FontWeight.w700,
                                    color: AppColors.textPrimary)),
                          ),
                          SizedBox(width: 8.w),
                          Text('${c.completion.round()}%',
                              style: AppText.custom(
                                  size: 12,
                                  weight: FontWeight.w800,
                                  color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  SizedBox(height: 14.h),
                  LmsCtaButton(
                    label: 'Go to my training',
                    icon: PhosphorIconsFill.play,
                    onTap: () => context.go(Routes.lmsMy),
                  ),
                  SizedBox(height: 10.h),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // Optimistic recheck: lift the block and reload every
                    // screen's data. The block comes back on the next
                    // mandatory-course 403 once the cooldown has passed.
                    onTap: () {
                      ref.read(mandatoryBlockProvider.notifier).clearBlock();
                      ref.invalidate(apiServiceProvider);
                    },
                    child: Container(
                      height: 48.h,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        border: Border.all(color: AppColors.borderInput),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Text("I've finished — recheck",
                          style: AppText.custom(
                              size: 14.5,
                              weight: FontWeight.w700,
                              color: AppColors.textSecondary)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
