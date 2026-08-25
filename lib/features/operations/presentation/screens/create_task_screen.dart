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
import '../../../crm/domain/entities/crm_catalog.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/ops_task_write_fields.dart';
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

  /// True once the `?project=` query param has been read, so a rebuild does not
  /// re-seed a project the user has since changed.
  bool _seededProject = false;
  /// The picked lane's `task_group_id` — empty string is the "No group" lane,
  /// which the API stores as a null FK.
  String _groupId = '';
  final Set<String> _assignees = {};
  bool _saving = false;
  /// The org's own status **name** once the catalog loads (a built-in key
  /// before that, and in mock mode).
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

  /// The status chips: the org's own statuses once
  /// `/projects/project-task-statuses/` has answered, the built-in vocabulary
  /// before that and in mock mode. `(key, label)` — the key is what a picked
  /// chip resolves to an id against.
  List<(String, String)> get _statusChips {
    final catalog = ref.watch(opsTaskStatusOptionsProvider);
    if (catalog.isEmpty) {
      return [for (final e in StatusMeta$.opsTask.entries) (e.key, e.value.label)];
    }
    return [for (final s in catalog) (s.name, s.name)];
  }

  /// The selected status, corrected for the catalog arriving after the form
  /// opened: the `'open'` default is a built-in key, and an org that renamed
  /// its first lane would otherwise show every chip unselected.
  String get _statusKey {
    final chips = _statusChips;
    if (chips.isEmpty) return _status;
    if (chips.any((c) => c.$1 == _status)) return _status;
    return chips.first.$1;
  }

  /// API mode: create remotely, refresh the list, toast + pop as before.
  /// Mock mode: exactly the previous local toast-and-pop behavior.
  ///
  /// `_projId` comes from the project dropdown: in API mode that list is the
  /// live projects whose ids are `project_id` UUIDs, so it is safe to send as
  /// the task's `project` FK (in mock mode it would be a `PRJ-24xx` seed id,
  /// but this branch never runs there).
  Future<void> _submit() async {
    // Without this a second tap during the round trip creates a second task.
    if (_saving) return;
    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show('Task created');
      context.pop();
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(opsTasksRepositoryProvider).createOpsTask(
            opsTaskWriteFields(
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
              statuses: ref.read(opsTaskStatusOptionsProvider),
            ),
          );
      if (!mounted) return;
      // The whole family: the list renders from `opsTasksScopedProvider` under
      // whatever filter query is active, so dropping only the unfiltered
      // `opsTasksProvider` would leave the new task invisible.
      ref.invalidate(opsTasksScopedProvider);
      // …and the unfiltered one too, which the ops dashboard reads.
      ref.invalidate(opsTasksProvider);
      ref.read(toastProvider.notifier).show('Task created');
      context.pop();
    } on AppError catch (e) {
      if (!mounted) return;
      // The form still holds everything typed, and a rejected date or subject
      // is meant to be corrected and resubmitted.
      setState(() => _saving = false);
      ref.read(toastProvider.notifier).showError(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Opened from a project's Tasks tab, which passes the project it belongs to
    // — the picker still offers every project, this only saves choosing the one
    // the user was already looking at.
    if (!_seededProject) {
      _seededProject = true;
      final preset = GoRouterState.of(context).uri.queryParameters['project'];
      if (preset != null && preset.isNotEmpty) _projId = preset;
    }
    final projects = ref.watch(allProjectsProvider);
    final projName = _projId == null ? '' : projects.where((p) => p.id == _projId).map((p) => p.name).firstOrNull ?? '';

    // The picked project's real lanes. Groups are per project, so this re-asks
    // whenever the project changes. It used to collect group *names* off the
    // loaded tasks and, when that came up empty, offer an invented
    // Design / Site works / Snagging — none of which resolved to a lane.
    final groupCatalog =
        _projId == null ? const <CatalogOption>[] : ref.watch(taskGroupsProvider(_projId!)).valueOrNull ?? const [];
    final groupName = _groupId.isEmpty
        ? 'No group'
        : groupCatalog.where((g) => g.id == _groupId).map((g) => g.name).firstOrNull ?? 'No group';

    final statusChips = _statusChips;
    final statusKey = _statusKey;

    return OpsFormScaffold(
      title: 'New Task',
      ctaLabel: 'Create Task',
      // The end-date field already flags "before start", but the CTA stayed
      // live, so the form would post a range the API rejects.
      ctaEnabled: _valid && !_saving && !_endErr,
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
            // Lanes belong to a project, so a previously-picked group is no
            // longer valid once the project changes.
            if (v != null) setState(() { _projId = v; _groupId = ''; });
          },
        ),
        SizedBox(height: 14.h),
        OpsPickerField(
          label: 'Task group',
          value: groupName,
          onTap: () async {
            final v = await showOpsOptionPicker(
              context: context,
              title: 'Task group',
              options: [
                (value: '', label: 'No group'),
                for (final g in groupCatalog) (value: g.id, label: g.name),
              ],
              currentValue: _groupId,
            );
            if (v != null) setState(() => _groupId = v);
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
            for (final (key, label) in statusChips)
              OpsFormChip(label: label, selected: statusKey == key, onTap: () => setState(() => _status = key)),
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
          initialDate: value ?? kFilterToday,
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
