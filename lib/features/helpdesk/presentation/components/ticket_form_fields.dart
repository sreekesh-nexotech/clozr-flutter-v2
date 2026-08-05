import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../data/api/roster.dart';

/// A field label (`12/600` muted) with an optional required asterisk. Shared by
/// the create and edit ticket forms.
class TicketFieldLabel extends StatelessWidget {
  const TicketFieldLabel(this.text, {super.key, this.required = false});
  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(text, style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
        if (required) Text(' *', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.error)),
      ],
    );
  }
}

/// A tap-to-open picker row (46px, inset border, trailing icon) — the design's
/// customer / product / project selectors.
class TicketPickerRow extends StatelessWidget {
  const TicketPickerRow({
    super.key,
    required this.label,
    required this.placeholder,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final bool placeholder;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 46.h,
        padding: EdgeInsets.symmetric(horizontal: 14.w),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(11.r),
          border: Border.all(color: AppColors.borderInput),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.custom(
                      size: 13.5,
                      weight: FontWeight.w600,
                      color: placeholder ? AppColors.textPlaceholder : AppColors.textBody)),
            ),
            Icon(icon, size: 15.sp, color: AppColors.textPlaceholder),
          ],
        ),
      ),
    );
  }
}

/// A wrapping row of single-select option chips.
class TicketChipWrap extends StatelessWidget {
  const TicketChipWrap({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.dotColor,
  });

  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelect;
  final Color Function(String)? dotColor;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: [
        for (final o in options)
          GestureDetector(
            onTap: () => onSelect(o),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 9.h),
              decoration: BoxDecoration(
                color: selected == o
                    ? (dotColor != null ? dotColor!(o).withOpacity(0.08) : AppColors.blueSubtle)
                    : AppColors.white,
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(
                  color: selected == o
                      ? (dotColor != null ? dotColor!(o) : const Color(0xFFA6D1FF))
                      : AppColors.borderCardSoft,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dotColor != null) ...[
                    Container(width: 9.w, height: 9.w, decoration: BoxDecoration(color: dotColor!(o), shape: BoxShape.circle)),
                    SizedBox(width: 7.w),
                  ],
                  Text(o,
                      style: AppText.custom(
                          size: 13,
                          weight: FontWeight.w600,
                          color: selected == o
                              ? (dotColor != null ? dotColor!(o) : AppColors.navy)
                              : AppColors.textLabelAlt)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A wrapping row of multi-select assignee chips (avatar + first name). Reads
/// the workspace roster so API mode offers real members, mock mode the reps.
class TicketAssigneeWrap extends ConsumerWidget {
  const TicketAssigneeWrap({super.key, required this.selected, required this.onToggle});
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: [
        for (final r in ref.watch(rosterProvider))
          GestureDetector(
            onTap: () => onToggle(r.id),
            child: Container(
              padding: EdgeInsets.fromLTRB(5.w, 5.h, 12.w, 5.h),
              decoration: BoxDecoration(
                color: selected.contains(r.id) ? AppColors.blueSubtle : AppColors.white,
                borderRadius: BorderRadius.circular(999.r),
                border: Border.all(
                  color: selected.contains(r.id) ? const Color(0xFFA6D1FF) : AppColors.borderCardSoft,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 24.w,
                    height: 24.w,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: r.color, shape: BoxShape.circle),
                    child: Text(r.initials, style: AppText.custom(size: 9.5, weight: FontWeight.w700, color: AppColors.white)),
                  ),
                  SizedBox(width: 7.w),
                  Text(r.firstName,
                      style: AppText.custom(
                          size: 12.5,
                          weight: FontWeight.w600,
                          color: selected.contains(r.id) ? AppColors.navy : AppColors.textLabelAlt)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
