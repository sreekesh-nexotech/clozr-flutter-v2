import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../application/providers/ops_tasks_providers.dart';
import '../../domain/entities/ops_task.dart';

/// The Ops Tasks list card: milestone flag + subject, project·group sub-line,
/// status/priority pills, an optional "Waiting on" chip, and a footer with
/// assignee avatars, due date, overdue chip and a subtask counter.
class OpsTaskCard extends ConsumerWidget {
  const OpsTaskCard({
    super.key,
    required this.task,
    required this.projectName,
    required this.unresolvedCount,
    required this.onTap,
    this.onMore,
  });

  final OpsTask task;
  final String projectName;
  final int unresolvedCount;
  final VoidCallback onTap;

  /// The row's ⋯ menu (webapp `RowMenu`: Edit / milestone / Delete). Null hides
  /// the control — a user with neither update nor delete gets no dead button.
  final VoidCallback? onMore;

  Widget _moreButton() => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onMore,
        child: Padding(
          padding: EdgeInsets.only(left: 12.w),
          child: Icon(PhosphorIconsBold.dotsThreeVertical, size: 18.sp, color: AppColors.textMuted),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = task;
    // The org's own status name and colour, not the built-in palette.
    final meta = opsTaskStatusMeta(
      key: t.status,
      statusName: t.statusName,
      statuses: ref.watch(opsTaskStatusOptionsProvider),
    );
    final priColor = StatusMeta$.projectPriority[t.pri] ?? AppColors.textMuted;
    final overdue = isTaskOverdue(t);
    final ids = t.assignees.take(2).toList();
    final more = t.assignees.length - ids.length;
    final due = 'Due ${opsWhenLabel(t.end, t.endTime)}';

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (t.milestone) ...[
                          Icon(PhosphorIconsFill.flag, size: 14.sp, color: AppColors.warningDeep),
                          SizedBox(width: 7.w),
                        ],
                        Expanded(
                          child: Text(t.subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.custom(size: 15.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                        ),
                      ],
                    ),
                    SizedBox(height: 3.h),
                    // Webapp: a task with no project is listed as "Standalone".
                    Text('${projectName.isEmpty ? (ApiConfig.apiEnabled && t.projId.isEmpty ? 'Standalone' : '—') : projectName} · ${t.group}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ],
                ),
              ),
              SizedBox(width: 12.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // A task with no status reads "—", as on the webapp.
                  if (ApiConfig.apiEnabled && t.statusName.trim().isEmpty)
                    StatusPill(label: '—', color: AppColors.textMuted)
                  else
                    StatusPill.meta(meta),
                  SizedBox(height: 5.h),
                  StatusPill(label: t.pri, color: priColor),
                ],
              ),
            ],
          ),
          if (unresolvedCount > 0) ...[
            SizedBox(height: 9.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 4.h),
              decoration: BoxDecoration(color: AppColors.tintAmber, borderRadius: BorderRadius.circular(7.r)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsFill.clock, size: 11.sp, color: const Color(0xFFB45C00)),
                  SizedBox(width: 5.w),
                  Text('Waiting on $unresolvedCount',
                      style: AppText.custom(size: 11, weight: FontWeight.w700, color: const Color(0xFFB45C00))),
                ],
              ),
            ),
          ],
          SizedBox(height: 11.h),
          Container(
            padding: EdgeInsets.only(top: 11.h),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF3F4F5)))),
            // The ⋯ sits at the right edge, after everything else in the footer.
            child: Row(children: [
              Expanded(child: Row(
              children: [
                AvatarStack(
                  size: 24,
                  overlap: 7,
                  items: [for (final id in ids) (MockUsers.of(id).initials, AppColors.navy)],
                ),
                if (more > 0) ...[
                  SizedBox(width: 4.w),
                  Text('+$more',
                      style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textMuted2)),
                ],
                SizedBox(width: 9.w),
                Flexible(
                  child: Text(due,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
                ),
                if (overdue) ...[
                  SizedBox(width: 8.w),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                    decoration: BoxDecoration(color: AppColors.tintRed, borderRadius: BorderRadius.circular(7.r)),
                    child: Text('Overdue',
                        style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.error)),
                  ),
                ],
                if (t.subtasks.isNotEmpty) ...[
                  const Spacer(),
                  Icon(PhosphorIconsRegular.listChecks, size: 12.sp, color: AppColors.textPlaceholder),
                  SizedBox(width: 4.w),
                  Text('${t.doneSubs}/${t.subtasks.length} subtasks',
                      style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                ],
              ],
              )),
              if (onMore != null) _moreButton(),
            ]),
          ),
        ],
      ),
    );
  }
}
