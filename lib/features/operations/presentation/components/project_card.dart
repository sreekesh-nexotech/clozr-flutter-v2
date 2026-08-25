import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/status_meta.dart';
import '../../application/providers/projects_providers.dart';
import '../../domain/entities/project.dart';

/// The Projects list card: title + id·type + customer, status/priority pills,
/// a progress bar and a due-date footer with an optional overdue chip.
class ProjectCard extends StatelessWidget {
  const ProjectCard({super.key, required this.project, required this.onTap});

  final Project project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final meta = StatusMeta$.project[p.status] ?? StatusMeta$.project['planning']!;
    final priColor = StatusMeta$.projectPriority[p.pri] ?? AppColors.textMuted;
    final overdue = isProjectOverdue(p);
    final ended = p.status == 'completed' || p.status == 'cancelled';

    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.symmetric(vertical: 15.h, horizontal: 16.w),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 17, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 4.h),
                    // `naming_series` ("PRJ-1010"), never `p.id` — that is the
                    // UUID, which this line was printing at the user.
                    Text([
                      if (p.code.isNotEmpty) p.code,
                      if (p.type.isNotEmpty) p.type,
                    ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(color: AppColors.textMuted2)),
                    if (!p.internal && (p.company ?? '').isNotEmpty) ...[
                      SizedBox(height: 3.h),
                      Text(p.company!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                    ],
                    if (p.internal) ...[
                      SizedBox(height: 4.h),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
                        decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(6.r)),
                        child: Text('INTERNAL',
                            style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textLabelAlt, letterSpacing: 0.4)),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 12.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusPill.meta(meta),
                  SizedBox(height: 5.h),
                  StatusPill(label: p.pri, color: priColor),
                ],
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3.r),
                  child: LinearProgressIndicator(
                    value: p.progress / 100,
                    minHeight: 6.h,
                    backgroundColor: const Color(0xFFEEF1F4),
                    valueColor: AlwaysStoppedAnimation(meta.color),
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Text('${p.progress}%',
                  style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          SizedBox(height: 11.h),
          Container(
            padding: EdgeInsets.only(top: 11.h),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFF3F4F5))),
            ),
            child: Row(
              children: [
                Icon(PhosphorIconsRegular.calendarBlank, size: 14.sp, color: AppColors.textPlaceholder),
                SizedBox(width: 7.w),
                Text('${ended ? 'Ended' : 'Ends'} ${p.end}',
                    style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
                if (overdue) ...[
                  const Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                    decoration: BoxDecoration(color: AppColors.tintRed, borderRadius: BorderRadius.circular(7.r)),
                    child: Text('Overdue',
                        style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.error)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
