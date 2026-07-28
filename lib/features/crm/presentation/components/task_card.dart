import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../domain/entities/crm_task.dart';
import 'crm_check_box.dart';

/// The Tasks list card: checkbox + clean title + meta / related lines + status
/// pill, then assignee avatar / due / priority below a hairline.
class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.onTap,
    required this.onToggle,
    this.relatedLine,
  });

  final CrmTask task;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  /// "Company · #L1001" resolved by the caller (needs the leads list).
  final String? relatedLine;

  @override
  Widget build(BuildContext context) {
    final meta = StatusMeta$.task[task.status] ?? StatusMeta$.task['todo']!;
    final done = task.status == 'done';
    final assignee = MockUsers.of(task.assignee);
    final tone = StatusMeta$.priorityTone[task.priority] ?? StatusMeta$.priorityTone['Low']!;

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
                    SizedBox(height: 4.h),
                    Text('#${task.id} · ${task.type}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    if (relatedLine != null) ...[
                      SizedBox(height: 3.h),
                      Text(relatedLine!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              _statusPill(meta),
            ],
          ),
          Padding(padding: EdgeInsets.only(top: 11.h), child: const ClozrDivider()),
          Padding(
            padding: EdgeInsets.only(top: 11.h),
            child: Row(
              children: [
                Container(
                  width: 26.w,
                  height: 26.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: assignee.color, shape: BoxShape.circle),
                  child: Text(assignee.initials,
                      style: AppText.custom(size: 9.5, weight: FontWeight.w700, color: AppColors.white)),
                ),
                SizedBox(width: 9.w),
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
                const Spacer(),
                Container(width: 8.w, height: 8.w, decoration: BoxDecoration(color: tone.fg, shape: BoxShape.circle)),
                SizedBox(width: 6.w),
                Text('${task.priority} priority',
                    style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.textMuted2)),
              ],
            ),
          ),
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
