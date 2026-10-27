import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../data/mock/mock_users.dart';
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
class ProjectCard extends ConsumerWidget {
  const ProjectCard({super.key, required this.project, required this.onTap});

  final Project project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = project;
    final statuses = ref.watch(projectStatusOptionsProvider);
    // The org's own status name and live colour.
    final meta = projectStatusMeta(key: p.status, statusName: p.statusName, statuses: statuses);
    final priColor = StatusMeta$.projectPriority[p.pri] ?? AppColors.textMuted;
    // Webapp: a status with `is_closed` shows a green "Closed" badge instead of
    // a % bar, and a closed project is never shown as overdue.
    final catalogClosed = statuses
        .where((s) => s.name.trim().toLowerCase() == p.statusName.trim().toLowerCase())
        .map((s) => s.isClosed)
        .firstOrNull;
    final closed = catalogClosed ?? (p.status == 'completed' || p.status == 'cancelled');
    final overdue = !closed && isProjectOverdue(p);
    final ended = closed;
    // Manager first, then the assignees (webapp shows the first + "+N").
    final people = <String>[
      if (p.manager.isNotEmpty) p.manager,
      for (final a in p.assignees) if (a != p.manager) a,
    ];
    final shown = people.take(2).toList();
    final more = people.length - shown.length;

    final card = ClozrCard(
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
                    if (p.internal || p.isArchived) ...[
                      SizedBox(height: 4.h),
                      Wrap(spacing: 6.w, children: [
                        if (p.internal) _tag('INTERNAL'),
                        // Webapp: "Archived" tag on an archived row.
                        if (p.isArchived) _tag('ARCHIVED'),
                      ]),
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
          if (closed)
            Row(children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 4.h),
                decoration: BoxDecoration(color: AppColors.tintGreen, borderRadius: BorderRadius.circular(8.r)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(PhosphorIconsFill.checkCircle, size: 13.sp, color: AppColors.success),
                  SizedBox(width: 5.w),
                  Text('Closed', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.success)),
                ]),
              ),
            ])
          else
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
                // No end date reads "—" (webapp), never a bare "Ends ".
                Text(p.end.trim().isEmpty ? 'Ends —' : '${ended ? 'Ended' : 'Ends'} ${p.end}',
                    style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
                const Spacer(),
                if (overdue) ...[
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                    decoration: BoxDecoration(color: AppColors.tintRed, borderRadius: BorderRadius.circular(7.r)),
                    child: Text('Overdue',
                        style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.error)),
                  ),
                  SizedBox(width: 8.w),
                ],
                // Project manager + assignees, as the webapp row shows them.
                if (shown.isNotEmpty) ...[
                  AvatarStack(
                    size: 24,
                    overlap: 7,
                    items: [for (final id in shown) (MockUsers.of(id).initials, AppColors.navy)],
                  ),
                  if (more > 0) ...[
                    SizedBox(width: 4.w),
                    Text('+$more',
                        style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textMuted2)),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
    // Archived rows are dimmed when listed among active ones (webapp).
    return p.isArchived && !ref.watch(archivedProjectsProvider)
        ? Opacity(opacity: 0.6, child: card)
        : card;
  }

  Widget _tag(String text) => Container(
        padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
        decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(6.r)),
        child: Text(text,
            style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textLabelAlt, letterSpacing: 0.4)),
      );
}
