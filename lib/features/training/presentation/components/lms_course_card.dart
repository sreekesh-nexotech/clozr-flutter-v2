import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/learner_record.dart';
import '../../domain/lms_logic.dart';
import '../../infrastructure/data_sources/local/lms_people.dart';
import '../lms_style.dart';
import 'lms_progress_bar.dart';
import 'lms_thumb.dart';

/// The course list card shared by Training Overview and All Courses: thumbnail +
/// title/status, subtitle + module count, average-progress bar, enrolled avatar
/// stack and an Edit button.
class LmsCourseCard extends StatelessWidget {
  const LmsCourseCard({
    super.key,
    required this.course,
    required this.avgPct,
    required this.avatars,
    required this.moreLabel,
    required this.onTap,
    required this.onEdit,
  });

  final Course course;
  final int avgPct;
  final List<(String, Color)> avatars;
  final String moreLabel;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  /// Builds a card from a course + the live learner records, deriving the
  /// enrolled avatars, average completion and "+N more" label.
  static LmsCourseCard from({
    required Course course,
    required List<LearnerRecord> records,
    required VoidCallback onTap,
    required VoidCallback onEdit,
  }) {
    final entries = <(String, CourseProgress)>[
      for (final r in records)
        if (r.entryFor(course.id) != null) (r.rid, r.entryFor(course.id)!),
    ];
    final avg = entries.isEmpty
        ? 0
        : (entries.map((e) => LmsLogic.pct(e.$2)).reduce((a, b) => a + b) / entries.length).round();
    final avatars = <(String, Color)>[
      for (final e in entries.take(2)) (LmsPeople.of(e.$1).initials, LmsPeople.of(e.$1).color),
    ];
    final more = entries.length > 2
        ? '+${entries.length - 2} more'
        : (entries.isEmpty ? 'No learners yet' : '');
    return LmsCourseCard(
      course: course,
      avgPct: avg,
      avatars: avatars,
      moreLabel: more,
      onTap: onTap,
      onEdit: onEdit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final meta = LmsStyle.publishMeta(course.isPublished);
    final modsLabel =
        '${course.modules.length} ${course.modules.length == 1 ? 'module' : 'modules'}';

    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.all(14.r),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LmsThumb(course: course, width: 54, height: 54, iconSize: 24),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(course.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                        ),
                        SizedBox(width: 8.w),
                        StatusPill.meta(meta),
                      ],
                    ),
                    SizedBox(height: 2.h),
                    Row(
                      children: [
                        Expanded(
                          child: Text(course.sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                        ),
                        SizedBox(width: 8.w),
                        Text(modsLabel,
                            style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(child: LmsProgressBar(value: avgPct / 100, color: course.accent)),
              SizedBox(width: 9.w),
              Text('$avgPct%',
                  style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textSecondary)),
            ],
          ),
          SizedBox(height: 11.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (avatars.isNotEmpty) ...[
                    AvatarStack(size: 26, items: avatars),
                    SizedBox(width: 7.w),
                  ],
                  if (moreLabel.isNotEmpty)
                    Text(moreLabel,
                        style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textMuted)),
                ],
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onEdit,
                child: Container(
                  height: 32.h,
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(9.r),
                    border: Border.all(color: const Color(0xFFE6E7EA)),
                  ),
                  child: Text('Edit',
                      style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.textSecondary)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
