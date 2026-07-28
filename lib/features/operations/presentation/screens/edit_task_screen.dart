import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/ops_tasks_providers.dart';
import '../../application/providers/projects_providers.dart';
import '../components/ops_form_scaffold.dart';
import '../components/ops_widgets.dart';

/// Edit Task — prefilled form. Expected End must be ≥ Start; the progress slider
/// shows only when the task has no subtasks (otherwise it's calculated).
class EditTaskScreen extends ConsumerStatefulWidget {
  const EditTaskScreen({super.key});

  @override
  ConsumerState<EditTaskScreen> createState() => _EditTaskScreenState();
}

class _EditTaskScreenState extends ConsumerState<EditTaskScreen> {
  final _subject = TextEditingController();
  final _desc = TextEditingController();
  final _hours = TextEditingController();

  bool _init = false;
  bool _dirty = false;
  String _id = '';
  String? _projId;
  String _group = 'Design';
  String _ttype = 'Task';
  String _status = 'open';
  String _pri = 'Medium';
  final Set<String> _assignees = {};
  DateTime? _start;
  DateTime? _end;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  String _weight = '1';
  String _dept = 'Projects';
  bool _milestone = false;
  String _colorName = 'Blue';
  double _progress = 0;
  bool _hasSubs = false;

  static const _ttypes = ['Task', 'Approval', 'Site visit', 'Meeting'];
  static const _depts = ['Projects', 'Design', 'MEP', 'Workshop', 'Snagging', 'Accounts'];
  static const _weights = ['1', '2', '3', '4', '5'];
  static const _colors = <(String, Color)>[
    ('Blue', AppColors.blueBright),
    ('Green', AppColors.success),
    ('Amber', AppColors.warning),
    ('Purple', AppColors.pending),
    ('Red', AppColors.error),
    ('Gray', AppColors.textMuted),
  ];

  @override
  void dispose() {
    _subject.dispose();
    _desc.dispose();
    _hours.dispose();
    super.dispose();
  }

  void _dirtied() {
    if (!_dirty) _dirty = true;
  }

  bool get _endErr => _start != null && _end != null && _end!.isBefore(_start!);

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final task = ref.watch(opsTaskByIdProvider(id));
    final projects = ref.watch(projectsListProvider);
    final allTasks = ref.watch(opsTasksListProvider);

    if (task == null) {
      return OpsEditScaffold(
        title: 'Edit task',
        subtitle: '—',
        onClose: () => context.pop(),
        onSave: () => context.pop(),
        children: const [Center(child: Text('Task not found'))],
      );
    }

    if (!_init) {
      _init = true;
      _id = task.id;
      _subject.text = task.subject;
      _desc.text = task.desc;
      _hours.text = '${task.expHrs}';
      _projId = task.projId;
      _group = task.group;
      _status = task.status;
      _pri = task.pri;
      _assignees.addAll(task.assignees);
      _start = opsParseDisplayDate(task.start);
      _end = opsParseDisplayDate(task.end);
      _startTime = opsParseTime(task.startTime);
      _endTime = opsParseTime(task.endTime);
      _weight = '${task.weight}';
      _dept = task.dept;
      _milestone = task.milestone;
      _colorName = task.color.name;
      _hasSubs = task.subtasks.isNotEmpty;
      _progress = (task.computedProgress(task.subtasks)).toDouble();
    }

    final projName = _projId == null ? '' : projects.where((p) => p.id == _projId).map((p) => p.name).firstOrNull ?? '';
    final groups = <String>{_group};
    for (final t in allTasks.where((t) => t.projId == _projId)) {
      groups.add(t.group);
    }

    return OpsEditScaffold(
      title: 'Edit task',
      subtitle: '$_id · changes apply on save',
      onClose: () => handleEditClose(context, dirty: _dirty),
      onSave: () {
        ref.read(toastProvider.notifier).show('Changes saved');
        context.pop();
      },
      children: [
        const OpsSectionLabel('Basics', first: true),
        AppTextField(label: 'Subject', required: true, controller: _subject, hint: 'What needs to happen?', onChanged: (_) => setState(_dirtied)),
        SizedBox(height: 14.h),
        AppTextField(label: 'Description', controller: _desc, hint: 'Add detail for the crew…', multiline: true, onChanged: (_) => _dirtied()),
        SizedBox(height: 14.h),
        OpsPickerField(
          label: 'Project',
          value: projName,
          placeholder: 'Select project…',
          caret: PhosphorIconsBold.caretRight,
          onTap: () async {
            final v = await showOpsOptionPicker(context: context, title: 'Select project', options: [for (final p in projects) (value: p.id, label: p.name)], currentValue: _projId ?? '');
            if (v != null) setState(() { _projId = v; _dirtied(); });
          },
        ),
        SizedBox(height: 14.h),
        Row(
          children: [
            Expanded(
              child: OpsPickerField(
                label: 'Task group',
                value: _group,
                onTap: () async {
                  final v = await showOpsOptionPicker(context: context, title: 'Task group', options: [for (final g in groups) (value: g, label: g)], currentValue: _group);
                  if (v != null) setState(() { _group = v; _dirtied(); });
                },
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: OpsPickerField(
                label: 'Type',
                value: _ttype,
                onTap: () async {
                  final v = await showOpsOptionPicker(context: context, title: 'Type', options: [for (final t in _ttypes) (value: t, label: t)], currentValue: _ttype);
                  if (v != null) setState(() { _ttype = v; _dirtied(); });
                },
              ),
            ),
          ],
        ),
        SizedBox(height: 14.h),
        _label('Status'),
        SizedBox(height: 7.h),
        Wrap(spacing: 8.w, runSpacing: 8.h, children: [
          for (final e in StatusMeta$.opsTask.entries)
            OpsFormChip(label: e.value.label, selected: _status == e.key, tone: e.value.color, onTap: () => setState(() { _status = e.key; _dirtied(); })),
        ]),
        SizedBox(height: 14.h),
        _label('Priority'),
        SizedBox(height: 7.h),
        Wrap(spacing: 8.w, runSpacing: 8.h, children: [
          for (final p in const ['High', 'Medium', 'Low'])
            OpsFormChip(label: p, selected: _pri == p, tone: StatusMeta$.projectPriority[p], onTap: () => setState(() { _pri = p; _dirtied(); })),
        ]),
        SizedBox(height: 14.h),
        _label('Assignee'),
        SizedBox(height: 7.h),
        Wrap(spacing: 8.w, runSpacing: 8.h, children: [
          for (final r in MockUsers.reps)
            OpsAssigneeChip(
              initials: r.initials,
              name: r.firstName,
              color: MockUsers.memberColors[r.id] ?? AppColors.navy,
              selected: _assignees.contains(r.id),
              filled: false,
              onTap: () => setState(() { _assignees.contains(r.id) ? _assignees.remove(r.id) : _assignees.add(r.id); _dirtied(); }),
            ),
        ]),
        const OpsSectionLabel('Schedule'),
        Row(
          children: [
            Expanded(flex: 13, child: _dateField('Expected start', _start, (d) => setState(() { _start = d; _dirtied(); }))),
            SizedBox(width: 10.w),
            Expanded(flex: 10, child: _timeField('Time', _startTime, (t) => setState(() { _startTime = t; _dirtied(); }))),
          ],
        ),
        SizedBox(height: 14.h),
        Row(
          children: [
            Expanded(
              flex: 13,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _dateField('Expected end', _end, (d) => setState(() { _end = d; _dirtied(); })),
                  if (_endErr)
                    Padding(
                      padding: EdgeInsets.only(top: 6.h),
                      child: Text('Ends before it starts', style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.error)),
                    ),
                ],
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(flex: 10, child: _timeField('Time', _endTime, (t) => setState(() { _endTime = t; _dirtied(); }))),
          ],
        ),
        SizedBox(height: 14.h),
        Row(
          children: [
            Expanded(child: AppTextField(label: 'Expected time (hrs)', controller: _hours, keyboardType: TextInputType.number, onChanged: (_) => _dirtied())),
            SizedBox(width: 10.w),
            Expanded(
              child: OpsPickerField(
                label: 'Task weight',
                value: _weight,
                onTap: () async {
                  final v = await showOpsOptionPicker(context: context, title: 'Task weight', options: [for (final w in _weights) (value: w, label: w)], currentValue: _weight);
                  if (v != null) setState(() { _weight = v; _dirtied(); });
                },
              ),
            ),
          ],
        ),
        const OpsSectionLabel('Classification'),
        OpsPickerField(
          label: 'Department',
          value: _dept,
          onTap: () async {
            final v = await showOpsOptionPicker(context: context, title: 'Department', options: [for (final d in _depts) (value: d, label: d)], currentValue: _dept);
            if (v != null) setState(() { _dept = v; _dirtied(); });
          },
        ),
        SizedBox(height: 14.h),
        _milestoneToggle(),
        SizedBox(height: 14.h),
        _label('Color tag'),
        SizedBox(height: 7.h),
        Wrap(spacing: 8.w, runSpacing: 8.h, children: [
          for (final (name, color) in _colors)
            OpsFormChip(label: name, selected: _colorName == name, tone: color, onTap: () => setState(() { _colorName = name; _dirtied(); })),
        ]),
        const OpsSectionLabel('Progress'),
        if (!_hasSubs) _progressSlider() else _calculatedProgress(),
      ],
    );
  }

  Widget _label(String t) => Text(t, style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt));

  Widget _milestoneToggle() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 13.h),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.borderCardSoft),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Milestone', style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 1.h),
                Text('Marks a key delivery point', style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() { _milestone = !_milestone; _dirtied(); }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 46.w,
              height: 27.h,
              padding: EdgeInsets.all(3.r),
              alignment: _milestone ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: _milestone ? AppColors.navy : const Color(0xFFD8DADF),
                borderRadius: BorderRadius.circular(999.r),
              ),
              child: Container(
                width: 21.w,
                height: 21.w,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 3, offset: const Offset(0, 1))],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressSlider() {
    return Container(
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.borderCardSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _label('Progress'),
              const Spacer(),
              Text('${_progress.round()}%', style: AppText.custom(size: 13.5, weight: FontWeight.w800, color: AppColors.textPrimary)),
            ],
          ),
          SizedBox(height: 4.h),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.navy,
              thumbColor: AppColors.navy,
              inactiveTrackColor: AppColors.borderCardSoft,
              overlayColor: AppColors.navy.withOpacity(0.12),
            ),
            child: Slider(
              value: _progress,
              min: 0,
              max: 100,
              divisions: 20,
              onChanged: (v) => setState(() { _progress = v; _dirtied(); }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _calculatedProgress() {
    return Container(
      height: 46.h,
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      decoration: BoxDecoration(color: const Color(0xFFEFF0F2), borderRadius: BorderRadius.circular(11.r)),
      child: Row(
        children: [
          Text('${_progress.round()}%', style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPlaceholder)),
          const Spacer(),
          Text('Calculated from subtasks', style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
        ],
      ),
    );
  }

  Widget _dateField(String label, DateTime? value, ValueChanged<DateTime> onPick) {
    return OpsPickerField(
      label: label,
      value: value == null ? '' : opsFmtDate(value),
      placeholder: 'Pick a date',
      caret: PhosphorIconsRegular.calendarBlank,
      onTap: () async {
        final d = await showDatePicker(context: context, initialDate: value ?? DateTime(2026, 7, 9), firstDate: DateTime(2024), lastDate: DateTime(2030));
        if (d != null) onPick(d);
      },
    );
  }

  Widget _timeField(String label, TimeOfDay? value, ValueChanged<TimeOfDay> onPick) {
    return OpsPickerField(
      label: label,
      value: value == null ? '' : opsFmtTime(value),
      placeholder: 'Time',
      caret: PhosphorIconsRegular.clock,
      onTap: () async {
        final t = await showTimePicker(context: context, initialTime: value ?? const TimeOfDay(hour: 9, minute: 0));
        if (t != null) onPick(t);
      },
    );
  }
}
