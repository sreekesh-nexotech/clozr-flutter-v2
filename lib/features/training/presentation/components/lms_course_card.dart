import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
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
    this.subtitle,
    this.onView,
    this.onDelete,
  });

  final Course course;
  final int avgPct;
  final List<(String, Color)> avatars;
  final String moreLabel;
  final VoidCallback onTap;

  /// Null hides Edit — platform courses are read-only for tenants (webapp).
  final VoidCallback? onEdit;

  /// Overrides the line under the title (Course builder list wording).
  final String? subtitle;

  /// Course builder list actions (webapp eye / trash). Null hides them —
  /// platform courses offer View only.
  final VoidCallback? onView;
  final VoidCallback? onDelete;

  /// Builds a card from a course + the live learner records, deriving the
  /// enrolled avatars, average completion and "+N more" label.
  static LmsCourseCard from({
    required Course course,
    required List<LearnerRecord> records,
    required VoidCallback onTap,
    required VoidCallback onEdit,
    VoidCallback? onDelete,
    bool builderList = false,
  }) {
    // The course list's own figures win (webapp table: modules_count,
    // "+N enrolled" / "Not assigned", completion_percentage). Records can only
    // ever match the signed-in user's enrolments, so deriving from them read
    // "No learners yet" on courses that had learners.
    if (course.enrolledCount != null || course.completion != null) {
      final n = course.enrolledCount ?? 0;
      // The Course builder list words its columns differently from the
      // dashboard table ("N learners", platform / "No description yet").
      final sub = course.listSubtitle;
      return LmsCourseCard(
        course: course,
        avgPct: (course.completion ?? 0).round(),
        avatars: const [],
        // One wording everywhere (UI/UX audit #50): "1 learner" / "4 learners",
        // never "+4 enrolled" on one screen and "4 learners" on another.
        moreLabel: n == 0 ? 'Not assigned' : '$n learner${n == 1 ? '' : 's'}',
        onTap: onTap,
        onEdit: course.isGlobal ? null : onEdit,
        subtitle:
            builderList ? (sub.isEmpty ? 'No description yet' : sub) : null,
        onView: builderList ? onTap : null,
        onDelete: builderList && !course.isGlobal ? onDelete : null,
      );
    }
    final entries = <(String, CourseProgress)>[
      for (final r in records)
        if (r.entryFor(course.id) != null) (r.rid, r.entryFor(course.id)!),
    ];
    final avg = entries.isEmpty
        ? 0
        : (entries.map((e) => LmsLogic.pct(e.$2)).reduce((a, b) => a + b) /
                entries.length)
            .round();
    final avatars = <(String, Color)>[
      for (final e in entries.take(2))
        (LmsPeople.of(e.$1).initials, LmsPeople.of(e.$1).color),
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
    final mods = course.moduleTotal;
    final modsLabel = '$mods ${mods == 1 ? 'module' : 'modules'}';
    // Under the title: the assigned roles (webapp), else the subtitle.
    final subtitle = this.subtitle ??
        (course.roleNames.isNotEmpty
            ? course.roleNames.join(', ')
            : course.sub);
    // Webapp `courseBarColor` for server completion; the seed keeps its accent.
    final barColor = course.completion == null
        ? course.accent
        : avgPct >= 75
            ? AppColors.success
            : avgPct >= 50
                ? AppColors.warning
                : AppColors.teal;

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
                              style: AppText.custom(
                                  size: 14.5,
                                  weight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                        ),
                        if (course.isGlobal) ...[
                          SizedBox(width: 6.w),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 7.w, vertical: 2.h),
                            decoration: BoxDecoration(
                                color: AppColors.tintNavy,
                                borderRadius: BorderRadius.circular(6.r)),
                            child: Text('Platform',
                                style: AppText.custom(
                                    size: 10.5,
                                    weight: FontWeight.w700,
                                    color: AppColors.navy)),
                          ),
                        ],
                        SizedBox(width: 8.w),
                        StatusPill.meta(meta),
                      ],
                    ),
                    SizedBox(height: 2.h),
                    Row(
                      children: [
                        Expanded(
                          child: Text(subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.custom(
                                  size: 12,
                                  weight: FontWeight.w500,
                                  color: AppColors.textPlaceholder)),
                        ),
                        SizedBox(width: 8.w),
                        Text(modsLabel,
                            style: AppText.custom(
                                size: 11.5,
                                weight: FontWeight.w600,
                                color: AppColors.textPlaceholder)),
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
              Expanded(
                  child: LmsProgressBar(value: avgPct / 100, color: barColor)),
              SizedBox(width: 9.w),
              Text('$avgPct%',
                  style: AppText.custom(
                      size: 12,
                      weight: FontWeight.w700,
                      color: AppColors.textSecondary)),
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
                        style: AppText.custom(
                            size: 12,
                            weight: FontWeight.w600,
                            color: AppColors.textMuted)),
                ],
              ),
              Row(
                children: [
                  if (onView != null) _action('View', onView!),
                  if (onEdit != null) ...[
                    if (onView != null) SizedBox(width: 8.w),
                    _action('Edit', onEdit!),
                  ],
                  if (onDelete != null) ...[
                    SizedBox(width: 8.w),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onDelete,
                      child: Container(
                        width: 34.h,
                        height: 32.h,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(9.r),
                          border: Border.all(color: const Color(0xFFE6E7EA)),
                        ),
                        child: Semantics(
                          label: 'Delete course',
                          button: true,
                          child: Icon(PhosphorIconsRegular.trash,
                              size: 16.sp, color: AppColors.error),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(String label, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 32.h,
          padding: EdgeInsets.symmetric(horizontal: 14.w),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(9.r),
            border: Border.all(color: const Color(0xFFE6E7EA)),
          ),
          child: Text(label,
              style: AppText.custom(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: AppColors.textSecondary)),
        ),
      );
}
