import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../application/providers/dashboard_providers.dart';
import '../../domain/entities/dash_colors.dart';

const _presets = ['This month', 'Last month', 'This quarter', 'Year to date', 'Last 30 days', 'Last 90 days'];
const _monthsFull = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];
const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// The dashboard period picker sheet: a 2-column preset grid, a "Custom range"
/// expander with From/To + a month calendar, and an Apply button that commits
/// the label to [dashPeriodProvider].
Future<void> showDashPeriodPicker(BuildContext context, WidgetRef ref, String current) {
  return showClozrSheet<void>(
    context: context,
    builder: (ctx) => _PeriodPickerBody(
      current: _presets.contains(current) ? current : 'This month',
      onApply: (label) {
        ref.read(dashPeriodProvider.notifier).state = label;
        Navigator.of(ctx).pop();
      },
      onClose: () => Navigator.of(ctx).pop(),
    ),
  );
}

class _PeriodPickerBody extends StatefulWidget {
  const _PeriodPickerBody({required this.current, required this.onApply, required this.onClose});
  final String current;
  final ValueChanged<String> onApply;
  final VoidCallback onClose;

  @override
  State<_PeriodPickerBody> createState() => _PeriodPickerBodyState();
}

class _PeriodPickerBodyState extends State<_PeriodPickerBody> {
  late String _preset = widget.current;
  bool _custom = false;
  DateTime? _from;
  DateTime? _to;
  int _calY = 2026;
  int _calM = 5; // June

  void _pickDay(DateTime d) {
    setState(() {
      if (_from == null || _to != null || d.isBefore(_from!)) {
        _from = d;
        _to = null;
      } else {
        _to = d;
      }
    });
  }

  String _fmt(DateTime d) => '${d.day} ${_monthsShort[d.month - 1]}';

  void _apply() {
    if (_custom && _from != null) {
      final label = _to != null ? '${_fmt(_from!)} – ${_fmt(_to!)}' : _fmt(_from!);
      widget.onApply(label);
    } else {
      widget.onApply(_preset);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(18.w, 6.h, 14.w, 8.h),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Period', style: AppText.custom(size: 17, weight: FontWeight.w700, color: AppColors.textPrimary)),
              GestureDetector(
                onTap: widget.onClose,
                child: Container(
                  width: 32.w,
                  height: 32.w,
                  decoration: BoxDecoration(color: DashColors.chipGrey, borderRadius: BorderRadius.circular(9.r)),
                  child: Icon(PhosphorIconsBold.x, size: 15.sp, color: AppColors.textLabelAlt),
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 10.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _presetGrid(),
                _customTrigger(),
                if (_custom) _customBody(),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(18.w, 10.h, 18.w, 26.h),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: _apply,
                child: Container(
                  height: 46.h,
                  padding: EdgeInsets.symmetric(horizontal: 26.w),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(13.r),
                    boxShadow: [BoxShadow(color: AppColors.navy.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 8))],
                  ),
                  child: Text('Apply', style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.white)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _presetGrid() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 2.w),
      child: Column(
        children: [
          for (int r = 0; r < _presets.length; r += 2)
            Row(
              children: [
                Expanded(child: _presetCell(_presets[r])),
                SizedBox(width: 18.w),
                Expanded(
                  child: (r + 1) < _presets.length ? _presetCell(_presets[r + 1]) : const SizedBox(),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _presetCell(String label) {
    final on = _preset == label && !_custom;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _preset = label;
        _custom = false;
      }),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 10.h),
        child: Text(label,
            style: AppText.custom(
                size: 14, weight: on ? FontWeight.w800 : FontWeight.w500, color: on ? AppColors.textPrimary : AppColors.textMuted)),
      ),
    );
  }

  Widget _customTrigger() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _custom = !_custom),
      child: Container(
        margin: EdgeInsets.only(top: 10.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 13.h),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: AppColors.borderCardSoft),
        ),
        child: Row(
          children: [
            Icon(PhosphorIconsRegular.calendarBlank, size: 16.sp, color: AppColors.textSecondary),
            SizedBox(width: 10.w),
            Expanded(
              child: Text('Custom range', style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textBody)),
            ),
            Icon(_custom ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown, size: 12.sp, color: DashColors.textMid),
          ],
        ),
      ),
    );
  }

  Widget _customBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 12.h),
        Row(
          children: [
            Expanded(child: _dateField('From', _from)),
            SizedBox(width: 10.w),
            Expanded(child: _dateField('To', _to)),
          ],
        ),
        SizedBox(height: 12.h),
        _calendar(),
      ],
    );
  }

  Widget _dateField(String label, DateTime? value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.custom(size: 12, weight: FontWeight.w600, color: DashColors.textMid)),
        SizedBox(height: 5.h),
        Container(
          height: 42.h,
          padding: EdgeInsets.symmetric(horizontal: 11.w),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(11.r),
            border: Border.all(color: AppColors.borderInput),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(value == null ? 'Select' : _fmt(value),
                    style: AppText.custom(
                        size: 13.5, weight: value == null ? FontWeight.w500 : FontWeight.w700,
                        color: value == null ? AppColors.textPlaceholder : AppColors.textBody)),
              ),
              Icon(PhosphorIconsRegular.calendarBlank, size: 14.sp, color: AppColors.textPlaceholder),
            ],
          ),
        ),
      ],
    );
  }

  Widget _calendar() {
    final firstWeekday = DateTime(_calY, _calM + 1, 1).weekday % 7; // 0 = Sunday
    final nDays = DateTime(_calY, _calM + 2, 0).day;
    const dows = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final cells = <Widget>[];
    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox());
    }
    for (int day = 1; day <= nDays; day++) {
      final d = DateTime(_calY, _calM + 1, day);
      final isFrom = _from != null && _sameDay(d, _from!);
      final isTo = _to != null && _sameDay(d, _to!);
      final inRange = _from != null && _to != null && d.isAfter(_from!) && d.isBefore(_to!);
      cells.add(GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _pickDay(d),
        child: Container(
          height: 34.h,
          alignment: Alignment.center,
          margin: EdgeInsets.symmetric(vertical: 1.h),
          decoration: BoxDecoration(
            color: (isFrom || isTo)
                ? AppColors.navy
                : inRange
                    ? AppColors.blueSubtle
                    : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Text('$day',
              style: AppText.custom(
                  size: 12.5,
                  weight: (isFrom || isTo) ? FontWeight.w800 : FontWeight.w600,
                  color: (isFrom || isTo) ? AppColors.white : AppColors.textBody)),
        ),
      ));
    }

    return Container(
      margin: EdgeInsets.only(top: 12.h),
      padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 8.h),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppColors.borderCardSoft),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => setState(() {
                  if (_calM == 0) {
                    _calM = 11;
                    _calY--;
                  } else {
                    _calM--;
                  }
                }),
                child: Icon(PhosphorIconsBold.caretLeft, size: 14.sp, color: AppColors.textSecondary),
              ),
              Text('${_monthsFull[_calM]} $_calY',
                  style: AppText.custom(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
              GestureDetector(
                onTap: () => setState(() {
                  if (_calM == 11) {
                    _calM = 0;
                    _calY++;
                  } else {
                    _calM++;
                  }
                }),
                child: Icon(PhosphorIconsBold.caretRight, size: 14.sp, color: AppColors.textSecondary),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              for (final d in dows)
                Expanded(
                  child: Center(
                    child: Text(d, style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder)),
                  ),
                ),
            ],
          ),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.05,
            children: cells,
          ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}
