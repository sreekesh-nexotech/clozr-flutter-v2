import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../domain/entities/lead.dart';
import '../../infrastructure/data_sources/remote/crm_tasks_remote_ds.dart';

/// Shared building blocks for the CRM add sheets (Add customer / follow-up /
/// task). Keeps the three focused-but-faithful forms consistent with the
/// prototype's sheet chrome.

// ── date & time pickers ──
//
// Due date / due time are chosen, never typed: a free-text box invites formats
// the API rejects (which then get silently dropped on write, since both
// `isoDateOrNull` and `apiTimeOrNull` answer null for anything unparseable).

/// Opens the platform date picker seeded from [current], which may be ISO
/// ("2026-06-24"), the display form ("24 Jun 2026"), or empty. Null if
/// dismissed.
Future<DateTime?> pickSheetDate(BuildContext context, String current) {
  final iso = CrmTasksRemoteDataSource.isoDateOrNull(current);
  final initial = iso == null ? DateTime.now() : DateTime.parse(iso);
  return showDatePicker(
    context: context,
    initialDate: initial,
    // Both directions: a task can be backdated (logging one already done) as
    // readily as it is scheduled ahead.
    firstDate: DateTime(initial.year - 2),
    lastDate: DateTime(initial.year + 5),
  );
}

/// Opens the platform time picker seeded from [current] ("10:00", "10:00:00",
/// or empty). Null if dismissed.
Future<TimeOfDay?> pickSheetTime(BuildContext context, String current) {
  final api = CrmTasksRemoteDataSource.apiTimeOrNull(current);
  final parts = api?.split(':');
  return showTimePicker(
    context: context,
    initialTime: parts == null
        ? TimeOfDay.now()
        : TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
  );
}

/// "24 Jun 2026" — the form the sheets show and the entities carry.
String sheetDateLabel(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')} ${_monthNames[d.month - 1]} ${d.year}';

/// "2026-06-24" — the form the API stores.
String sheetIsoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A stored time ("10:00:00", "10:00") as the sheets show it — "10:00". Null
/// when empty or unparseable, which is what an unfilled field looks like.
String? sheetTimeText(String raw) => CrmTasksRemoteDataSource.apiTimeOrNull(raw);

/// "10:00" — shown and stored alike.
String sheetTimeLabel(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Two-letter initials from a name (first letters of the first two words).
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final w = words.first;
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
}

/// A short, session-unique id with the given [prefix] (e.g. `C`, `TL-`, `F`).
String genId(String prefix) =>
    '$prefix${DateTime.now().millisecondsSinceEpoch.remainder(100000)}';

/// The read-only "this is being raised against X" row shown at the top of a
/// sheet opened from a lead's detail screen.
///
/// Deliberately not editable: the link comes from the screen you opened the
/// sheet on, and letting it be changed here would invite creating a record
/// against a lead you are not looking at.
class LinkedLeadField extends StatelessWidget {
  const LinkedLeadField({super.key, required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    final subtitle = lead.company ?? lead.project;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetFieldLabel('Linked lead'),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 11.h),
          decoration: BoxDecoration(
            color: AppColors.bgChipGrey,
            borderRadius: BorderRadius.circular(11.r),
            border: Border.all(color: AppColors.borderCardSoft),
          ),
          child: Row(
            children: [
              Container(
                width: 32.w,
                height: 32.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(9.r)),
                child: Text(lead.initials,
                    style: AppText.custom(
                        size: 11.5, weight: FontWeight.w700, color: AppColors.navy)),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lead.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(
                            size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    if (subtitle.isNotEmpty) ...[
                      SizedBox(height: 2.h),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(
                              size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A field label (matches the add-sheet label style in the prototype).
class SheetFieldLabel extends StatelessWidget {
  const SheetFieldLabel(this.label, {super.key, this.required = false});
  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 7.h),
      child: Row(
        children: [
          Text(label,
              style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
          if (required)
            Text(' *',
                style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.error)),
        ],
      ),
    );
  }
}

/// A selectable pill used for status / type / priority choices in the sheets.
class SelectChip extends StatelessWidget {
  const SelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.dot,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: selected ? AppColors.blueSubtle : AppColors.white,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: selected ? const Color(0xFFA6D1FF) : const Color(0xFFE6E7EA),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(width: 9.w, height: 9.w, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              SizedBox(width: 7.w),
            ] else if (icon != null) ...[
              Icon(icon, size: 14.sp, color: selected ? AppColors.navy : AppColors.textLabelAlt),
              SizedBox(width: 6.w),
            ],
            Text(label,
                style: AppText.custom(
                  size: 13,
                  weight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.navy : AppColors.textLabelAlt,
                )),
          ],
        ),
      ),
    );
  }
}

/// The sticky primary action button in the sheet footer.
///
/// Set [busy] while a save is in flight: the bar dims, reports progress and
/// stops accepting taps. Every one of these sheets awaits a `POST` before it
/// pops, so without it a second tap during that window creates the record
/// twice — which is exactly what a lead's audit trail showed.
class SheetSubmitBar extends StatelessWidget {
  const SheetSubmitBar({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.busy = false,
    this.busyLabel = 'Saving…',
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool busy;
  final String busyLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(18.w, 12.h, 18.w, 24.h),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderCardSoft))),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Null rather than a no-op closure, so the tap is not merely swallowed
        // here — it falls through to nothing and cannot re-enter the save.
        onTap: busy ? null : onTap,
        child: Opacity(
          opacity: busy ? 0.6 : 1,
          child: Container(
            height: 48.h,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(12.r)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  SizedBox(
                    width: 15.sp,
                    height: 15.sp,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(AppColors.white),
                    ),
                  )
                else
                  Icon(icon, size: 15.sp, color: AppColors.white),
                SizedBox(width: 8.w),
                Text(busy ? busyLabel : label,
                    style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
