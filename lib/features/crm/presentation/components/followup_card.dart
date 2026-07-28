import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../domain/entities/followup.dart';
import 'crm_check_box.dart';

/// The Follow-ups list card: checkbox + agenda title + meta line + status pill,
/// then owner avatar / due time / kind below a hairline.
class FollowupCard extends StatelessWidget {
  const FollowupCard({super.key, required this.followup, required this.onTap, required this.onToggle});

  final Followup followup;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final meta = StatusMeta$.followup[followup.status] ?? StatusMeta$.followup['due']!;
    final done = followup.status == 'done';
    final owner = MockUsers.of(followup.owner);
    final title = followup.agenda.isNotEmpty ? followup.agenda : '${followup.kind} — ${followup.company}';
    final timeLabel = '${followup.due.replaceAll(' 2026', '')} · ${followup.time}';

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
                    SizedBox(height: 3.h),
                    Text('${followup.kind} · ${followup.company} · ${followup.contact}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              _statusPill(meta),
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
                Container(
                  width: 26.w,
                  height: 26.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: owner.color, shape: BoxShape.circle),
                  child: Text(owner.initials,
                      style: AppText.custom(size: 9.5, weight: FontWeight.w700, color: AppColors.white)),
                ),
                SizedBox(width: 9.w),
                Text(timeLabel,
                    style: AppText.custom(
                        size: 12,
                        weight: FontWeight.w700,
                        color: followup.status == 'overdue' ? AppColors.error : AppColors.textLabelAlt)),
                const Spacer(),
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
}
