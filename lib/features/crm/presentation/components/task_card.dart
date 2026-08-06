import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../application/providers/crm_catalog_providers.dart';
import '../../domain/entities/crm_task.dart';
import '../../domain/entities/view_schema.dart';
import 'crm_check_box.dart';

/// The Tasks list card: checkbox + clean title + meta / related lines + status
/// pill, then assignee avatar / due / priority below a hairline.
///
/// The layout is **org-configurable**: [schema] says which of those slots the
/// org shows on its mobile card (`/crm/tasks/schema/?view_type=mobile`). An
/// empty schema means "no opinion" and every slot renders, so mock mode and a
/// failed fetch look exactly as they did before this became configurable.
///
/// The title and the checkbox are never gated — the title is the module's
/// protected name field, and a card you cannot tick is not a task card.
class TaskCard extends ConsumerWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.onTap,
    required this.onToggle,
    this.relatedLine,
    this.schema = ViewSchema.empty,
  });

  final CrmTask task;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  /// "Company · #L1001" resolved by the caller (needs the leads list).
  final String? relatedLine;

  /// The org's configured column set for the mobile card.
  final ViewSchema schema;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The org's own lane name and colour, not the folded built-in bucket.
    final meta = crmTaskStatusMeta(task, ref.watch(taskStatusOptionsProvider));
    final done = task.status == 'done';
    final assignee = MockUsers.of(task.assignee);
    final tone = StatusMeta$.priorityTone[task.priority] ?? StatusMeta$.priorityTone['Low']!;

    final showType = schema.shows('task_type');
    final showRelated = schema.shows('related_to') && relatedLine != null;
    final showStatus = schema.shows('status');
    final showAssignee = schema.shows('assigned_to');
    final showDue = schema.shows('due_date');
    final showPriority = schema.shows('priority');
    // The whole lower strip is optional — with none of its three slots visible
    // it would render as a hairline over empty space.
    final showFooter = showAssignee || showDue || showPriority;

    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.all(15.r),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CrmCheckBox(done: done, onTap: onToggle),
              SizedBox(width: 11.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.titleClean,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(
                          size: 15,
                          weight: FontWeight.w700,
                          color: done ? AppColors.textPlaceholder : AppColors.textPrimary,
                          height: 1.35,
                        ).copyWith(decoration: done ? TextDecoration.lineThrough : null)),
                    if (showType) ...[
                      SizedBox(height: 4.h),
                      Text('#${task.id} · ${task.type}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    ],
                    if (showRelated) ...[
                      SizedBox(height: 3.h),
                      Text(relatedLine!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                    ],
                  ],
                ),
              ),
              if (showStatus) ...[
                SizedBox(width: 8.w),
                _statusPill(meta),
              ],
            ],
          ),
          if (showFooter) ...[
            Padding(padding: EdgeInsets.only(top: 11.h), child: const ClozrDivider()),
            Padding(
              padding: EdgeInsets.only(top: 11.h),
              child: Row(
                children: [
                  if (showAssignee) ...[
                    Container(
                      width: 26.w,
                      height: 26.w,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: assignee.color, shape: BoxShape.circle),
                      child: Text(assignee.initials,
                          style: AppText.custom(size: 9.5, weight: FontWeight.w700, color: AppColors.white)),
                    ),
                    SizedBox(width: 9.w),
                  ],
                  if (showDue) ...[
                    Text(task.due,
                        style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textLabelAlt)),
                    if (task.dueNote.isNotEmpty) ...[
                      SizedBox(width: 8.w),
                      Text(task.dueNote,
                          style: AppText.custom(
                              size: 11.5,
                              weight: FontWeight.w600,
                              color: task.isOverdue ? AppColors.error : AppColors.warningDeep)),
                    ],
                  ],
                  const Spacer(),
                  if (showPriority) ...[
                    Container(width: 8.w, height: 8.w, decoration: BoxDecoration(color: tone.fg, shape: BoxShape.circle)),
                    SizedBox(width: 6.w),
                    Text('${task.priority} priority',
                        style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.textMuted2)),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusPill(StatusMeta meta) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(color: meta.color.withOpacity(0.09), borderRadius: BorderRadius.circular(8.r)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7.w, height: 7.w, decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle)),
          SizedBox(width: 6.w),
          Text(meta.label, style: AppText.custom(size: 12, weight: FontWeight.w700, color: meta.color)),
        ],
      ),
    );
  }
}
