import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/ops_tasks_providers.dart';
import '../../application/providers/projects_providers.dart';
import '../components/ops_form_scaffold.dart';
import '../components/ops_widgets.dart';

/// New Task — full-screen create form.
class CreateTaskScreen extends ConsumerStatefulWidget {
  const CreateTaskScreen({super.key});

  @override
  ConsumerState<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends ConsumerState<CreateTaskScreen> {
  final _subject = TextEditingController();
  final _hours = TextEditingController();
  final _desc = TextEditingController();

  String? _projId;
  String _group = 'No group';
  final Set<String> _assignees = {};
  String _status = 'open';
  String _pri = 'Medium';
  DateTime? _start;
  DateTime? _end;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  @override
  void dispose() {
    _subject.dispose();
    _hours.dispose();
    _desc.dispose();
    super.dispose();
  }

  bool get _endErr => _start != null && _end != null && _end!.isBefore(_start!);
  bool get _valid => _subject.text.trim().isNotEmpty && _projId != null;

  /// API mode: create remotely, refresh the list, toast + pop as before.
  /// Mock mode: exactly the previous local toast-and-pop behavior.
  ///
  /// `_projId` comes from the project dropdown: in API mode that list is the
  /// live projects whose ids are `project_id` UUIDs, so it is safe to send as
  /// the task's `project` FK (in mock mode it would be a `PRJ-24xx` seed id,
  /// but this branch never runs there).
  Future<void> _submit() async {
    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show('Task created');
      context.pop();
      return;
    }
    try {
      await ref.read(opsTasksRepositoryProvider).createOpsTask({
        'subject': _subject.text.trim(),
        if (_projId != null) 'project': _projId,
        'priority': _pri,
        'description': _desc.text.trim(),
      });
      if (!mounted) return;
      ref.invalidate(opsTasksProvider);
      ref.read(toastProvider.notifier).show('Task created');
      context.pop();
    } on AppError catch (e) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsListProvider);
    final tasks = ref.watch(opsTasksListProvider);
    final projName = _projId == null ? '' : projects.where((p) => p.id == _projId).map((p) => p.name).firstOrNull ?? '';

    final groups = <String>{'No group'};
    for (final t in tasks.where((t) => t.projId == _projId)) {
      groups.add(t.group);
    }
    if (groups.length == 1) groups.addAll(['Design', 'Site works', 'Snagging']);

    return OpsFormScaffold(
      title: 'New Task',
      ctaLabel: 'Create Task',
      ctaEnabled: _valid,
      onClose: () => context.pop(),
      onSubmit: _submit,
      children: [
        AppTextField(label: 'Subject', required: true, controller: _subject, hint: 'What needs doing?', onChanged: (_) => setState(() {})),
        SizedBox(height: 14.h),
        OpsPickerField(
          label: 'Project',
          required: true,
          value: projName,
          placeholder: 'Select project…',
          caret: PhosphorIconsRegular.magnifyingGlass,
          onTap: () async {
            final v = await showOpsOptionPicker(
              context: context,
              title: 'Select project',
              options: [for (final p in projects) (value: p.id, label: p.name)],
              currentValue: _projId ?? '',
            );
            if (v != null) setState(() { _projId = v; _group = 'No group'; });
          },
        ),
        SizedBox(height: 14.h),
        OpsPickerField(
          label: 'Task group',
          value: _group,
          onTap: () async {
            final v = await showOpsOptionPicker(
              context: context,
              title: 'Task group',
              options: [for (final g in groups) (value: g, label: g)],
              currentValue: _group,
            );
            if (v != null) setState(() => _group = v);
          },
        ),
        SizedBox(height: 14.h),
        _label('Assignees'),
        SizedBox(height: 7.h),
        _assigneeWrap(),
        SizedBox(height: 14.h),
        _label('Status'),
        SizedBox(height: 7.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            for (final e in StatusMeta$.opsTask.entries)
              OpsFormChip(label: e.value.label, selected: _status == e.key, onTap: () => setState(() => _status = e.key)),
          ],
        ),
        SizedBox(height: 14.h),
        _label('Priority'),
        SizedBox(height: 7.h),
        Wrap(
          spacing: 8.w,
          children: [
            for (final p in const ['High', 'Medium', 'Low'])
              OpsFormChip(label: p, selected: _pri == p, onTap: () => setState(() => _pri = p)),
          ],
        ),
        SizedBox(height: 14.h),
        Row(
          children: [
            Expanded(child: _dateField('Expected start', _start, (d) => setState(() => _start = d))),
            SizedBox(width: 9.w),
            Expanded(child: _timeField('Start time', _startTime, (t) => setState(() => _startTime = t))),
          ],
        ),
        SizedBox(height: 14.h),
        Row(
          children: [
            Expanded(child: _dateField('Expected end', _end, (d) => setState(() => _end = d), error: _endErr)),
            SizedBox(width: 9.w),
            Expanded(child: _timeField('End time', _endTime, (t) => setState(() => _endTime = t))),
          ],
        ),
        if (_endErr) ...[
          SizedBox(height: 8.h),
          Text('End must be on or after start.', style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.error)),
        ],
        SizedBox(height: 14.h),
        AppTextField(label: 'Expected time (hrs)', controller: _hours, hint: '0', keyboardType: TextInputType.number),
        SizedBox(height: 14.h),
        AppTextField(label: 'Description', controller: _desc, hint: 'Add any detail…', multiline: true),
      ],
    );
  }

  Widget _label(String t) => Text(t, style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt));

  Widget _assigneeWrap() {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: [
        for (final r in ref.watch(rosterProvider))
          OpsAssigneeChip(
            initials: r.initials,
            name: r.firstName,
            color: MockUsers.memberColors[r.id] ?? AppColors.navy,
            selected: _assignees.contains(r.id),
            onTap: () => setState(() => _assignees.contains(r.id) ? _assignees.remove(r.id) : _assignees.add(r.id)),
          ),
      ],
    );
  }

  Widget _dateField(String label, DateTime? value, ValueChanged<DateTime> onPick, {bool error = false}) {
    return OpsPickerField(
      label: label,
      value: value == null ? '' : opsFmtDate(value),
      placeholder: 'Pick a date',
      caret: PhosphorIconsRegular.calendarBlank,
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime(2026, 7, 9),
          firstDate: DateTime(2024),
          lastDate: DateTime(2030),
        );
        if (d != null) onPick(d);
      },
    );
  }

  Widget _timeField(String label, TimeOfDay? value, ValueChanged<TimeOfDay> onPick) {
    return OpsPickerField(
      label: label,
      value: value == null ? '' : opsFmtTime(value),
      placeholder: 'Pick time',
      caret: PhosphorIconsRegular.clock,
      onTap: () async {
        final t = await showTimePicker(context: context, initialTime: value ?? const TimeOfDay(hour: 9, minute: 0));
        if (t != null) onPick(t);
      },
    );
  }
}
