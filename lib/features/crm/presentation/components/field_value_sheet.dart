import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../application/record_rows.dart';
import '../sheets/add_sheet_kit.dart'
    show pickSheetDate, pickSheetTime, sheetDateLabel, sheetIsoDate;

/// What the sheet hands back. A record rather than the bare value so that
/// "cleared" (`value == null`) is distinguishable from "dismissed" (null).
typedef FieldValueResult = ({Object? value});

/// The webapp's inline editors for the types a text box cannot do — date,
/// date-time, Yes / No, a one-of choice and a many-of choice — as a sheet.
///
/// [initial] is the stored value as the record carries it (`2026-11-10`,
/// `true`, a choice value, or a list of them). The result is already in the
/// shape the API takes: an ISO date, a bool, a choice value, a list of values;
/// null clears the field.
Future<FieldValueResult?> showFieldValueSheet(
  BuildContext context, {
  required String label,
  required InlineKind kind,
  required Object? initial,
  List<(String, String)> options = const [],
  String blankLabel = '—',
}) {
  return showClozrSheet<FieldValueResult>(
    context: context,
    builder: (_) => _FieldValueSheet(
        label: label,
        kind: kind,
        initial: initial,
        options: options,
        blankLabel: blankLabel),
  );
}

class _FieldValueSheet extends StatefulWidget {
  const _FieldValueSheet({
    required this.label,
    required this.kind,
    required this.initial,
    required this.options,
    this.blankLabel = '—',
  });

  final String blankLabel;
  final String label;
  final InlineKind kind;
  final Object? initial;
  final List<(String, String)> options;

  @override
  State<_FieldValueSheet> createState() => _FieldValueSheetState();
}

class _FieldValueSheetState extends State<_FieldValueSheet> {
  DateTime? _date;
  TimeOfDay? _time;
  bool? _bool;
  String _one = '';
  late final Set<String> _many;

  @override
  void initState() {
    super.initState();
    final raw = widget.initial;
    switch (widget.kind) {
      case InlineKind.date:
      case InlineKind.datetime:
        final parsed = raw == null ? null : DateTime.tryParse('$raw');
        if (parsed != null) {
          _date = DateTime(parsed.year, parsed.month, parsed.day);
          if (widget.kind == InlineKind.datetime && '$raw'.contains('T')) {
            final local = parsed.toLocal();
            _time = TimeOfDay(hour: local.hour, minute: local.minute);
          }
        }
      case InlineKind.boolean:
        _bool = raw is bool ? raw : (raw == null ? null : '$raw' == 'true');
      case InlineKind.select:
        _one = raw == null ? '' : '$raw';
      case _:
        break;
    }
    _many = {
      if (raw is List)
        for (final v in raw) '$v'
      else if (raw is String && raw.isNotEmpty && raw.contains(','))
        ...raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty)
      else if (raw is String && raw.isNotEmpty)
        raw,
    };
  }

  Object? _result() {
    switch (widget.kind) {
      case InlineKind.date:
        return _date == null ? null : sheetIsoDate(_date!);
      case InlineKind.datetime:
        if (_date == null) return null;
        final t = _time ?? const TimeOfDay(hour: 0, minute: 0);
        return '${sheetIsoDate(_date!)}T'
            '${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}';
      case InlineKind.boolean:
        return _bool ?? false;
      case InlineKind.select:
        return _one.isEmpty ? null : _one;
      case InlineKind.multiselect:
        return _many.isEmpty
            ? null
            : [
                for (final (v, _) in widget.options)
                  if (_many.contains(v)) v
              ];
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: widget.label),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 8.h),
              child: _editor(),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
            child: Row(
              children: [
                Expanded(
                    child: PrimaryButton(
                        label: 'Cancel',
                        ghost: true,
                        onTap: () => Navigator.of(context).pop())),
                SizedBox(width: 10.w),
                Expanded(
                  flex: 2,
                  child: PrimaryButton(
                      label: 'Save',
                      onTap: () => Navigator.of(context)
                          .pop<FieldValueResult>((value: _result()))),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _editor() {
    switch (widget.kind) {
      case InlineKind.boolean:
        return Wrap(spacing: 8.w, children: [
          for (final (v, l) in const [(true, 'Yes'), (false, 'No')])
            ChoiceChip(
                label: Text(l),
                selected: _bool == v,
                onSelected: (_) => setState(() => _bool = v)),
        ]);
      case InlineKind.date:
      case InlineKind.datetime:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              label: widget.label,
              readOnly: true,
              value: _date == null ? '' : sheetDateLabel(_date!),
              hint: 'Pick a date',
              suffixIcon: PhosphorIconsRegular.calendarBlank,
              onTap: () async {
                final d = await pickSheetDate(
                    context, _date == null ? '' : sheetIsoDate(_date!));
                if (d != null && mounted) setState(() => _date = d);
              },
            ),
            if (widget.kind == InlineKind.datetime) ...[
              SizedBox(height: 12.h),
              AppTextField(
                label: 'Time',
                readOnly: true,
                value: _time == null
                    ? ''
                    : '${_time!.hour.toString().padLeft(2, '0')}:'
                        '${_time!.minute.toString().padLeft(2, '0')}',
                hint: 'Pick a time',
                suffixIcon: PhosphorIconsRegular.clock,
                onTap: () async {
                  final t = await pickSheetTime(
                      context,
                      _time == null
                          ? ''
                          : '${_time!.hour}:${_time!.minute.toString().padLeft(2, '0')}');
                  if (t != null && mounted) setState(() => _time = t);
                },
              ),
            ],
            if (_date != null)
              TextButton(
                  onPressed: () => setState(() {
                        _date = null;
                        _time = null;
                      }),
                  child: const Text('Clear')),
          ],
        );
      case InlineKind.select:
        return Column(children: [
          for (final (v, l) in [('', widget.blankLabel), ...widget.options])
            _choiceRow(l,
                selected: _one == v,
                multi: false,
                onTap: () => setState(() => _one = v)),
        ]);
      case InlineKind.multiselect:
        return Column(children: [
          for (final (v, l) in widget.options)
            _choiceRow(l,
                selected: _many.contains(v),
                multi: true,
                onTap: () => setState(() {
                      if (!_many.remove(v)) _many.add(v);
                    })),
        ]);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _choiceRow(String label,
      {required bool selected,
      required bool multi,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 4.w),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: AppText.custom(
                      size: 14,
                      weight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: AppColors.textPrimary)),
            ),
            if (multi)
              Icon(
                  selected
                      ? PhosphorIconsFill.checkSquare
                      : PhosphorIconsRegular.square,
                  size: 20.sp,
                  color: selected
                      ? AppColors.blueBright
                      : AppColors.textPlaceholder)
            else if (selected)
              Icon(PhosphorIconsBold.check,
                  size: 16.sp, color: AppColors.blueBright),
          ],
        ),
      ),
    );
  }
}
