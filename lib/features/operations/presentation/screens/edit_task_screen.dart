import 'package:flutter/material.dart';
import '../../../../core/filters/filter_models.dart';
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
import '../../../../data/api/status_keys.dart';
import '../../../crm/domain/entities/crm_catalog.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../../../core/network/network_providers.dart';
import '../../../crm/presentation/components/due_date_change.dart';
import '../../application/ops_task_write_fields.dart';
import '../../application/project_write_fields.dart' show apiDate;
import '../../application/project_task_error.dart';
import '../../application/providers/ops_tasks_providers.dart';
import '../../domain/entities/ops_task.dart';
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
  bool _fromDetail = false;
  bool _dirty = false;
  bool _saving = false;
  /// The uuid — the write key, never shown.
  String _id = '';

  /// The human code the header shows. It printed [_id], so the user saw
  /// 36 characters of uuid where the record's own number belongs.
  String _code = '';
  String? _projId;
  String _groupId = '';
  String _group = 'No group';
  /// `task_type_id`, empty when the task has no type.
  String _ttype = '';
  String _status = 'open';
  String _pri = 'Medium';
  final Set<String> _assignees = {};
  DateTime? _start;
  DateTime? _end;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  String _weight = '1';
  final _dept = TextEditingController();
  bool _milestone = false;
  double _progress = 0;
  bool _hasSubs = false;

  /// `color` — lowercase `#rrggbb`, empty for none (webapp "Color tag").
  String _color = '';

  /// The write body as prefilled — the save sends only what differs from it,
  /// as the webapp does, so a cleared value goes out as an explicit null.
  Map<String, dynamic>? _original;

  /// Whether the task had an expected end when the form opened: moving an
  /// existing date may need a reason (SLA engine).
  bool _hadEnd = false;

  static const _weights = ['1', '2', '3', '4', '5'];

  /// The colour-tag swatches (any `#rrggbb` is valid server-side).
  static const _swatches = [
    '#e74c3c', '#e67e22', '#f1c40f', '#2ecc71', '#1abc9c', '#3498db', '#9b59b6', '#34495e',
  ];

  @override
  void dispose() {
    _subject.dispose();
    _desc.dispose();
    _hours.dispose();
    _dept.dispose();
    super.dispose();
  }

  void _dirtied() {
    if (!_dirty) _dirty = true;
  }

  bool get _endErr => _start != null && _end != null && _end!.isBefore(_start!);

  void _prefill(OpsTask task) {
    _id = task.id;
    _code = task.code;
    _subject.text = task.subject;
    _desc.text = task.desc;
    // Blank until the retrieve answers: `?view=list` drops both decimals, and
    // a "0" the user did not type would be written straight back on save.
    _hours.text = task.expHrs == null ? '' : opsDecimalLabel(task.expHrs!);
    _projId = task.projId;
    _groupId = task.groupId;
    _group = task.group;
    _ttype = task.typeId;
    // The org's own status name, so the chip built from the catalog matches;
    // the folded key is the fallback before the catalog answers.
    _status = task.statusName.isNotEmpty ? task.statusName : task.status;
    _pri = task.pri;
    _assignees
      ..clear()
      ..addAll(task.assignees);
    _start = opsParseDisplayDate(task.start);
    _end = opsParseDisplayDate(task.end);
    _startTime = opsParseTime(task.startTime);
    _endTime = opsParseTime(task.endTime);
    // The picker offers whole numbers, but the field is a decimal server-side —
    // keep whatever is stored so an untouched 3.5 is not silently rewritten.
    _weight = task.weight == null ? '1' : opsDecimalLabel(task.weight!);
    _dept.text = task.dept;
    _color = RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(task.color.name) ? task.color.name.toLowerCase() : '';
    _milestone = task.milestone;
    _hadEnd = task.endISO.trim().isNotEmpty;
    // `subtasks` is never embedded by the API, so the count is what says
    // whether progress is rolled up from children or set by hand here.
    _hasSubs = task.subtasks.isNotEmpty || task.subtaskCount > 0;
    _progress = (task.computedProgress(task.subtasks)).toDouble();
    _original = _body();
  }

  /// Every field the form edits, as the PATCH would carry it — a cleared
  /// project, group, type or date as null (the webapp's `fkSelect` / date
  /// clear), the description and department as plain (possibly empty) text.
  Map<String, dynamic> _body() {
    final base = opsTaskWriteFields(
      subject: _subject.text,
      priority: _pri,
      description: _desc.text,
      projectId: _projId,
      groupId: _groupId,
      statusLabel: _statusKey,
      assigneeIds: _assignees,
      start: _start,
      startTime: _startTime,
      end: _end,
      endTime: _endTime,
      expectedHours: _hours.text,
      weight: _weight,
      statuses: ref.read(opsTaskStatusOptionsProvider),
    );
    return {
      ...base,
      'project': (_projId ?? '').isEmpty ? null : _projId,
      'task_group': _groupId.isEmpty ? null : _groupId,
      'type': _ttype.isEmpty ? null : _ttype,
      'description': _desc.text.trim(),
      'exp_start_date': base['exp_start_date'],
      'exp_end_date': base['exp_end_date'],
      'is_milestone': _milestone,
      'department': _dept.text.trim(),
      'color': _color.isEmpty ? null : _color,
      // Leaf tasks only: a parent's progress is the subtasks' rollup.
      if (!_hasSubs) 'progress': _progress.round(),
    };
  }

  static bool _same(Object? a, Object? b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      final sa = a.map((e) => '$e').toSet();
      return b.every((e) => sa.contains('$e'));
    }
    return a == b;
  }

  /// The status chips: the org's own statuses once the catalog has answered,
  /// the built-in vocabulary before that and in mock mode.
  List<(String, String, Color?)> get _statusChips {
    // Read, not watched: the save builds its body outside build; the build
    // itself watches the catalog.
    final catalog = ref.read(opsTaskStatusOptionsProvider);
    if (catalog.isEmpty) {
      return [
        for (final e in StatusMeta$.opsTask.entries) (e.key, e.value.label, e.value.color),
      ];
    }
    return [
      for (final s in catalog)
        // The org's own colour (Settings › PMO) — the built-in palette only
        // when the org left it blank.
        (s.name, s.name, s.color ?? StatusMeta$.opsTask[opsTaskStatusKey(name: s.name)]?.color),
    ];
  }

  /// The selected status, corrected for the catalog arriving after the record:
  /// a task whose status the org renamed would otherwise show none selected.
  String get _statusKey {
    final chips = _statusChips;
    if (chips.isEmpty || chips.any((c) => c.$1 == _status)) return _status;
    return chips.first.$1;
  }

  /// API mode: PATCH the edited fields, refresh the list, toast + pop as
  /// before. Mock mode: exactly the previous local toast-and-pop behavior.
  ///
  /// Sends everything the form edits. It used to send only `subject`,
  /// `priority` and `description`, so a changed status, project, lane, type,
  /// assignee set, date, department or milestone flag was silently discarded.
  ///
  /// Sending the dates does re-run the backend's cross-field date validation
  /// (operations-task.md "PATCH is genuinely partial") — that is correct now
  /// that the form prefills from the real record rather than from a slim row
  /// with a blank start date.
  /// Webapp: PATCH only the changed keys → "Changes saved". A blank subject is
  /// refused first ("Subject is required"); a moved expected end goes through
  /// the SLA reason / approval flow — a 202 is "Sent to your manager for
  /// approval" and the date stays until the manager decides.
  Future<void> _save() async {
    if (_saving) return;
    if (_subject.text.trim().isEmpty) {
      ref.read(toastProvider.notifier).showError('Subject is required');
      return;
    }
    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show('Changes saved');
      context.pop();
      return;
    }
    final body = _body();
    final original = _original ?? const <String, dynamic>{};
    final patch = <String, dynamic>{
      for (final e in body.entries)
        if (!original.containsKey(e.key) || !_same(original[e.key], e.value)) e.key: e.value,
    };
    if (patch.isEmpty) {
      ref.read(toastProvider.notifier).show('Changes saved');
      context.pop();
      return;
    }
    setState(() => _saving = true);
    try {
      final outcome = await writeWithDueDateFlow(
        context,
        ref,
        path: '/projects/tasks/$_id/',
        fields: patch,
        hadDate: _hadEnd,
        dateKey: 'exp_end_date',
        fieldLabel: 'Expected end',
        dateLabel: _end == null ? 'no end date' : dueDateLabel(apiDate(_end!)),
      );
      if (!mounted) return;
      if (outcome == DueDateWrite.cancelled) {
        setState(() => _saving = false);
        return;
      }
      ref.invalidate(opsTasksProvider);
      ref.invalidate(opsTasksScopedProvider);
      // Await the record itself before leaving, so the detail screen does not
      // show the old values and then change under the user.
      ref.invalidate(opsTaskDetailProvider(_id));
      await ref.read(opsTaskDetailProvider(_id).future);
      if (!mounted) return;
      // A parked change already said "Sent to your manager for approval".
      if (outcome == DueDateWrite.saved) ref.read(toastProvider.notifier).show('Changes saved');
      context.pop();
    } on AppError catch (e) {
      if (!mounted) return;
      // A completed task rejects every other field (§3A) — that message is the
      // only thing explaining why the save did nothing, so it must be shown.
      setState(() => _saving = false);
      ref.read(apiServiceProvider).handled(e);
      ref.read(toastProvider.notifier).showError(projectTaskErrorMessage(e, ProjectTaskAction.update));
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    // The **full** record: the list row it used to read is the 19-field slim
    // projection, which carries no description, expected start, department or
    // dependency edges.
    final task = ref.watch(opsTaskDetailOrListProvider(id));
    final projects = ref.watch(allProjectsProvider);
    ref.watch(opsTaskStatusOptionsProvider);

    if (task == null) {
      return OpsEditScaffold(
        title: 'Edit task',
        subtitle: '—',
        onClose: () => context.pop(),
        onSave: () => context.pop(),
        children: const [Center(child: Text('Task not found'))],
      );
    }

    // Prefill on the first record, then again when the detail lands — the first
    // build usually gets the slim list row. An edit already in progress is
    // never overwritten.
    final hasDetail = ref.watch(opsTaskDetailProvider(id)).valueOrNull != null;
    if (!_init || (hasDetail && !_fromDetail && !_dirty)) {
      _init = true;
      _fromDetail = hasDetail;
      _prefill(task);
    }

    final projName = (_projId ?? '').isEmpty
        ? 'No project (standalone)'
        : projects.where((p) => p.id == _projId).map((p) => p.name).firstOrNull ?? task.projectName;

    // The project's real lanes, same source as the create form. This used to
    // gather group *names* off loaded tasks, and `task_group` wants a UUID.
    final groupCatalog =
        (_projId ?? '').isEmpty ? const <CatalogOption>[] : ref.watch(taskGroupsProvider(_projId!)).valueOrNull ?? const [];
    final groupName = _groupId.isEmpty
        ? 'No group'
        : groupCatalog.where((g) => g.id == _groupId).map((g) => g.name).firstOrNull ?? _group;

    // The org's own task types, keyed by `task_type_id`. The picker offered a
    // hardcoded Task / Approval / Site visit / Meeting, none of which was a
    // real type.
    final typeCatalog = ref.watch(opsTaskTypeOptionsProvider);
    final typeName = typeCatalog.where((t) => t.id == _ttype).map((t) => t.name).firstOrNull ?? '';

    final statusChips = _statusChips;
    final statusKey = _statusKey;

    return OpsEditScaffold(
      title: 'Edit task',
      subtitle: _code.isEmpty
          // `task_code` is null for a standalone task, and an empty code
          // would leave a dangling separator.
          ? 'Changes apply on save'
          : '$_code · changes apply on save',
      onClose: () => handleEditClose(context, dirty: _dirty),
      onSave: _save,
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
            final v = await showOpsOptionPicker(context: context, title: 'Select project', options: [
              (value: '', label: 'No project (standalone)'),
              for (final p in projects) (value: p.id, label: p.name),
            ], currentValue: _projId ?? '');
            // Webapp: a project change always drops the group (groups belong
            // to a project).
            if (v != null && v != (_projId ?? '')) setState(() { _projId = v.isEmpty ? null : v; _groupId = ''; _dirtied(); });
          },
        ),
        SizedBox(height: 14.h),
        Row(
          children: [
            Expanded(
              child: OpsPickerField(
                label: 'Task group',
                value: groupName,
                onTap: () async {
                  // A standalone task has no groups to pick from.
                  if ((_projId ?? '').isEmpty) return;
                  final v = await showOpsOptionPicker(
                    context: context,
                    title: 'Task group',
                    options: [
                      (value: '', label: 'No group'),
                      for (final g in groupCatalog) (value: g.id, label: g.name),
                    ],
                    currentValue: _groupId,
                  );
                  if (v != null) setState(() { _groupId = v; _dirtied(); });
                },
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: OpsPickerField(
                label: 'Type',
                value: typeName.isEmpty ? '—' : typeName,
                onTap: () async {
                  final v = await showOpsOptionPicker(
                    context: context,
                    title: 'Type',
                    // "—" clears the type (sent as null).
                    options: [(value: '', label: '—'), for (final t in typeCatalog) (value: t.id, label: t.name)],
                    currentValue: _ttype,
                  );
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
          for (final (key, label, tone) in statusChips)
            OpsFormChip(label: label, selected: statusKey == key, tone: tone, onTap: () => setState(() { _status = key; _dirtied(); })),
        ]),
        SizedBox(height: 14.h),
        _label('Priority'),
        SizedBox(height: 7.h),
        Wrap(spacing: 8.w, runSpacing: 8.h, children: [
          for (final p in const ['Urgent', 'High', 'Medium', 'Low'])
            OpsFormChip(label: p, selected: _pri == p, tone: StatusMeta$.projectPriority[p], onTap: () => setState(() { _pri = p; _dirtied(); })),
        ]),
        SizedBox(height: 14.h),
        _label('Assignee'),
        SizedBox(height: 7.h),
        Wrap(spacing: 8.w, runSpacing: 8.h, children: [
          for (final r in ref.watch(rosterProvider))
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
        // Free text server-side (no Department model), as on the webapp.
        AppTextField(label: 'Department', controller: _dept, hint: 'e.g. Design', onChanged: (_) => _dirtied()),
        SizedBox(height: 14.h),
        _label('Color tag'),
        SizedBox(height: 7.h),
        _colorRow(),
        SizedBox(height: 14.h),
        _milestoneToggle(),
        const OpsSectionLabel('Progress'),
        if (!_hasSubs) _progressSlider() else _calculatedProgress(),
      ],
    );
  }

  Widget _colorRow() {
    Widget dot(String hex) {
      final on = _color == hex;
      final fill = hex.isEmpty
          ? AppColors.white
          : Color(int.parse('FF${hex.substring(1)}', radix: 16));
      return GestureDetector(
        onTap: () => setState(() { _color = hex; _dirtied(); }),
        child: Container(
          width: 30.w,
          height: 30.w,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: on ? AppColors.navy : AppColors.borderCardSoft, width: on ? 2.5 : 1.2),
          ),
          child: hex.isEmpty ? Icon(PhosphorIconsBold.prohibit, size: 14.sp, color: AppColors.textPlaceholder) : null,
        ),
      );
    }

    return Wrap(spacing: 9.w, runSpacing: 9.h, children: [dot(''), for (final h in _swatches) dot(h)]);
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
        final d = await showDatePicker(context: context, initialDate: value ?? kFilterToday, firstDate: DateTime(2024), lastDate: DateTime(2030));
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
