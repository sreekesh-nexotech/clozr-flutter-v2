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
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
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

const _taskTypes = ['Task', 'Call', 'Meeting', 'Email', 'Deadline'];

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
  String _assignee = 'me';
  bool _showErrors = false;

  @override
  void dispose() {
    for (final c in [_title, _desc, _due, _dueTime]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _titleOk => _title.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() => _showErrors = true);
    if (!_titleOk) {
      widget.ref.read(toastProvider.notifier).show('Enter a task title');
      return;
    }
    final lead = widget.lead;
    if (ApiConfig.apiEnabled) {
      try {
        await widget.ref.read(crmTasksRepositoryProvider).createTask({
          'title': _title.text.trim(),
          'task_type': _type,
          'due_date': _due.text.trim(),
          'due_time': _dueTime.text.trim(),
          'description': _desc.text.trim(),
          if (lead != null) 'related_to': 'lead',
          if (lead != null) 'related_to_id': lead.id,
        });
      } on AppError catch (e) {
        widget.ref.read(toastProvider.notifier).show(e.message);
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
      type: _type,
      leadId: lead?.id,
      status: _status,
      priority: _priority,
      assignee: _assignee,
      due: dueLabel,
      dueNote: '',
    );
    final drafts = widget.ref.read(crmTaskDraftsProvider);
    widget.ref.read(crmTaskDraftsProvider.notifier).state = [task, ...drafts];
    widget.ref.read(toastProvider.notifier).show('Task added');
    Navigator.of(context).pop();
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'New task', onClose: () => Navigator.of(context).pop()),
        Flexible(
          child: SingleChildScrollView(
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
                      SelectChip(label: t, selected: _type == t, onTap: () => setState(() => _type = t)),
                  ],
                ),
                SizedBox(height: 16.h),
                const SheetFieldLabel('Priority'),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    for (final p in const ['High', 'Medium', 'Low'])
                      SelectChip(
                        label: p,
                        selected: _priority == p,
                        dot: StatusMeta$.priorityTone[p]!.fg,
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
                      child: AppTextField(label: 'Due date', controller: _due, hint: '24 Jun 2026'),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      flex: 2,
                      child: AppTextField(label: 'Due time', controller: _dueTime, hint: '10:00'),
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
        SheetSubmitBar(label: 'Add task', icon: PhosphorIconsBold.plus, onTap: _submit),
      ],
    );
  }
}
