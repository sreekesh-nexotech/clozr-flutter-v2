import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/api/status_keys.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/filters/tasks_filter_spec.dart';
import '../../application/providers/crm_catalog_providers.dart';
import '../../application/providers/crm_tasks_providers.dart';
import '../../domain/entities/crm_task.dart';
import '../../domain/entities/lead.dart';
import 'add_sheet_kit.dart';

/// Add task — a focused-but-faithful port of the prototype's `addTask` sheet. On
/// submit the new task is prepended to [crmTaskDraftsProvider] so it appears
/// immediately in the list, then a toast confirms.
///
/// Pass [lead] when opening from a lead's Tasks tab: the sheet then shows the
/// link, and the created task carries `related_to=lead` so it comes back in
/// that lead's scoped fetch instead of floating unattached.
Future<void> showAddTaskSheet(BuildContext context, WidgetRef ref, {Lead? lead}) {
  return showClozrSheet<void>(
    context: context,
    builder: (_) => _AddTaskSheet(ref: ref, lead: lead),
  );
}

class _AddTaskSheet extends StatefulWidget {
  const _AddTaskSheet({required this.ref, this.lead});
  final WidgetRef ref;

  /// The lead this task is being raised against, when opened from one.
  final Lead? lead;

  @override
  State<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<_AddTaskSheet> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _due = TextEditingController();
  final _dueTime = TextEditingController();
  String _status = 'todo';
  String _type = 'Call';
  String _priority = 'Medium';

  /// The server's task-type choice set, falling back to the built-in list
  /// before it loads. `task_type` is submitted as the value, so offering one
  /// the server does not accept is rejected on save.
  ///
  /// Read rather than watched so it is valid from the submit callback; build
  /// watches the catalogs to keep the chips fresh.
  List<String> get _taskTypes {
    final catalog = widget.ref.read(taskTypeOptionsProvider);
    return catalog.isNotEmpty ? [for (final t in catalog) t.id] : kBuiltinTaskTypes;
  }

  /// The org's priorities, folded to the display vocabulary the rest of the app
  /// uses — an org spelling them "critical"/"high" still shows Urgent/High.
  List<String> get _priorities {
    final catalog = widget.ref.read(taskPriorityOptionsProvider);
    return catalog.isNotEmpty
        ? {for (final p in catalog) priorityKey(p.name)}.toList()
        : kBuiltinTaskPriorities;
  }

  /// The chosen values, corrected to something this org offers — the defaults
  /// are guesses until the catalogs say otherwise.
  String get _selectedPriority {
    final list = _priorities;
    return list.isEmpty || list.contains(_priority) ? _priority : list.first;
  }

  String get _selectedType {
    final list = _taskTypes;
    return list.isEmpty || list.contains(_type) ? _type : list.first;
  }

  String _assignee = 'me';
  bool _showErrors = false;

  /// True while the create is in flight, so a second tap cannot post again.
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_title, _desc, _due, _dueTime]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _titleOk => _title.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _showErrors = true);
    if (!_titleOk) {
      widget.ref.read(toastProvider.notifier).show('Enter a task title');
      return;
    }
    final lead = widget.lead;
    if (ApiConfig.apiEnabled) {
      setState(() => _saving = true);
      try {
        await widget.ref.read(crmTasksRepositoryProvider).createTask({
          'title': _title.text.trim(),
          'task_type': _selectedType,
          'due_date': _due.text.trim(),
          'due_time': _dueTime.text.trim(),
          'description': _desc.text.trim(),
          if (lead != null) 'related_to': 'lead',
          if (lead != null) 'related_to_id': lead.id,
        });
      } on AppError catch (e) {
        // Refused — let the user correct it and try again.
        if (mounted) setState(() => _saving = false);
        widget.ref.read(toastProvider.notifier).showError(e.message);
        return;
      }
      widget.ref.invalidate(crmTasksProvider);
      // Every lead's Tasks tab reads its own scoped fetch, so the org-wide
      // list alone going stale is not enough to refresh them.
      widget.ref.invalidate(leadTasksProvider);
      widget.ref.read(toastProvider.notifier).show('Task added');
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final due = _due.text.trim();
    final dueTime = _dueTime.text.trim();
    final dueLabel = due.isEmpty
        ? 'No due date'
        : (dueTime.isEmpty ? due : '$due · $dueTime');
    final task = CrmTask(
      id: genId('TL-'),
      title: _title.text.trim(),
      type: _selectedType,
      leadId: lead?.id,
      status: _status,
      priority: _selectedPriority,
      assignee: _assignee,
      due: dueLabel,
      dueNote: '',
    );
    final drafts = widget.ref.read(crmTaskDraftsProvider);
    widget.ref.read(crmTaskDraftsProvider.notifier).state = [task, ...drafts];
    widget.ref.read(toastProvider.notifier).show('Task added');
    Navigator.of(context).pop();
  }

  Future<void> _pickDueDate() async {
    final picked = await pickSheetDate(context, _due.text);
    if (picked == null || !mounted) return;
    setState(() => _due.text = sheetDateLabel(picked));
  }

  Future<void> _pickDueTime() async {
    final picked = await pickSheetTime(context, _dueTime.text);
    if (picked == null || !mounted) return;
    setState(() => _dueTime.text = sheetTimeLabel(picked));
  }

  void _pickAssignee() {
    final roster = widget.ref.read(rosterProvider);
    showClozrSheet<void>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: 'Assign to', onClose: () => Navigator.of(ctx).pop()),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(14.w, 4.h, 14.w, 28.h),
              children: [
                for (final r in roster)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() => _assignee = r.id);
                      Navigator.of(ctx).pop();
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 6.w),
                      child: Row(
                        children: [
                          Container(
                            width: 38.w,
                            height: 38.w,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(11.r)),
                            child: Text(r.initials,
                                style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.navy)),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.name, style: AppText.bodyStrong()),
                                SizedBox(height: 1.h),
                                Text(r.role, style: AppText.caption()),
                              ],
                            ),
                          ),
                          if (_assignee == r.id)
                            Icon(PhosphorIconsBold.check, size: 19.sp, color: AppColors.success),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watched here so the chips swap from the built-in lists to the org's own
    // the moment the catalogs resolve, even with the sheet already open.
    widget.ref.watch(taskTypeOptionsProvider);
    widget.ref.watch(taskPriorityOptionsProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'New task', onClose: () => Navigator.of(context).pop()),
        Flexible(
          child: SingleChildScrollView(
            // Title and Description sit above the Status / Type / Priority
            // chips, so typing hides the rest of the form; dragging the sheet
            // is how you get back to it.
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 12.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.lead != null) ...[
                  LinkedLeadField(lead: widget.lead!),
                  SizedBox(height: 14.h),
                ],
                AppTextField(
                  label: 'Task title',
                  required: true,
                  controller: _title,
                  hint: 'e.g. Prepare BOQ & quotation',
                  errorText: _showErrors && !_titleOk ? 'Enter a task title' : null,
                  onChanged: (_) => setState(() {}),
                ),
                SizedBox(height: 14.h),
                AppTextField(
                    label: 'Description',
                    controller: _desc,
                    hint: 'Optional details or notes about the task…',
                    multiline: true),
                SizedBox(height: 16.h),
                const SheetFieldLabel('Status'),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    for (final k in StatusMeta$.task.keys)
                      SelectChip(
                        label: StatusMeta$.task[k]!.label,
                        selected: _status == k,
                        dot: StatusMeta$.task[k]!.color,
                        onTap: () => setState(() => _status = k),
                      ),
                  ],
                ),
                SizedBox(height: 16.h),
                const SheetFieldLabel('Type'),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    for (final t in _taskTypes)
                      SelectChip(label: t, selected: _selectedType == t, onTap: () => setState(() => _type = t)),
                  ],
                ),
                SizedBox(height: 16.h),
                const SheetFieldLabel('Priority'),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    for (final p in _priorities)
                      SelectChip(
                        label: p,
                        selected: _selectedPriority == p,
                        dot: StatusMeta$.priorityTone[p]?.fg,
                        onTap: () => setState(() => _priority = p),
                      ),
                  ],
                ),
                SizedBox(height: 16.h),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: AppTextField(
                        label: 'Due date',
                        readOnly: true,
                        onTap: _pickDueDate,
                        value: _due.text.isEmpty ? null : _due.text,
                        hint: '24 Jun 2026',
                        suffixIcon: PhosphorIconsRegular.calendarBlank,
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      flex: 2,
                      child: AppTextField(
                        label: 'Due time',
                        readOnly: true,
                        onTap: _pickDueTime,
                        value: _dueTime.text.isEmpty ? null : _dueTime.text,
                        hint: '10:00',
                        suffixIcon: PhosphorIconsRegular.clock,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14.h),
                AppTextField(
                  label: 'Assign to',
                  readOnly: true,
                  onTap: _pickAssignee,
                  value: MockUsers.of(_assignee).name,
                ),
              ],
            ),
          ),
        ),
        SheetSubmitBar(
            label: 'Add task',
            icon: PhosphorIconsBold.plus,
            busy: _saving,
            busyLabel: 'Adding…',
            onTap: _submit),
      ],
    );
  }
}
