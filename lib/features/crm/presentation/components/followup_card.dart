import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../domain/entities/followup.dart';
import '../../application/task_columns.dart';
import '../../domain/entities/view_schema.dart';
import 'crm_check_box.dart';

/// The Follow-ups list card: checkbox + title + meta line + status pill, then
/// owner avatar / due time / priority below a hairline.
///
/// The layout is **org-configurable**: [schema] says which of those slots the
/// org put on its mobile card. An empty schema means "no opinion" and every
/// slot renders, so mock mode and a failed fetch look exactly as before.
class FollowupCard extends StatelessWidget {
  const FollowupCard({
    super.key,
    required this.followup,
    required this.onTap,
    required this.onToggle,
    this.schema = ViewSchema.empty,
    this.status,
  });

  /// The status pill to render — the org's own status name and colour, resolved
  /// by the screen so every card in one list agrees with the tab above it.
  final StatusMeta? status;

  final Followup followup;

  /// The org's configured card columns
  /// (`/crm/tasks/schema/?view_type=mobile&is_followup=true`).
  final ViewSchema schema;

  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    // The org's own status when the screen resolved one; only a follow-up with
    // no status name at all falls back to the built-in bucket.
    final meta = status ??
        StatusMeta$.followup[followup.status] ??
        StatusMeta$.followup['due']!;
    final done = followup.status == 'done';
    final owner = MockUsers.of(followup.owner);
    // The headline is the task's own **title**. It used to read `agenda`,
    // which preferred the description — so a follow-up with one showed its
    // description as the heading and its title nowhere at all.
    final title = followup.title.isNotEmpty
        ? followup.title
        : '${followup.kind} — ${followup.company}';
    final timeLabel = '${followup.due.replaceAll(' 2026', '')} · ${followup.time}';
    // The sub-line names the type and the record this follow-up hangs off, so
    // it shows only when the org kept either of those columns on its card.
    final subLine = [
      if (schema.shows('task_type') && followup.kind.isNotEmpty) followup.kind,
      if (schema.shows('related_to') && followup.contact.isNotEmpty) followup.contact,
    ].join(' · ');
    // Everything else the org made visible, in its order — the card no longer
    // renders only the slots it was built with.
    final extras = followupExtraColumns(followup, schema);

    return ClozrCard(
      radius: 16,
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
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(
                          size: 14.5,
                          weight: FontWeight.w700,
                          color: done ? AppColors.textPlaceholder : AppColors.textPrimary,
                          height: 1.35,
                        ).copyWith(decoration: done ? TextDecoration.lineThrough : null)),
                    // Its own line now, on the org's say-so — `description` is
                    // a distinct column in the mobile layout, not a substitute
                    // for the title.
                    if (schema.shows('description') && followup.description.isNotEmpty) ...[
                      SizedBox(height: 3.h),
                      Text(followup.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(
                              size: 12.5, weight: FontWeight.w500, color: AppColors.textLabelAlt)),
                    ],
                    if (subLine.isNotEmpty) ...[
                      SizedBox(height: 3.h),
                      Text(subLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    ],
                    if (extras.isNotEmpty) ...[
                      SizedBox(height: 6.h),
                      Wrap(
                        spacing: 6.w,
                        runSpacing: 6.h,
                        children: [for (final e in extras) _chip(e.label, e.value)],
                      ),
                    ],
                  ],
                ),
              ),
              if (schema.shows('status')) ...[
                SizedBox(width: 8.w),
                _statusPill(meta),
              ],
            ],
          ),
          Padding(
            padding: EdgeInsets.only(top: 11.h),
            child: const ClozrDivider(),
          ),
          Padding(
            padding: EdgeInsets.only(top: 11.h),
            child: Row(
              children: [
                if (schema.shows('assigned_to')) ...[
                  Container(
                    width: 26.w,
                    height: 26.w,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: owner.color, shape: BoxShape.circle),
                    child: Text(owner.initials,
                        style: AppText.custom(size: 9.5, weight: FontWeight.w700, color: AppColors.white)),
                  ),
                  SizedBox(width: 9.w),
                ],
                if (schema.shows('due_date'))
                  Text(timeLabel,
                      style: AppText.custom(
                          size: 12,
                          weight: FontWeight.w700,
                          color: followup.status == 'overdue' ? AppColors.error : AppColors.textLabelAlt)),
                const Spacer(),
                // Priority is on the org's seeded mobile card but was never
                // rendered; the type sits here when priority is not configured.
                if (schema.shows('priority') && followup.priority.isNotEmpty)
                  Text(followup.priority,
                      style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.textPlaceholder))
                else if (schema.shows('task_type'))
                  Text(followup.kind,
                      style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(StatusMeta meta) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 3.h),
      decoration: BoxDecoration(color: meta.color.withOpacity(0.09), borderRadius: BorderRadius.circular(8.r)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7.w, height: 7.w, decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle)),
          SizedBox(width: 6.w),
          Text(meta.label, style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: meta.color)),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: AppColors.bgChipGrey,
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: RichText(
        text: TextSpan(children: [
          TextSpan(
            text: '$label ',
            style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textMuted),
          ),
          TextSpan(
            text: value,
            style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.textPrimary),
          ),
        ]),
      ),
    );
  }
}
