import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../infrastructure/data_sources/remote/crm_tasks_remote_ds.dart';
import 'add_sheet_kit.dart';

/// Moves a follow-up's due date and time.
///
/// Returns the `PATCH /crm/tasks/{id}/` body — `due_date` and, when given,
/// `due_time` — or null when dismissed, which the caller must read as "no
/// change" rather than "clear the date".
///
/// A date is required: rescheduling to nothing is not rescheduling, and the
/// whole point of the action is to move the follow-up to a specific moment.
Future<Map<String, dynamic>?> showRescheduleSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String due,
  required String time,
}) {
  return showClozrSheet<Map<String, dynamic>>(
    context: context,
    builder: (_) => _RescheduleSheet(ref: ref, due: due, time: time),
  );
}

class _RescheduleSheet extends StatefulWidget {
  const _RescheduleSheet({required this.ref, required this.due, required this.time});

  final WidgetRef ref;

  /// The current values, in the display forms the entity carries
  /// ("16 Jun 2026" and "09:30").
  final String due;
  final String time;

  @override
  State<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<_RescheduleSheet> {
  late final TextEditingController _date =
      TextEditingController(text: widget.due.trim());
  late final TextEditingController _time =
      TextEditingController(text: widget.time.trim());
  bool _showErrors = false;

  @override
  void dispose() {
    _date.dispose();
    _time.dispose();
    super.dispose();
  }

  /// The API-shaped date, or null when the box cannot be parsed. Accepts both
  /// ISO and the "24 Jun 2026" display form the entity holds.
  String? get _isoDate => CrmTasksRemoteDataSource.isoDateOrNull(_date.text);

  Future<void> _pickDate() async {
    final parsed = _isoDate;
    final initial = parsed == null ? DateTime.now() : DateTime.parse(parsed);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      // A follow-up can legitimately be moved backwards (logging one that
      // slipped) as well as forwards, so the range spans both.
      firstDate: DateTime(initial.year - 2),
      lastDate: DateTime(initial.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() => _date.text =
        '${picked.day.toString().padLeft(2, '0')} '
        '${_monthNames[picked.month - 1]} ${picked.year}');
  }

  Future<void> _pickTime() async {
    final now = TimeOfDay.now();
    final current = CrmTasksRemoteDataSource.apiTimeOrNull(_time.text);
    final picked = await showTimePicker(
      context: context,
      initialTime: current == null
          ? now
          : TimeOfDay(
              hour: int.parse(current.split(':')[0]),
              minute: int.parse(current.split(':')[1]),
            ),
    );
    if (picked == null || !mounted) return;
    setState(() => _time.text =
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}');
  }

  void _submit() {
    setState(() => _showErrors = true);
    final iso = _isoDate;
    if (iso == null) {
      widget.ref.read(toastProvider.notifier).show('Pick a due date');
      return;
    }
    final apiTime = CrmTasksRemoteDataSource.apiTimeOrNull(_time.text);
    Navigator.of(context).pop({
      'due_date': iso,
      // Omitted rather than sent blank when the box is empty: a follow-up with
      // no time is normal, and clearing it is not what "reschedule" means.
      if (apiTime != null) 'due_time': apiTime,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'Reschedule', onClose: () => Navigator.of(context).pop()),
        Padding(
          padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 12.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                label: 'Due date',
                required: true,
                readOnly: true,
                onTap: _pickDate,
                value: _date.text.isEmpty ? null : _date.text,
                hint: 'e.g. 24 Jun 2026',
                suffixIcon: PhosphorIconsRegular.calendarBlank,
                errorText:
                    _showErrors && _isoDate == null ? 'Pick a due date' : null,
              ),
              SizedBox(height: 14.h),
              AppTextField(
                label: 'Due time',
                readOnly: true,
                onTap: _pickTime,
                value: _time.text.isEmpty ? null : _time.text,
                hint: 'Optional — e.g. 10:00',
                suffixIcon: PhosphorIconsRegular.clock,
              ),
              SizedBox(height: 8.h),
              Text(
                'Moving a follow-up updates its due date on the server; the '
                'activity log records the change.',
                style: AppText.custom(
                        size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder)
                    .copyWith(height: 1.4),
              ),
            ],
          ),
        ),
        SheetSubmitBar(
          label: 'Reschedule',
          icon: PhosphorIconsBold.calendarPlus,
          onTap: _submit,
        ),
      ],
    );
  }
}

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
