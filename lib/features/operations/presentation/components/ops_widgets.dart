import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../data/mock/status_meta.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Format a date the prototype way, e.g. "02 May 2026".
String opsFmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';

/// Parse a display date like "02 May 2026" back into a [DateTime].
DateTime? opsParseDisplayDate(String s) {
  final parts = s.trim().split(RegExp(r'\s+'));
  if (parts.length != 3) return null;
  final day = int.tryParse(parts[0]);
  final month = _months.indexOf(parts[1]) + 1;
  final year = int.tryParse(parts[2]);
  if (day == null || month == 0 || year == null) return null;
  return DateTime(year, month, day);
}

/// Format a time the prototype way, e.g. "9:00 AM".
String opsFmtTime(TimeOfDay t) {
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '$h:${t.minute.toString().padLeft(2, '0')} $ap';
}

/// A status option for the picker sheet (key, {label,color}).
typedef StatusOption = ({String key, StatusMeta meta});

/// Presents the Clozr status picker sheet (Project status / Task status). Rows
/// show a colour dot, the label and a check on the current status. Returns the
/// chosen key (or null if dismissed).
Future<String?> showOpsStatusPicker({
  required BuildContext context,
  required String title,
  required Map<String, StatusMeta> statuses,
  required String currentKey,
}) {
  return showClozrSheet<String>(
    context: context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(title: title),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 26.h),
            child: Column(
              children: [
                for (final entry in statuses.entries)
                  _StatusRow(
                    label: entry.value.label,
                    color: entry.value.color,
                    selected: entry.key == currentKey,
                    onTap: () => Navigator.of(ctx).pop(entry.key),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// A plain single-select option sheet (project / group / type / department…).
/// Returns the chosen value's key, or null if dismissed.
Future<String?> showOpsOptionPicker({
  required BuildContext context,
  required String title,
  required List<({String value, String label})> options,
  required String currentValue,
}) {
  return showClozrSheet<String>(
    context: context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(title: title),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 26.h),
            child: Column(
              children: [
                for (final o in options)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(ctx).pop(o.value),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 13.h),
                      decoration: BoxDecoration(
                        color: o.value == currentValue ? const Color(0xFFF6F8FB) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(o.label, style: AppText.custom(size: 15, weight: FontWeight.w600, color: AppColors.textBody))),
                          Icon(PhosphorIconsBold.check, size: 18.sp, color: o.value == currentValue ? AppColors.success : Colors.transparent),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// A read-only field that looks like a picker/select trigger (label + caret).
class OpsPickerField extends StatelessWidget {
  const OpsPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder = 'Select…',
    this.required = false,
    this.caret = PhosphorIconsBold.caretDown,
  });
  final String label;
  final String value;
  final VoidCallback onTap;
  final String placeholder;
  final bool required;
  final IconData caret;

  @override
  Widget build(BuildContext context) {
    final filled = value.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
            if (required) Text(' *', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.error)),
          ],
        ),
        SizedBox(height: 7.h),
        GestureDetector(
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
                  child: Text(filled ? value : placeholder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 14, weight: FontWeight.w600, color: filled ? AppColors.textBody : AppColors.textPlaceholder)),
                ),
                Icon(caret, size: 13.sp, color: AppColors.textPlaceholder),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.color, required this.selected, required this.onTap});
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 13.h),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF6F8FB) : Colors.transparent,
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: [
            Container(width: 11.w, height: 11.w, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            SizedBox(width: 12.w),
            Expanded(child: Text(label, style: AppText.custom(size: 15, weight: FontWeight.w600, color: AppColors.textBody))),
            Icon(PhosphorIconsBold.check, size: 18.sp, color: selected ? AppColors.success : Colors.transparent),
          ],
        ),
      ),
    );
  }
}

/// The Operations list saved-view chip ("My Projects" / "My Tasks"). Navy
/// filled when active, white with a hairline border when off.
class OpsSavedChip extends StatelessWidget {
  const OpsSavedChip({super.key, required this.label, required this.active, required this.onTap, this.icon = PhosphorIconsRegular.userCircle});
  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34.h,
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        decoration: BoxDecoration(
          color: active ? AppColors.navy : AppColors.white,
          borderRadius: BorderRadius.circular(10.r),
          border: active ? null : Border.all(color: const Color(0xFFE6E7EA)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13.sp, color: active ? AppColors.white : AppColors.textMuted2),
            SizedBox(width: 6.w),
            Text(label,
                style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: active ? AppColors.white : AppColors.textLabelAlt)),
          ],
        ),
      ),
    );
  }
}

/// A single-choice form chip (status / priority / type). When [tone] is set the
/// selected state uses that colour (tinted bg, coloured ring, leading dot) — the
/// edit-form style; otherwise it uses the blue create-form style.
class OpsFormChip extends StatelessWidget {
  const OpsFormChip({super.key, required this.label, required this.selected, required this.onTap, this.tone});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final Color ring;
    final Color bg;
    final Color fg;
    if (tone != null) {
      ring = selected ? tone! : AppColors.borderCardSoft;
      bg = selected ? tone!.withOpacity(0.08) : AppColors.white;
      fg = selected ? tone! : AppColors.textLabelAlt;
    } else {
      ring = selected ? const Color(0xFFA6D1FF) : AppColors.borderCardSoft;
      bg = selected ? AppColors.blueSubtle : AppColors.white;
      fg = selected ? AppColors.navy : AppColors.textLabelAlt;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 9.h),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: ring, width: selected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tone != null) ...[
              Container(width: 9.w, height: 9.w, decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
              SizedBox(width: 7.w),
            ],
            Text(label, style: AppText.custom(size: 13, weight: FontWeight.w600, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// A togglable assignee chip: avatar + first name. Navy-filled when selected in
/// create forms; a tinted outline in edit forms (controlled by [filled]).
class OpsAssigneeChip extends StatelessWidget {
  const OpsAssigneeChip({
    super.key,
    required this.initials,
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
    this.filled = true,
  });
  final String initials;
  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final bool navyFill = filled && selected;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34.h,
        padding: EdgeInsets.only(left: 6.w, right: 12.w),
        decoration: BoxDecoration(
          color: navyFill ? AppColors.navy : (selected ? AppColors.tintNavy : AppColors.white),
          borderRadius: BorderRadius.circular(filled ? 17.r : 999.r),
          border: selected && !navyFill
              ? Border.all(color: AppColors.navy, width: 1.5)
              : (navyFill ? null : Border.all(color: const Color(0xFFE6E7EA))),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24.w,
              height: 24.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: navyFill ? Colors.white24 : color,
                shape: BoxShape.circle,
              ),
              child: Text(initials, style: AppText.custom(size: 9, weight: FontWeight.w700, color: AppColors.white)),
            ),
            SizedBox(width: 7.w),
            Text(name,
                style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: navyFill ? AppColors.white : (selected ? AppColors.navy : AppColors.textLabelAlt))),
          ],
        ),
      ),
    );
  }
}
