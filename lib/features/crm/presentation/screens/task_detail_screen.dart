import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/api/roster.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/models/note.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/notes_thread.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../../../core/utils/relative_time.dart';
import '../../application/providers/attachments_providers.dart';
import '../../application/providers/audit_log_providers.dart';
import '../../application/providers/crm_notes_providers.dart';
import '../../application/record_rows.dart';
import '../../application/providers/crm_tasks_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../../domain/entities/audit_entry.dart';
import '../../domain/entities/crm_task.dart';
import '../../domain/entities/lead_file.dart';
import '../components/crm_async.dart';
import '../components/crm_detail_parts.dart';
import 'crm_status_sheet.dart';

/// Task type → Phosphor glyph (mirrors the prototype's TASKTYPES map).
const _taskTypeIcons = <String, IconData>{
  'Task': PhosphorIconsRegular.checkSquare,
  'Call': PhosphorIconsRegular.phone,
  'Email': PhosphorIconsRegular.envelopeSimple,
  'Meeting': PhosphorIconsRegular.usersThree,
  'Deadline': PhosphorIconsRegular.flag,
  'Site visit': PhosphorIconsRegular.mapPin,
  'Quote': PhosphorIconsRegular.fileText,
  'Admin': PhosphorIconsRegular.clipboardText,
  'Follow-up': PhosphorIconsRegular.arrowUUpRight,
};

class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({super.key});

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  int _tab = 0; // 0 = Description, 1 = Files
  bool _uploading = false;
  final _notesKey = GlobalKey<NotesThreadState>();

  /// Scrolls the notes card into view and focuses the composer (#13).
  void _focusNotes() {
    final ctx = _notesKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 300), alignment: 0.05, curve: Curves.easeOut);
    }
    _notesKey.currentState?.focusComposer();
  }

  /// Records a status change for an existing task, applying an optimistic
  /// override so the detail + list reflect it immediately. In API mode the write
  /// is awaited: on failure the override is rolled back to its prior value and
  /// the error is surfaced; [successMessage] is toasted only after the write
  /// lands. Mock mode is unchanged (optimistic + success toast).
  Future<void> _setStatus(String id, String status, String successMessage) async {
    final prev = ref.read(crmTaskStatusOverrideProvider);
    ref.read(crmTaskStatusOverrideProvider.notifier).state = {...prev, id: status};
    if (ApiConfig.apiEnabled) {
      try {
        await ref.read(crmTasksRepositoryProvider).setTaskStatusByKey(id, status);
      } on AppError catch (e) {
        final rolled = {...ref.read(crmTaskStatusOverrideProvider)};
        if (prev.containsKey(id)) {
          rolled[id] = prev[id]!;
        } else {
          rolled.remove(id);
        }
        ref.read(crmTaskStatusOverrideProvider.notifier).state = rolled;
        ref.read(toastProvider.notifier).show(e.message);
        return;
      }
      // The info panel reads the raw record, so the optimistic override alone
      // would leave its Status row showing the old value until a refetch. This
      // is what made a status change look like it had not applied.
      ref.invalidate(taskRowProvider(id));
      ref.invalidate(crmTasksProvider);
    }
    ref.read(toastProvider.notifier).show(successMessage);
  }

  /// Copies a task: the same record, re-posted as a new one.
  ///
  /// Built from the **record**, not the mapped entity, so fields the entity
  /// drops (description, due time, duration, team) come along too.
  Future<void> _duplicate(CrmTask task) async {
    final toast = ref.read(toastProvider.notifier);
    final row = ref.read(taskRowProvider(task.id)).valueOrNull;
    if (row == null) {
      toast.show('Still loading this task — try again in a moment');
      return;
    }
    final related = row['related_to'];
    try {
      await ref.read(crmTasksRepositoryProvider).createTask({
        'title': '${row['title'] ?? task.title} (copy)',
        'task_type': row['task_type'] ?? task.type,
        'description': row['description'] ?? '',
        'due_date': row['due_date'] ?? '',
        'due_time': row['due_time'] ?? '',
        // Carry the link so the copy sits beside the original.
        if (related is Map && related['model'] != null) 'related_to': related['model'],
        if (related is Map && related['id'] != null) 'related_to_id': related['id'],
      });
    } on AppError catch (e) {
      toast.show(e.message);
      return;
    }
    ref.invalidate(crmTasksProvider);
    ref.invalidate(leadTasksProvider);
    toast.show('Task duplicated');
  }

  /// Deleting is irreversible, so it asks first.
  Future<void> _confirmDelete(CrmTask task) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('"${task.titleClean}" will be removed. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final toast = ref.read(toastProvider.notifier);
    try {
      await ref.read(crmTasksRepositoryProvider).deleteTask(task.id);
    } on AppError catch (e) {
      toast.show(e.message);
      return;
    }
    ref.invalidate(crmTasksProvider);
    ref.invalidate(leadTasksProvider);
    toast.show('Task deleted');
    if (mounted) context.pop();
  }

  void _openTaskMenu(CrmTask task, bool done) {
    showActionMenu(
      context,
      actions: [
        MenuAction(
          icon: PhosphorIconsRegular.pencilSimple,
          label: 'Edit task',
          enabled: !done,
          sublabel: done ? 'Task is done' : null,
          onTap: () => context.push('${Routes.editCrmTask}?id=${task.id}'),
        ),
        MenuAction(
            icon: PhosphorIconsRegular.copy,
            label: 'Duplicate task',
            onTap: () => _duplicate(task)),
        MenuAction(icon: PhosphorIconsRegular.notePencil, label: 'Add note', onTap: _focusNotes),
        MenuAction(
            icon: PhosphorIconsRegular.trash,
            label: 'Delete task',
            destructive: true,
            onTap: () => _confirmDelete(task)),
      ],
    );
  }

  /// Wraps a loading / error / not-found state under the section app bar so the
  /// back control stays available in every state.
  Widget _stateScaffold(Widget child) => Container(
        color: AppColors.bgDetail,
        child: Column(
          children: [
            DetailAppBar(section: 'Task', onBack: () => context.pop()),
            Expanded(child: child),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final async = ref.watch(crmTasksProvider);
    return async.when(
      loading: () => _stateScaffold(const DetailSkeleton()),
      error: (e, _) => _stateScaffold(
        ErrorState.forError(crmAppError(e), onRetry: () => ref.invalidate(crmTasksProvider)),
      ),
      data: (_) => _buildTask(context, id),
    );
  }

  Widget _buildTask(BuildContext context, String id) {
    final task = ref.watch(crmTaskByIdProvider(id));
    if (task == null) {
      return _stateScaffold(const EmptyState(
        icon: PhosphorIconsRegular.checkSquare,
        title: 'Task not found',
        body: 'This task may have been removed or you no longer have access to it.',
      ));
    }

    final meta = StatusMeta$.task[task.status] ?? StatusMeta$.task['todo']!;
    final assignee = MockUsers.of(task.assignee);
    final leads = ref.watch(leadsProvider).valueOrNull ?? const [];
    final lead = task.leadId == null ? null : leads.where((l) => l.id == task.leadId).firstOrNull;
    final done = task.status == 'done';

    // Notes thread (#13) — tasks start with an empty thread; the shared
    // composer stays usable regardless of the task's status.
    final notesSeed = CrmNotesSeed('TASK-${task.id}', () => <NoteEntry>[], apiModel: 'task');
    final notes = ref.watch(crmNotesProvider(notesSeed));

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: 'Task',
            name: task.title,
            onBack: () => context.pop(),
            trailing: DetailIconAction(
              icon: PhosphorIconsBold.dotsThreeVertical,
              onTap: () => _openTaskMenu(task, done),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
              children: [
                _titleCard(task, meta),
                if (lead != null) ...[SizedBox(height: 14.h), _relatedCard(lead)],
                SizedBox(height: 14.h),
                _infoCard(task, assignee),
                SizedBox(height: 14.h),
                _descFilesCard(task, lead),
                SizedBox(height: 14.h),
                NotesThread(
                  author: ref.watch(noteAuthorProvider),
                  key: _notesKey,
                  notes: notes,
                  onAddNote: (body, atts) =>
                      ref.read(crmNotesProvider(notesSeed).notifier).addNote(body, atts, ref.read(noteAuthorProvider)),
                  onAddReply: (noteId, body) =>
                      ref.read(crmNotesProvider(notesSeed).notifier).addReply(noteId, body, ref.read(noteAuthorProvider)),
                ),
                SizedBox(height: 14.h),
                _activityCard(task, meta, assignee),
              ],
            ),
          ),
          _bottomBar(task, done),
        ],
      ),
    );
  }

  Widget _titleCard(CrmTask task, StatusMeta meta) {
    final overdue = task.isOverdue;
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.all(18.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46.w,
                height: 46.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(13.r)),
                child: Icon(_taskTypeIcons[task.type] ?? PhosphorIconsRegular.checkSquare, size: 22.sp, color: AppColors.navy),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.title, style: AppText.custom(size: 19, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3, height: 1.3)),
                    SizedBox(height: 3.h),
                    Text('${task.id} · ${task.type} task', style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    SizedBox(height: 5.h),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('Due ${task.due}', style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.textSecondary)),
                        if (task.dueNote.isNotEmpty) ...[
                          SizedBox(width: 8.w),
                          Text(task.dueNote,
                              style: AppText.custom(size: 12, weight: FontWeight.w700, color: overdue ? AppColors.error : AppColors.warningDeep)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 14)),
          Row(
            children: [
              _statusChip(meta, () => _openStatusSheet(task, meta)),
              SizedBox(width: 9.w),
              PriorityPill(priority: task.priority),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(StatusMeta meta, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(color: meta.color.withOpacity(0.09), borderRadius: BorderRadius.circular(9.r)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8.w, height: 8.w, decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle)),
            SizedBox(width: 7.w),
            Text(meta.label, style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: meta.color)),
            SizedBox(width: 6.w),
            Icon(PhosphorIconsBold.caretDown, size: 10.sp, color: AppColors.textMuted2),
          ],
        ),
      ),
    );
  }

  void _openStatusSheet(CrmTask task, StatusMeta meta) {
    showCrmStatusSheet(
      context: context,
      ref: ref,
      title: 'Update task status',
      options: const ['todo', 'inprogress', 'blocked', 'done'],
      meta: StatusMeta$.task,
      current: task.status,
      onSelect: (k) => _setStatus(task.id, k, 'Status set to ${StatusMeta$.task[k]!.label}'),
    );
  }

  Widget _relatedCard(dynamic lead) {
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 15.h),
      onTap: () => context.push('${Routes.leadDetail}?id=${lead.id}'),
      child: Row(
        children: [
          Container(
            width: 42.w,
            height: 42.w,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Color(0xFFEEF1F4), shape: BoxShape.circle),
            child: Text(lead.initials, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.navy)),
          ),
          SizedBox(width: 13.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RELATED TO', style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.5)),
                SizedBox(height: 2.h),
                Text(lead.company ?? lead.name, style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 1.h),
                Text('Lead · #${lead.id}', style: AppText.caption()),
              ],
            ),
          ),
          Icon(PhosphorIconsBold.caretRight, size: 15.sp, color: AppColors.textPlaceholder),
        ],
      ),
    );
  }

  /// The icon for a schema column, by field name. Anything unrecognised — an
  /// org's custom field, or a built-in we have no icon for — gets the neutral
  /// one rather than being dropped.
  static IconData _rowIcon(String name) => switch (name) {
        'task_type' => PhosphorIconsRegular.tag,
        'priority' => PhosphorIconsRegular.flag,
        'due_date' || 'due_time' => PhosphorIconsRegular.calendarBlank,
        'duration' => PhosphorIconsRegular.timer,
        'assigned_to' || 'assignees' => PhosphorIconsRegular.userCircle,
        'assigned_team' => PhosphorIconsRegular.usersThree,
        'related_to' => PhosphorIconsRegular.link,
        'description' => PhosphorIconsRegular.textAlignLeft,
        'status' => PhosphorIconsRegular.circleDashed,
        _ => PhosphorIconsRegular.info,
      };

  /// The built-in rows, used when the org's detail layout has not loaded (and
  /// in mock mode) — the panel as it was before the layout became configurable.
  List<(IconData, String, String)> _fallbackRows(CrmTask task, dynamic assignee) => [
        (PhosphorIconsRegular.tag, 'Type', task.type),
        (PhosphorIconsRegular.flag, 'Priority', task.priority),
        (PhosphorIconsRegular.calendarBlank, 'Due date', task.due),
        (PhosphorIconsRegular.userCircle, 'Assigned to', assignee.name),
        (PhosphorIconsRegular.hash, 'Task ID', task.id),
      ];

  Widget _infoCard(CrmTask task, dynamic assignee) {
    // The org's own layout over the raw record. Both must be present: the
    // schema says which rows, the record supplies their values.
    final schema = ref.watch(taskDetailSchemaProvider);
    final row = ref.watch(taskRowProvider(task.id)).valueOrNull;
    final rows = (schema.isEmpty || row == null)
        ? _fallbackRows(task, assignee)
        : [
            // `title` is the page header, so it is never repeated as a row.
            for (final r in recordRows(row, schema, skip: const {'title', 'description'}))
              (_rowIcon(r.name), r.label, r.value),
          ];
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.all(18.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Task information', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 6.h),
          for (int i = 0; i < rows.length; i++)
            Container(
              padding: EdgeInsets.symmetric(vertical: 9.h),
              decoration: BoxDecoration(
                border: i == rows.length - 1 ? null : const Border(bottom: BorderSide(color: Color(0xFFF3F4F5))),
              ),
              child: Row(
                children: [
                  SizedBox(width: 20.w, child: Icon(rows[i].$1, size: 17.sp, color: AppColors.textPlaceholder)),
                  SizedBox(width: 12.w),
                  SizedBox(width: 92.w, child: Text(rows[i].$2, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted))),
                  Expanded(
                    child: Text(rows[i].$3, textAlign: TextAlign.right, style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _descFilesCard(CrmTask task, dynamic lead) {
    // The task's own description, from the record. This used to be a sentence
    // assembled from the task's other fields — which read as a description the
    // user had written, and was not.
    final row = ref.watch(taskRowProvider(task.id)).valueOrNull;
    final written = (row?['description'] ?? '').toString().trim();
    final desc = written.isNotEmpty ? written : 'No description added yet.';
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailUnderlineTabs(labels: const ['Description', 'Files'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
          if (_tab == 0)
            Padding(
              padding: EdgeInsets.only(top: 12.h),
              child: Text(desc, style: AppText.custom(size: 14, weight: FontWeight.w500, color: AppColors.textLabelAlt).copyWith(height: 1.6)),
            )
          else
            _filesTab(task),
        ],
      ),
    );
  }

  /// The task's attachments, from the shared polymorphic table.
  Widget _filesTab(CrmTask task) {
    final files = ref.watch(taskFilesProvider(task.id)).valueOrNull ?? const <LeadFile>[];
    return Padding(
      padding: EdgeInsets.only(top: 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (files.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 10.h),
              child: Text('No files attached yet.',
                  style: AppText.custom(
                      size: 13.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
            )
          else
            for (final f in files)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 7.h),
                child: Row(
                  children: [
                    Icon(PhosphorIconsRegular.paperclip, size: 15.sp, color: AppColors.textPlaceholder),
                    SizedBox(width: 9.w),
                    Expanded(
                      child: Text(f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(
                              size: 13.5, weight: FontWeight.w600, color: AppColors.textPrimary)),
                    ),
                  ],
                ),
              ),
          SizedBox(height: 10.h),
          GestureDetector(
            onTap: _uploading ? null : () => _uploadFiles(task),
            child: Container(
              height: 40.h,
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: AppColors.borderInput)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsRegular.uploadSimple, size: 15.sp, color: AppColors.navy),
                  SizedBox(width: 7.w),
                  Text(_uploading ? 'Uploading…' : 'Upload file', style: AppText.bodyStrong()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Picks files off the device and uploads each against this task.
  Future<void> _uploadFiles(CrmTask task) async {
    if (_uploading) return;
    final toast = ref.read(toastProvider.notifier);

    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false, // paths only — a large file should not sit in memory
    );
    if (picked == null || !mounted) return; // cancelled

    final files = [
      for (final f in picked.files)
        if (f.path != null) (path: f.path!, name: f.name),
    ];
    if (files.isEmpty) return;

    if (!ApiConfig.apiEnabled) {
      toast.show('Files upload once the app is connected to the API.');
      return;
    }

    setState(() => _uploading = true);
    final repo = ref.read(attachmentsRepositoryProvider);
    var stored = 0;
    String? failure;
    for (final f in files) {
      try {
        final saved = await repo.uploadFile(
          relatedTo: 'task',
          relatedToId: task.id,
          path: f.path,
          name: f.name,
        );
        if (saved != null) stored++;
      } on AppError catch (e) {
        failure = e.message;
        break;
      }
    }
    if (!mounted) return;
    setState(() => _uploading = false);

    if (stored > 0) ref.invalidate(taskFilesProvider(task.id));
    if (failure != null) {
      // Say what did land before what didn't, so a partial batch is not read
      // as a total failure.
      toast.show(stored == 0 ? failure : '$stored uploaded · $failure');
    } else {
      toast.show(stored == 1 ? 'File uploaded' : '$stored files uploaded');
    }
  }

  /// The row styling for one kind of audit event.
  static ActivityItem _activityRow(AuditEntry e) {
    final (icon, tone, bg) = switch (e.kind) {
      AuditEventKind.created =>
        (PhosphorIconsRegular.plusCircle, AppColors.textMuted2, AppColors.bgChipGrey),
      AuditEventKind.statusChanged =>
        (PhosphorIconsRegular.arrowsClockwise, AppColors.blueBright, AppColors.tintBlue),
      AuditEventKind.noteAdded =>
        (PhosphorIconsRegular.note, AppColors.success, AppColors.tintGreen),
      AuditEventKind.childAdded =>
        (PhosphorIconsRegular.paperclip, AppColors.warningDeep, AppColors.tintAmber),
      AuditEventKind.deleted =>
        (PhosphorIconsRegular.trash, AppColors.error, AppColors.bgChipGrey),
      _ => (PhosphorIconsRegular.pencilSimple, AppColors.textMuted2, AppColors.bgChipGrey),
    };
    return ActivityItem(
        icon: icon, tone: tone, bg: bg, title: e.title, sub: e.subtitle, time: relativeTime(e.at));
  }

  Widget _activityCard(CrmTask task, StatusMeta meta, dynamic assignee) {
    // The task's real audit trail. It refetches off the API write tick, so an
    // edit, a status change, a note or an upload all land here without this
    // card being told about each one.
    final entries = ref.watch(taskActivityLogProvider(task.id)).valueOrNull ?? const [];
    if (entries.isEmpty) return const SizedBox.shrink();
    final items = [for (final e in entries) _activityRow(e)];
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 6.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.pulse, size: 16.sp, color: AppColors.textLabelAlt),
              SizedBox(width: 7.w),
              Text('Activity', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          SizedBox(height: 12.h),
          ActivityTimeline(items: items),
        ],
      ),
    );
  }

  Widget _bottomBar(CrmTask task, bool done) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 22.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: Row(
        children: [
          // The pencil beside Mark complete opens the same edit screen as the
          // menu's "Edit task" — it read as an edit affordance either way.
          GestureDetector(
            onTap: () => context.push('${Routes.editCrmTask}?id=${task.id}'),
            child: Container(
              width: 48.w,
              height: 48.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12.r), border: Border.all(color: AppColors.borderInput)),
              child: Icon(PhosphorIconsRegular.pencilSimple, size: 21.sp, color: AppColors.navy),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: GestureDetector(
              onTap: () => _setStatus(task.id, done ? 'todo' : 'done', done ? 'Task reopened' : 'Task marked complete'),
              child: Container(
                height: 48.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? AppColors.tintGreen : AppColors.navy,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(done ? PhosphorIconsFill.checkCircle : PhosphorIconsBold.check, size: 17.sp, color: done ? AppColors.success : AppColors.white),
                    SizedBox(width: 8.w),
                    Text(done ? 'Completed · reopen' : 'Mark complete',
                        style: AppText.custom(size: 15, weight: FontWeight.w700, color: done ? AppColors.success : AppColors.white)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
