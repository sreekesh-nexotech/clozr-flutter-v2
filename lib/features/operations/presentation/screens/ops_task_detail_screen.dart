import '../../../crm/presentation/components/closing_note.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../approvals/domain/entities/approval.dart';
import '../../../approvals/presentation/components/approval_parts.dart';
import '../../../approvals/presentation/components/approval_request_note.dart';
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
import '../../../crm/domain/entities/crm_catalog.dart';
import '../../application/providers/project_form_providers.dart';
import '../components/ops_hold_edit_row.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../../data/api/status_keys.dart';
import '../../../../data/api/user_directory.dart';
import '../../../crm/application/providers/crm_notes_providers.dart';
import '../../../crm/domain/entities/audit_entry.dart' hide AuditEntry;
import '../../../crm/domain/entities/audit_entry.dart' as crm_audit
    show AuditEntry;
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/file_name_dialog.dart';
import '../../../../core/utils/upload_rules.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/utils/attachment_link.dart';
import '../../../../core/network/network_providers.dart';
import '../../../crm/application/attachment_cascade.dart';
import '../../../crm/application/providers/attachments_providers.dart';
import '../../../crm/domain/entities/lead_file.dart';
import '../../../crm/infrastructure/data_sources/remote/attachments_remote_ds.dart';
import '../../../crm/presentation/components/due_date_change.dart';
import '../../application/ops_task_write_fields.dart';
import '../../application/project_task_error.dart';
import '../../application/project_write_fields.dart' show apiDate;
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/notes_thread.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../../auth/presentation/components/permission_guard.dart';
import '../../application/providers/ops_subtasks_providers.dart';
import '../../application/providers/ops_tasks_providers.dart';
import '../../application/providers/projects_providers.dart';
import '../../domain/entities/ops_task.dart';
import '../components/ops_detail_widgets.dart';
import '../components/ops_widgets.dart';

/// Ops task detail — summary, details, checkable subtasks, dependency chips,
/// notes and audit log. Status opens a picker sheet; subtasks drive progress.
class OpsTaskDetailScreen extends ConsumerStatefulWidget {
  const OpsTaskDetailScreen({super.key});

  @override
  ConsumerState<OpsTaskDetailScreen> createState() =>
      _OpsTaskDetailScreenState();
}

class _OpsTaskDetailScreenState extends ConsumerState<OpsTaskDetailScreen> {
  /// Local override of the folded status key — what drives the pill colour and
  /// the completed-lock. [_statusName] is the org's own name for the same
  /// choice, which is what the picker and the write need.
  String? _status;
  String? _statusName;
  List<String>? _waitingOn;
  final _subCtrl = TextEditingController();

  // Subtask quick-add extras (webapp parity C13): due date, time, assignee.
  DateTime? _subDate;
  TimeOfDay? _subTime;
  String? _subAssignee;
  String? _subAssigneeName;
  final _notesKey = GlobalKey<NotesThreadState>();

  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    // Notes load fresh on open — the shared thread provider outlives a
    // sign-out, and would otherwise show the previous session's copy.
    // After the first frame: a provider cannot change while the tree builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(crmNotesProvider);
    });
  }

  @override
  void dispose() {
    _subCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final tasksAsync = ref.watch(opsTasksProvider);
    final task = ref.watch(opsTaskDetailOrListProvider(id));
    final allTasks = ref.watch(opsTasksListProvider);
    final projects = ref.watch(allProjectsProvider);
    // Watched, not read on demand: the status sheet needs the org's catalog,
    // and nothing else on this screen would ever have started that fetch.
    ref.watch(opsTaskStatusCatalogProvider);

    // Gate on **this task's** record, not on the whole task list. The list is a
    // multi-page walk, so waiting on it meant one task's page could not paint
    // until every task in the org had downloaded. The list is still watched —
    // it just no longer blocks.
    //
    // A failed fetch of the record itself (offline, 403, 404) shows the error
    // with Retry, as the webapp does — not the list row standing in for it,
    // which kept a removed or unreachable task on screen with Edit enabled.
    final detailAsync = ref.watch(opsTaskDetailProvider(id));
    final detailFailed =
        ApiConfig.apiEnabled && detailAsync.hasError && !detailAsync.isLoading;
    final gate = detailFailed
        ? AsyncValue<List<OpsTask>>.error(
            detailAsync.error!, detailAsync.stackTrace ?? StackTrace.current)
        : task != null
            ? const AsyncValue<List<OpsTask>>.data(<OpsTask>[])
            : tasksAsync;

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          _appBar('Task', task?.subject),
          Expanded(
            child: AsyncStateView<List<OpsTask>>(
              value: gate,
              onRetry: () {
                ref.invalidate(opsTaskDetailProvider(id));
                ref.invalidate(opsTasksProvider);
              },
              onRefresh: () => _refresh(id),
              loading: () => const DetailSkeleton(),
              // Webapp: "Task not found." for a removed task, the role copy
              // for a refused one — never the stale record.
              error: (e, retry) => e.type == AppErrorType.notFound ||
                      e.type == AppErrorType.forbidden
                  ? EmptyState(
                      icon: PhosphorIconsRegular.listChecks,
                      title: e.type == AppErrorType.notFound
                          ? 'Task not found.'
                          : 'You don’t have access to this',
                      body: e.type == AppErrorType.notFound
                          ? 'This task may have been removed.'
                          : projectTaskErrorMessage(e, ProjectTaskAction.view),
                    )
                  : ErrorState.forError(e, onRetry: retry),
              data: (_) {
                if (task == null) {
                  return const EmptyState(
                    icon: PhosphorIconsRegular.listChecks,
                    title: 'Task not found',
                    body:
                        'This task may have been removed, or you may not have access to it.',
                  );
                }
                // Subtasks come from the shared provider so toggles stay in sync
                // with the standalone subtask page (#12). Dependencies remain a
                // local working copy.
                final subtasks = ref.watch(opsSubtasksProvider(id));
                // Seed the local working copy from the **full** record only.
                // `??=` seeded it on the first build instead, which is the slim
                // list row — and that carries no dependency edges at all, so
                // the blockers stayed empty until the screen was rebuilt from
                // scratch (which is why they showed up after a trip through
                // Edit and back).
                //
                // Only once the refetch has *landed*: while it is in flight
                // the provider still carries the previous record, and seeding
                // from that put the pre-change chips straight back after an
                // add or remove.
                if (_waitingOn == null &&
                    detailAsync.valueOrNull != null &&
                    !detailAsync.isLoading) {
                  _waitingOn = List.of(task.waitingOn);
                }
                // API mode: the record's own edges, refetched after every write —
                // a local copy went stale after an add or remove.
                final waitingOn = ApiConfig.apiEnabled
                    ? task.waitingOn
                    : (_waitingOn ?? task.waitingOn);
                final status = _status ?? task.status;

                // The org's own name and colour; a status just picked here has
                // its name in [_statusName] until the record comes back.
                final meta = opsTaskStatusMeta(
                  key: status,
                  statusName:
                      _statusName ?? (_status == null ? task.statusName : ''),
                  statuses: ref.watch(opsTaskStatusOptionsProvider),
                );
                final priColor = StatusMeta$.projectPriority[task.pri] ??
                    AppColors.textMuted;
                final locked = status == 'completed' || status == 'cancelled';
                final project =
                    projects.where((p) => p.id == task.projId).firstOrNull;
                final overdue = isTaskOverdue(task);
                final progress = task.computedProgress(subtasks);

                // Webapp: the role holds Operations › Tasks (edit) but this
                // record says `can_update: false` — readable, not changeable.
                final viewOnly =
                    hasPermission(ref, 'project_task', PermVerb.update) &&
                        task.canUpdate == false;

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 40.h),
                  children: [
                    _summaryCard(
                        task,
                        meta,
                        priColor,
                        project?.name ?? task.projectName.ifEmpty('—'),
                        overdue),
                    if (viewOnly) ...[
                      SizedBox(height: 14.h),
                      _viewOnlyBanner()
                    ],
                    // SLA engine: an expected-end change waiting on the manager.
                    PendingDueDateBanner(
                        pending: task.pendingDueChange, fieldLabel: 'Due date'),
                    ApprovalBanner(
                        module: ApprovalModules.projectTask, objectId: task.id),
                    if (locked) ...[
                      SizedBox(height: 14.h),
                      _lockBanner(status)
                    ],
                    SizedBox(height: 14.h),
                    _detailsCard(task, meta, progress, locked),
                    SizedBox(height: 14.h),
                    _subtasksCard(task, subtasks, locked),
                    if ((!locked && task.projId.isNotEmpty) ||
                        _hasDeps(task, waitingOn, allTasks)) ...[
                      SizedBox(height: 14.h),
                      _depsCard(task, waitingOn, allTasks, locked),
                    ],
                    SizedBox(height: 14.h),
                    _filesCard(task, locked),
                    _notes(task.id),
                    _auditLog(task, waitingOn),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Pull-to-refresh. Reloads the enriched record, the org-wide list (for the
  /// list-row fallback), this task's subtasks, its activity log and its notes
  /// together.
  Future<void> _refresh(String id) async {
    ref.invalidate(opsTaskDetailProvider(id));
    ref.invalidate(opsTasksProvider);
    ref.invalidate(opsTaskActivityProvider(id));
    // Whole family: the notifier loads in its constructor, so dropping it is
    // what re-reads the thread. Not awaited — nothing exposes that future —
    // but the record fetches below outlast it comfortably.
    ref.invalidate(crmNotesProvider);
    await settle([
      ref.read(opsTaskDetailProvider(id).future),
      ref.read(opsTasksProvider.future),
      ref.read(opsTaskActivityProvider(id).future),
      // The subtasks notifier isn't a FutureProvider — its own `load()` is the
      // equivalent reload.
      ref.read(opsSubtasksProvider(id).notifier).load(),
    ]);
  }

  Widget _appBar(String section, String? name) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: DetailAppBar(
        section: section,
        name: name,
        onBack: () => context.pop(),
        trailing: DetailIconAction(
          icon: PhosphorIconsBold.dotsThreeVertical,
          onTap: _openMenu,
        ),
      ),
    );
  }

  Widget _summaryCard(OpsTask t, StatusMeta meta, Color priColor,
      String projName, bool overdue) {
    final ids = t.assignees.take(2).toList();
    final more = t.assignees.length - ids.length;
    final names = t.assignees
        .map((id) => MockUsers.of(id).firstName)
        .join(', ')
        .ifEmpty('—');
    // Webapp header sub-line: "{Type} task · {Project}", or "Standalone task".
    final subLine = [
      if (t.typeName.isNotEmpty) '${t.typeName} task',
      if (t.projId.isNotEmpty) projName,
    ].join(' · ').ifEmpty('Standalone task');
    // Priority is hidden when the task has none (API rows say so explicitly).
    final showPri = !ApiConfig.apiEnabled || t.priorityRaw.isNotEmpty;
    final dueColor = overdue ? AppColors.error : AppColors.textLabelAlt;
    final canOpenProject = t.projId.isNotEmpty && t.projectAccessible != false;
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.all(18.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 7.w,
                      runSpacing: 4.h,
                      children: [
                        Text(t.subject,
                            style: AppText.custom(
                                size: 18,
                                weight: FontWeight.w800,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.3)),
                        if (t.milestone)
                          Icon(PhosphorIconsFill.flag,
                              size: 16.sp, color: AppColors.warningDeep),
                        if (t.pendingDeps > 0)
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8.w, vertical: 3.h),
                            decoration: BoxDecoration(
                                color: AppColors.tintAmber,
                                borderRadius: BorderRadius.circular(999.r)),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(PhosphorIconsRegular.hourglassMedium,
                                  size: 11.sp, color: const Color(0xFFB45C00)),
                              SizedBox(width: 4.w),
                              Text('Waiting on ${t.pendingDeps}',
                                  style: AppText.custom(
                                      size: 11,
                                      weight: FontWeight.w700,
                                      color: const Color(0xFFB45C00))),
                            ]),
                          ),
                      ],
                    ),
                    SizedBox(height: 4.h),
                    Text(subLine,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(
                            size: 13,
                            weight: FontWeight.w500,
                            color: AppColors.textMuted)),
                    if (t.projId.isNotEmpty) ...[
                      SizedBox(height: 6.h),
                      // The project chip: a link when the project can be opened,
                      // plain text with a lock when it is outside this user's reach.
                      GestureDetector(
                        onTap: canOpenProject
                            ? () => context
                                .push('${Routes.projectDetail}?id=${t.projId}')
                            : () => ref
                                .read(toastProvider.notifier)
                                .show("You don't have access to this project"),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(
                            child: Text(
                                '$projName › ${t.group.ifEmpty('No group')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.custom(
                                    size: 12.5,
                                    weight: FontWeight.w600,
                                    color: canOpenProject
                                        ? AppColors.blueBright
                                        : AppColors.textMuted)),
                          ),
                          if (!canOpenProject) ...[
                            SizedBox(width: 4.w),
                            Icon(PhosphorIconsRegular.lock,
                                size: 12.sp, color: AppColors.textPlaceholder),
                          ],
                        ]),
                      ),
                    ],
                    if (t.hasFromTicket) ...[
                      SizedBox(height: 8.h),
                      GestureDetector(
                        // The ticket opens even for an assignee without Helpdesk — its
                        // detail sits outside the module guard, as on the webapp.
                        onTap: () => context
                            .push('${Routes.ticketDetail}?id=${t.fromTicket}'),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10.w, vertical: 5.h),
                          decoration: BoxDecoration(
                              color: AppColors.blueSubtle,
                              borderRadius: BorderRadius.circular(8.r)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(PhosphorIconsFill.ticket,
                                  size: 12.sp, color: AppColors.blueBright),
                              SizedBox(width: 6.w),
                              Text('From ticket',
                                  style: AppText.custom(
                                      size: 11.5,
                                      weight: FontWeight.w700,
                                      color: AppColors.blueBright)),
                              SizedBox(width: 6.w),
                              Icon(PhosphorIconsBold.arrowRight,
                                  size: 10.sp, color: AppColors.blueBright),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 12.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GestureDetector(
                      onTap: _openStatusSheet, child: StatusPill.meta(meta)),
                  if (showPri) ...[
                    SizedBox(height: 5.h),
                    StatusPill(label: t.pri, color: priColor),
                  ],
                ],
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 14)),
          Row(
            children: [
              AvatarStack(size: 28, overlap: 7, items: [
                for (final id in ids)
                  (MockUsers.of(id).initials, AppColors.navy)
              ]),
              if (more > 0) ...[
                SizedBox(width: 5.w),
                Text('+$more',
                    style: AppText.custom(
                        size: 11,
                        weight: FontWeight.w700,
                        color: AppColors.textMuted2)),
              ],
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(names,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(
                            size: 13,
                            weight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    SizedBox(height: 1.h),
                    Text('Assignees',
                        style: AppText.custom(
                            size: 11.5,
                            weight: FontWeight.w500,
                            color: AppColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          // Webapp: "Due 17 Nov 2026 · Overdue · PRJ-1003-t2" (red when overdue),
          // "No due date" when there is none. Tap to change it (UI/UX
          // audit #04 — the header used to be inert).
          InkWell(
            onTap: () => _changeDue(t),
            child: Row(
              children: [
                Icon(PhosphorIconsRegular.calendarBlank,
                    size: 15.sp,
                    color:
                        overdue ? AppColors.error : AppColors.textPlaceholder),
                SizedBox(width: 7.w),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: t.endISO.trim().isEmpty && t.end.trim().isEmpty
                              ? 'No due date · tap to set'
                              : 'Due ${t.endISO.trim().isEmpty ? t.end : dueDateLabel(t.endISO)}',
                          style: TextStyle(color: dueColor)),
                      if (overdue)
                        TextSpan(
                            text: ' · Overdue',
                            style: TextStyle(color: AppColors.error)),
                      if (t.code.isNotEmpty)
                        TextSpan(
                            text: ' · ${t.code}',
                            style: TextStyle(color: AppColors.textPlaceholder)),
                    ]),
                    style: AppText.custom(
                        size: 13, weight: FontWeight.w600, color: dueColor),
                  ),
                ),
                Icon(PhosphorIconsRegular.pencilSimple,
                    size: 14.sp, color: AppColors.textPlaceholder),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _viewOnlyCopy = 'You can view this task but not change it.';

  /// Webapp `ProjectTaskDetailScreen`: module update granted, record refused.
  Widget _viewOnlyBanner() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: AppColors.bgChipGrey,
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsFill.eye, size: 18.sp, color: AppColors.textMuted2),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(_viewOnlyCopy,
                style: AppText.custom(
                    size: 13,
                    weight: FontWeight.w700,
                    color: AppColors.textLabelAlt)),
          ),
        ],
      ),
    );
  }

  /// Whether the signed-in role may change task [id]: the module's edit grant
  /// (webapp `PermissionGate`) and the record's own `can_update`. Says why
  /// when it may not, instead of sending a write the server will refuse.
  bool _ensureCanEdit(String id) {
    if (!ensurePermission(ref, 'project_task', PermVerb.update)) return false;
    if (ref.read(opsTaskDetailOrListProvider(id))?.canUpdate == false) {
      ref.read(toastProvider.notifier).showError(_viewOnlyCopy);
      return false;
    }
    return true;
  }

  Widget _lockBanner(String status) {
    final completed = status == 'completed';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: completed ? AppColors.tintGreen : AppColors.bgChipGrey,
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
              completed
                  ? PhosphorIconsFill.sealCheck
                  : PhosphorIconsFill.prohibit,
              size: 18.sp,
              color: completed ? AppColors.success : AppColors.textMuted2),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This task is $status — fields are locked.',
                    style: AppText.custom(
                        size: 13,
                        weight: FontWeight.w700,
                        color: completed
                            ? AppColors.success
                            : AppColors.textLabelAlt)),
                SizedBox(height: 2.h),
                Text('Status and notes stay editable.',
                    style: AppText.custom(
                        size: 12,
                        weight: FontWeight.w500,
                        color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One Details row, long-press editable in place like a lead's fields.
  /// Expected time, task weight, milestone and department save from the row;
  /// the dates go through the Edit form (a due-date change may need a
  /// manager's approval), and the rest are display-only.
  Widget _holdRow(
      OpsTask t, String label, String value, Color valueColor, bool locked) {
    final row = Container(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppText.custom(
                  size: 13,
                  weight: FontWeight.w500,
                  color: AppColors.textMuted)),
          SizedBox(width: 14.w),
          Expanded(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: AppText.custom(
                      size: 14, weight: FontWeight.w700, color: valueColor))),
        ],
      ),
    );
    final toast = ref.read(toastProvider.notifier);
    void blocked(String m) => toast.show(m);
    final canEdit = !locked && _canWrite(t);
    final hint = locked
        ? 'This task is ${t.status == 'cancelled' ? 'cancelled' : 'completed'} — it can no longer be edited.'
        : (hasPermission(ref, 'project_task', PermVerb.update)
            ? _viewOnlyCopy
            : permissionCopy(PermVerb.update));
    OpsHoldEditRow field(String key, String type, Object? raw) =>
        OpsHoldEditRow(
          label: label,
          display: value,
          apiKey: key,
          type: type,
          rawValue: raw,
          canEdit: canEdit,
          deniedHint: hint,
          editForm: 'Edit task',
          onSave: (k, v) => _saveTaskField(t, label, k, v),
          onBlocked: blocked,
          child: row,
        );
    switch (label) {
      case 'Expected time':
        return field('expected_time', 'decimal', t.expHrs);
      case 'Task weight':
        return field('task_weight', 'decimal', t.weight);
      case 'Milestone':
        return field('is_milestone', 'boolean', t.milestone);
      case 'Department':
        return field('department', 'string', t.dept);
      case 'Due date':
        return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () => _changeDue(t),
            child: row);
      case 'Expected start':
        return OpsReadOnlyHoldRow(
            message: '$label is changed from Edit task.',
            onBlocked: blocked,
            child: row);
      default:
        return OpsReadOnlyHoldRow(
            message: '$label is read-only.', onBlocked: blocked, child: row);
    }
  }

  /// Writes one field from a row. Null on success, the server's words on a
  /// refusal (shown beside the box, as on a lead).
  Future<Object?> _saveTaskField(
      OpsTask t, String label, String key, Object? value) async {
    if (!_ensureCanEdit(t.id)) return _viewOnlyCopy;
    // The task write drops blanks, so an emptied box would look saved and
    // change nothing.
    if (value == null || (value is String && value.trim().isEmpty)) {
      return 'Enter a value — to clear it, use Edit task.';
    }
    try {
      await ref
          .read(opsTasksRepositoryProvider)
          .updateOpsTask(t.id, {key: value});
      ref.invalidate(opsTasksProvider);
      ref.invalidate(opsTasksScopedProvider);
      ref.invalidate(opsTaskDetailProvider(t.id));
      ref.read(toastProvider.notifier).show('$label updated');
      return null;
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      return e.bareMessage.isEmpty ? 'Could not save.' : e.bareMessage;
    }
  }

  Widget _detailsCard(OpsTask t, StatusMeta meta, int progress, bool locked) {
    final valueColor =
        locked ? AppColors.textPlaceholder : AppColors.textPrimary;
    final rows = <(String, String)>[
      // `task_code` ("PRJ-1010-t3"), display-only and stable. Absent on a
      // standalone task and on the slim list row, so the row waits for the
      // retrieve rather than showing the UUID.
      if (t.code.isNotEmpty) ('Task ID', t.code),
      ('Type', t.typeName.ifEmpty('—')),
      ('Expected start', opsWhenLabel(t.start, t.startTime)),
      // "Due date", as CRM calls the same field (UI/UX audit #04).
      ('Due date', opsWhenLabel(t.end, t.endTime)),
      // Detail-only decimals, so both wait for the retrieve rather than
      // printing the "0 hrs" / "1" the mapper used to hardcode.
      if (t.expHrs != null)
        ('Expected time', '${opsDecimalLabel(t.expHrs!)} hrs'),
      if (t.weight != null) ('Task weight', opsDecimalLabel(t.weight!)),
      ('Milestone', t.milestone ? 'Yes' : 'No'),
      ('Department', t.dept.trim().isEmpty ? '—' : t.dept),
    ];
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Details',
              style: AppText.custom(
                  size: 15,
                  weight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          Padding(
            padding: EdgeInsets.fromLTRB(2.w, 12.h, 2.w, 4.h),
            // Webapp copy when there is none.
            child: Text(
                t.desc.trim().isEmpty
                    ? 'No description yet — use Edit to add context for this task.'
                    : t.desc,
                style: AppText.custom(
                    size: 14,
                    weight: FontWeight.w500,
                    color: locked || t.desc.trim().isEmpty
                        ? AppColors.textPlaceholder
                        : AppColors.textLabelAlt,
                    height: 1.6)),
          ),
          SizedBox(height: 6.h),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4.r),
                  child: LinearProgressIndicator(
                    value: progress / 100,
                    minHeight: 8.h,
                    backgroundColor: const Color(0xFFEEF1F4),
                    valueColor: AlwaysStoppedAnimation(meta.color),
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Text('$progress%',
                  style: AppText.custom(
                      size: 13,
                      weight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ],
          ),
          if (t.progress == null) ...[
            SizedBox(height: 4.h),
            Text('Calculated from subtasks',
                style: AppText.custom(
                    size: 11.5,
                    weight: FontWeight.w500,
                    color: AppColors.textPlaceholder)),
          ],
          // Only when the record actually carries one of them — a completed
          // task whose dates were never stamped would otherwise read
          // "started — · completed —".
          if (t.status == 'completed' &&
              (t.actualStart != null || t.actualEnd != null)) ...[
            SizedBox(height: 4.h),
            Text(
                'Actual: started ${t.actualStart ?? '—'} · completed ${t.actualEnd ?? '—'}',
                style: AppText.custom(
                    size: 12,
                    weight: FontWeight.w500,
                    color: AppColors.textPlaceholder)),
          ],
          SizedBox(height: 6.h),
          if (!locked && _canWrite(t)) const OpsHoldEditHint(),
          for (final r in rows) _holdRow(t, r.$1, r.$2, valueColor, locked),
          if (ApiConfig.apiEnabled && t.color.name.isNotEmpty) _colorRow(t),
          if (ApiConfig.apiEnabled) _committedRow(t, locked),
          if (!locked) ...[
            // Dimmed, with the reason under it, for a user who may not edit
            // (module grant or this record's can_update) — as Edit project.
            Opacity(
              opacity: _canWrite(t) ? 1 : 0.45,
              child: GestureDetector(
                onTap: () {
                  if (!_ensureCanEdit(t.id)) return;
                  context.push('${Routes.editTask}?id=${t.id}');
                },
                child: Container(
                  height: 44.h,
                  margin: EdgeInsets.only(top: 14.h),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(12.r),
                    border:
                        Border.all(color: const Color(0xFFE6E7EA), width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsRegular.pencilSimple,
                          size: 15.sp, color: AppColors.textSecondary),
                      SizedBox(width: 7.w),
                      Text('Edit task',
                          style: AppText.custom(
                              size: 13.5,
                              weight: FontWeight.w700,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            ),
            // Labelled primary action, as on CRM Task (UI/UX audit #15).
            Opacity(
              opacity: _canWrite(t) ? 1 : 0.45,
              child: Semantics(
                button: true,
                label: 'Mark complete',
                child: GestureDetector(
                  onTap: () => _markComplete(t),
                  child: Container(
                    height: 44.h,
                    margin: EdgeInsets.only(top: 10.h),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsBold.check,
                            size: 15.sp, color: AppColors.white),
                        SizedBox(width: 7.w),
                        Text('Mark complete',
                            style: AppText.custom(
                                size: 13.5,
                                weight: FontWeight.w700,
                                color: AppColors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!_canWrite(t)) ...[
              SizedBox(height: 6.h),
              Text(
                hasPermission(ref, 'project_task', PermVerb.update)
                    ? _viewOnlyCopy
                    : permissionCopy(PermVerb.update),
                textAlign: TextAlign.center,
                style: AppText.custom(
                    size: 12,
                    weight: FontWeight.w500,
                    color: AppColors.textMuted),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// SLA engine — the committed end (webapp `committedDateField`): the date
  /// or "Not committed yet", how often it moved, and a lock: only admins and
  /// Executive Leadership (`can_change_committed_date`) may change it, through
  /// the same reason / approval flow as the expected end.
  /// Webapp "Color tag": the task's swatch.
  Widget _colorRow(OpsTask t) => Container(
        padding: EdgeInsets.symmetric(vertical: 10.h),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
        child: Row(children: [
          Text('Color tag',
              style: AppText.custom(
                  size: 13,
                  weight: FontWeight.w500,
                  color: AppColors.textMuted)),
          const Spacer(),
          Container(
            width: 16.w,
            height: 16.w,
            decoration: BoxDecoration(
              color: t.color.hex,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.borderCardSoft),
            ),
          ),
        ]),
      );

  Widget _committedRow(OpsTask t, bool locked) {
    final canChange = !locked &&
        t.canChangeCommitted == true &&
        t.canUpdate != false &&
        hasPermission(ref, 'project_task', PermVerb.update);
    final moved = rescheduleLabel(
        {'reschedule_count': t.rescheduleCount, 'slip_days': t.slipDays});
    final value = t.committedEndISO.isEmpty
        ? 'Not committed yet'
        : dueDateLabel(t.committedEndISO);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canChange
          ? () => _changeCommitted(t)
          : () => ref.read(toastProvider.notifier).show(
              'Locked once set; admins and Executive Leadership can change it'),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10.h),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Committed end',
                style: AppText.custom(
                    size: 13,
                    weight: FontWeight.w500,
                    color: AppColors.textMuted)),
            SizedBox(width: 6.w),
            Icon(
                canChange
                    ? PhosphorIconsRegular.pencilSimple
                    : PhosphorIconsRegular.lock,
                size: 13.sp,
                color: AppColors.textPlaceholder),
            SizedBox(width: 14.w),
            Expanded(
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(value,
                    textAlign: TextAlign.right,
                    style: AppText.custom(
                        size: 14,
                        weight: FontWeight.w700,
                        color: t.committedEndISO.isEmpty
                            ? AppColors.textPlaceholder
                            : AppColors.textPrimary)),
                if (moved != null) ...[
                  SizedBox(height: 2.h),
                  Text(moved,
                      style: AppText.custom(
                          size: 11.5,
                          weight: FontWeight.w600,
                          color: AppColors.warningDeep)),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }

  /// Header date tap / Due date long-press (UI/UX audit #04): pick a new
  /// due date and save it through the same reason / approval flow the web
  /// uses for an expected-end change. Edit rights and an unlocked task needed.
  Future<void> _changeDue(OpsTask t) async {
    if (!_ensureCanEdit(t.id)) return;
    final status = t.status;
    if (status == 'completed' || status == 'cancelled') {
      ref
          .read(toastProvider.notifier)
          .show('This task is closed — reopen it to change the due date.');
      return;
    }
    final current = DateTime.tryParse(t.endISO)?.toLocal();
    final d = await showDatePicker(
      context: context,
      helpText: 'Due date',
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (d == null || !mounted) return;
    try {
      final outcome = await writeWithDueDateFlow(
        context,
        ref,
        path: '/projects/tasks/${t.id}/',
        fields: {'exp_end_date': opsTaskEndStamp(d, keepTimeFrom: current)},
        hadDate: t.endISO.trim().isNotEmpty,
        dateKey: 'exp_end_date',
        fieldLabel: 'Due date',
        dateLabel: dueDateLabel(apiDate(d)),
      );
      if (!mounted) return;
      if (outcome == DueDateWrite.saved) {
        ref.read(toastProvider.notifier).show('Due date updated');
      }
      ref.invalidate(opsTaskDetailProvider(t.id));
      ref.invalidate(opsTasksProvider);
    } on AppError catch (e) {
      if (!mounted) return;
      ref.read(apiServiceProvider).handled(e);
      ref
          .read(toastProvider.notifier)
          .showError(projectTaskErrorMessage(e, ProjectTaskAction.update));
    }
  }

  Future<void> _changeCommitted(OpsTask t) async {
    final current = DateTime.tryParse(t.committedEndISO)?.toLocal();
    final d = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (d == null || !mounted) return;
    final iso = '${apiDate(d)}T00:00:00${_tzOffset(d)}';
    try {
      final outcome = await writeWithDueDateFlow(
        context,
        ref,
        path: '/projects/tasks/${t.id}/',
        fields: {'committed_end_date': iso},
        hadDate: t.committedEndISO.isNotEmpty,
        dateKey: 'committed_end_date',
        fieldLabel: 'Committed end',
        dateLabel: dueDateLabel(apiDate(d)),
      );
      if (!mounted) return;
      if (outcome == DueDateWrite.saved)
        ref.read(toastProvider.notifier).show('Saved');
      ref.invalidate(opsTaskDetailProvider(t.id));
    } on AppError catch (e) {
      if (!mounted) return;
      ref.read(apiServiceProvider).handled(e);
      ref
          .read(toastProvider.notifier)
          .showError(projectTaskErrorMessage(e, ProjectTaskAction.update));
    }
  }

  /// "+05:30" — the device's offset, so a picked day stays that day server-side.
  static String _tzOffset(DateTime d) {
    final o = d.timeZoneOffset;
    final sign = o.isNegative ? '-' : '+';
    final m = o.inMinutes.abs();
    return '$sign${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  /// Webapp Files tab: the task's attachments (`related_to=project_task`),
  /// "No files yet", and "Upload file" → "File uploaded".
  Widget _filesCard(OpsTask t, bool locked) {
    final async = ref.watch(projectTaskFilesProvider(t.id));
    final files = async.valueOrNull ?? const <LeadFile>[];
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(PhosphorIconsRegular.paperclip,
                size: 16.sp, color: AppColors.textLabelAlt),
            SizedBox(width: 7.w),
            Text('Files',
                style: AppText.custom(
                    size: 15,
                    weight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ]),
          SizedBox(height: 8.h),
          if (files.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Text(async.isLoading ? 'Loading files…' : 'No files yet',
                  style: AppText.custom(
                      size: 13,
                      weight: FontWeight.w500,
                      color: AppColors.textPlaceholder)),
            ),
          for (final f in files)
            _fileRow(t, f, canManage: !locked && _canWrite(t)),
          SizedBox(height: 8.h),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _uploading ? null : () => _uploadFile(t),
            child: Container(
              height: 42.h,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11.r),
                border: Border.all(color: AppColors.borderInput),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                    _uploading
                        ? PhosphorIconsRegular.circleNotch
                        : PhosphorIconsRegular.uploadSimple,
                    size: 15.sp,
                    color: AppColors.navy),
                SizedBox(width: 8.w),
                Text(_uploading ? 'Uploading…' : 'Upload file',
                    style: AppText.custom(
                        size: 13.5,
                        weight: FontWeight.w600,
                        color: AppColors.textBody)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// One attachment, as the CRM Files rows show it (UI/UX audit #02): type
  /// icon, name, "TXT · 4 B · Sufail Salim · 2d ago", and Rename · Download ·
  /// Delete. Rename / Delete need edit rights on an unlocked task.
  Widget _fileRow(OpsTask t, LeadFile f, {required bool canManage}) {
    final uploader = f.uploaderName.isNotEmpty
        ? f.uploaderName
        : (f.uploadedBy.isEmpty ? '' : MockUsers.of(f.uploadedBy).name);
    final meta = [
      f.ext,
      if (f.sizeLabel.isNotEmpty) f.sizeLabel,
      if (uploader.isNotEmpty) uploader,
      if (f.uploadedAt.isNotEmpty) f.uploadedAt,
    ].join(' · ');
    Widget action(IconData icon, String label, VoidCallback onTap,
            {Color? color}) =>
        Semantics(
          button: true,
          label: label,
          child: Tooltip(
            message: label,
            child: InkWell(
              borderRadius: BorderRadius.circular(8.r),
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.all(7.w),
                child: Icon(icon,
                    size: 17.sp, color: color ?? AppColors.textMuted),
              ),
            ),
          ),
        );
    return InkWell(
      onTap: () => _openFile(f),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 9.h),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
        child: Row(children: [
          Container(
            width: 34.w,
            height: 34.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: AppColors.bgChipGrey,
                borderRadius: BorderRadius.circular(10.r)),
            child: Icon(attachmentIcon(f.ext),
                size: 17.sp, color: AppColors.textSecondary),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.custom(
                      size: 13.5,
                      weight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              SizedBox(height: 2.h),
              Text(meta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption()),
            ]),
          ),
          if (canManage)
            action(PhosphorIconsRegular.pencilSimple, 'Rename file',
                () => _renameFile(t, f)),
          action(PhosphorIconsRegular.downloadSimple, 'Download file',
              () => _openFile(f)),
          if (canManage)
            action(PhosphorIconsRegular.trash, 'Delete file',
                () => _deleteFile(t, f),
                color: AppColors.error),
        ]),
      ),
    );
  }

  /// Hands the stored file to the OS (view / save), reporting why if it can't.
  Future<void> _openFile(LeadFile f) async {
    final failure = await openAttachment(f.url);
    if (failure != null && mounted) {
      ref.read(toastProvider.notifier).showError(failure);
    }
  }

  /// The upload's name dialog again, then `PATCH` the name (extension kept).
  Future<void> _renameFile(OpsTask t, LeadFile f) async {
    if (!_ensureCanEdit(t.id)) return;
    final typed = await showFileNameDialog(context, f.name,
        title: 'Rename file', action: 'Save');
    if (typed == null || !mounted) return;
    final next = storedFileName(typed, f.name);
    if (next == f.name) return;
    final err =
        await ref.read(attachmentsRepositoryProvider).renameFile(f.id, next);
    if (!mounted) return;
    final toast = ref.read(toastProvider.notifier);
    if (err != null) {
      toast.showError(err);
      return;
    }
    ref.invalidate(projectTaskFilesProvider(t.id));
    toast.show('File renamed');
  }

  /// Confirm, then `DELETE /crm/attachments/{id}/`.
  Future<void> _deleteFile(OpsTask t, LeadFile f) async {
    if (!_ensureCanEdit(t.id)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this file?'),
        content: Text('“${f.name}” will be removed from this task.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Delete', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await ref.read(attachmentsRepositoryProvider).deleteFile(f.id);
    if (!mounted) return;
    final toast = ref.read(toastProvider.notifier);
    if (err != null) {
      toast.showError(err);
      return;
    }
    ref.invalidate(projectTaskFilesProvider(t.id));
    toast.show('File deleted');
  }

  Future<void> _uploadFile(OpsTask t) async {
    if (!_ensureCanEdit(t.id)) return;
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(withData: false);
    } on Object catch (e) {
      if (!mounted) return;
      ref
          .read(toastProvider.notifier)
          .showError('Could not open the file picker: $e');
      return;
    }
    final file = picked?.files.singleOrNull;
    final path = file?.path;
    if (file == null || path == null || !mounted) return;
    // Offer the stored name (extension kept), as every other record's upload
    // does (webapp upload dialog) — UAT.
    final typed = await showFileNameDialog(context, file.name);
    if (typed == null || !mounted) return;
    final storedName = storedFileName(typed, file.name);
    setState(() => _uploading = true);
    try {
      await AttachmentsRemoteDataSource(ref.read(apiServiceProvider))
          .uploadFile(
        relatedTo: 'project_task',
        relatedToId: t.id,
        path: path,
        name: storedName,
      );
      if (!mounted) return;
      ref.invalidate(projectTaskFilesProvider(t.id));
      ref.read(toastProvider.notifier).show('File uploaded');
    } on AppError catch (e) {
      if (!mounted) return;
      ref.read(apiServiceProvider).handled(e);
      ref
          .read(toastProvider.notifier)
          .showError(projectTaskErrorMessage(e, ProjectTaskAction.update));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Webapp `canEdit`: the module's edit grant and this record's own
  /// `can_update`. Without it the add-subtask and add-dependency editors are
  /// not offered at all.
  bool _canWrite(OpsTask t) =>
      hasPermission(ref, 'project_task', PermVerb.update) &&
      t.canUpdate != false;

  Widget _subtasksCard(OpsTask t, List<Subtask> subs, bool locked) {
    final taskId = t.id;
    // The child rows are their own fetch (§3C), so until they land the record's
    // own `subtask_done_count` / `subtask_count` are what the counter has —
    // showing "0/0 done" on a task the server says has five would be wrong.
    final done =
        subs.isEmpty ? t.subtaskDoneCount : subs.where((s) => s.done).length;
    final total = subs.isEmpty ? t.subtaskCount : subs.length;
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.listChecks,
                  size: 16.sp, color: AppColors.textLabelAlt),
              SizedBox(width: 7.w),
              Text('Subtasks',
                  style: AppText.custom(
                      size: 15,
                      weight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const Spacer(),
              if (total > 0)
                Text('$done/$total done',
                    style: AppText.custom(
                        size: 12,
                        weight: FontWeight.w600,
                        color: AppColors.textMuted)),
            ],
          ),
          for (int i = 0; i < subs.length; i++)
            _subtaskRow(taskId, i, subs[i], locked),
          if (!locked && _canWrite(t)) ...[
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40.h,
                    padding: EdgeInsets.symmetric(horizontal: 13.w),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.bgScreen,
                      borderRadius: BorderRadius.circular(11.r),
                      border: Border.all(color: const Color(0xFFE6E7EA)),
                    ),
                    child: TextField(
                      controller: _subCtrl,
                      style: AppText.custom(
                          size: 13.5,
                          weight: FontWeight.w500,
                          color: AppColors.textBody),
                      cursorColor: AppColors.blueBright,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addSubtask(taskId),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '+ Add subtask',
                        hintStyle: AppText.custom(
                            size: 13.5,
                            weight: FontWeight.w500,
                            color: AppColors.textPlaceholder),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 9.w),
                GestureDetector(
                  onTap: () => _addSubtask(taskId),
                  child: Container(
                    width: 40.w,
                    height: 40.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: AppColors.navy,
                        borderRadius: BorderRadius.circular(11.r)),
                    child: Icon(PhosphorIconsBold.plus,
                        size: 16.sp, color: AppColors.white),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            Wrap(spacing: 6.w, runSpacing: 6.h, children: [
              _subChip(
                PhosphorIconsRegular.calendarBlank,
                _subDate == null ? 'Due date' : opsFmtDate(_subDate!),
                active: _subDate != null,
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    helpText: 'Subtask due date',
                    initialDate: _subDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(DateTime.now().year + 5),
                  );
                  if (d != null && mounted) setState(() => _subDate = d);
                },
                onClear: _subDate == null
                    ? null
                    : () => setState(() {
                          _subDate = null;
                          _subTime = null;
                        }),
              ),
              _subChip(
                PhosphorIconsRegular.clock,
                _subTime == null ? 'Time' : opsFmtTime(_subTime!),
                active: _subTime != null,
                // A time only means something with a day.
                onTap: _subDate == null
                    ? null
                    : () async {
                        final tm = await showTimePicker(
                            context: context,
                            initialTime: _subTime ?? TimeOfDay.now());
                        if (tm != null && mounted) {
                          setState(() => _subTime = tm);
                        }
                      },
                onClear: _subTime == null
                    ? null
                    : () => setState(() => _subTime = null),
              ),
              _subChip(
                PhosphorIconsRegular.userCircle,
                _subAssigneeName ?? "Parent's assignee",
                active: _subAssignee != null,
                onTap: _pickSubAssignee,
                onClear: _subAssignee == null
                    ? null
                    : () => setState(() {
                          _subAssignee = null;
                          _subAssigneeName = null;
                        }),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _subtaskRow(String taskId, int index, Subtask s, bool locked) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Webapp: a subtask is a full project task — same detail, notes, files
      // and audit — so it opens the task page itself (mock rows have no id of
      // their own and keep the reduced subtask page).
      onTap: () => ApiConfig.apiEnabled && s.id.isNotEmpty
          ? context.push('${Routes.opsTaskDetail}?id=${s.id}')
          : context.push('${Routes.opsSubtask}?taskId=$taskId&i=$index'),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 11.h),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
        child: Row(
          children: [
            GestureDetector(
              onTap: locked ? null : () => _toggleSubtask(taskId, index),
              child: Container(
                width: 22.w,
                height: 22.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s.done ? AppColors.navy : AppColors.white,
                  borderRadius: BorderRadius.circular(7.r),
                  border: s.done
                      ? null
                      : Border.all(color: const Color(0xFFC9CCD2), width: 1.5),
                ),
                child: Icon(PhosphorIconsBold.check,
                    size: 13.sp,
                    color: s.done ? AppColors.white : Colors.transparent),
              ),
            ),
            SizedBox(width: 11.w),
            Expanded(
              child: Text(s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.custom(
                      size: 13.5,
                      weight: FontWeight.w600,
                      color: s.done
                          ? AppColors.textPlaceholder
                          : AppColors.textBody,
                      decoration: s.done ? TextDecoration.lineThrough : null)),
            ),
            if (s.due.isNotEmpty) ...[
              SizedBox(width: 8.w),
              Text(s.due,
                  style: AppText.custom(
                      size: 11,
                      weight: FontWeight.w600,
                      color: AppColors.textPlaceholder)),
            ],
            SizedBox(width: 8.w),
            // Unassigned subtasks are ordinary — the avatar is dropped rather
            // than drawn as an "Unknown" placeholder.
            if (s.who.isNotEmpty) ...[
              Container(
                width: 24.w,
                height: 24.w,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                    color: AppColors.navy, shape: BoxShape.circle),
                child: Text(MockUsers.of(s.who).initials,
                    style: AppText.custom(
                        size: 8.5,
                        weight: FontWeight.w700,
                        color: AppColors.white)),
              ),
              SizedBox(width: 6.w),
            ],
            Icon(PhosphorIconsRegular.caretRight,
                size: 13.sp, color: AppColors.textPlaceholder),
          ],
        ),
      ),
    );
  }

  /// Drops the local copy so the card re-seeds from the refetched record —
  /// otherwise the working list would keep showing the pre-edit set.
  void _refreshDeps(String taskId) {
    setState(() => _waitingOn = null);
    ref.invalidate(opsTaskDetailProvider(taskId));
    ref.invalidate(opsTasksProvider);
    ref.invalidate(opsTasksScopedProvider);
  }

  /// `DELETE /projects/task-dependencies/{edge}/`. The ✕ used to mutate the
  /// local list only, so the blocker came straight back on the next load.
  Future<void> _removeDep(OpsTask t, String blockerId, String? edgeId) async {
    if (!_ensureCanEdit(t.id)) return;
    if (!ApiConfig.apiEnabled) {
      setState(() => _waitingOn?.remove(blockerId));
      return;
    }
    // No edge id means this row came from a slim list row rather than the
    // record, so there is nothing to delete by. Refetch instead of pretending.
    if (edgeId == null || edgeId.isEmpty) {
      _refreshDeps(t.id);
      return;
    }
    try {
      await ref.read(opsTasksRepositoryProvider).removeDependency(edgeId);
      if (!mounted) return;
      _refreshDeps(t.id);
      ref.read(toastProvider.notifier).show('Dependency removed');
    } on AppError catch (e) {
      if (!mounted) return;
      ref.read(apiServiceProvider).handled(e);
      ref
          .read(toastProvider.notifier)
          .showError(projectTaskErrorMessage(e, ProjectTaskAction.update));
    }
  }

  /// `POST /projects/task-dependencies/`. Webapp picker: the tasks in **this
  /// project** ("Search tasks in this project…"), minus this task and every
  /// task already linked either way.
  Future<void> _addDep(
      OpsTask t, List<String> waitingOn, List<OpsTask> all) async {
    if (!_ensureCanEdit(t.id)) return;
    final taken = {t.id, ...waitingOn, for (final b in t.blocking) b.taskId};
    List<OpsTask> pool = all;
    if (ApiConfig.apiEnabled) {
      try {
        pool = await ref.read(projectTasksProvider(t.projId).future);
      } on Object {
        pool = const [];
      }
      if (!mounted) return;
    }
    final options = [
      for (final x in pool)
        if (!taken.contains(x.id) &&
            (x.projId == t.projId || !ApiConfig.apiEnabled))
          (value: x.id, label: x.subject.ifEmpty('Untitled task')),
    ];
    if (options.isEmpty) {
      ref.read(toastProvider.notifier).show('No matching tasks');
      return;
    }
    final chosen = await showOpsOptionPicker(
      context: context,
      title: 'Waiting on',
      options: options,
      currentValue: '',
      searchHint: 'Search tasks in this project…',
    );
    if (chosen == null || !mounted) return;

    if (!ApiConfig.apiEnabled) {
      setState(() => _waitingOn = [...waitingOn, chosen]);
      return;
    }
    try {
      await ref
          .read(opsTasksRepositoryProvider)
          .addDependency(taskId: t.id, dependsOn: chosen);
      if (!mounted) return;
      _refreshDeps(t.id);
      ref.read(toastProvider.notifier).show('Dependency added');
    } on AppError catch (e) {
      if (!mounted) return;
      // A cycle or a duplicate lands here, and the backend's message is the
      // only thing that says which — shown once, without the field prefix.
      ref.read(apiServiceProvider).handled(e);
      ref
          .read(toastProvider.notifier)
          .showError(projectTaskErrorMessage(e, ProjectTaskAction.update));
    }
  }

  bool _hasDeps(OpsTask t, List<String> waitingOn, List<OpsTask> all) {
    if (waitingOn.isNotEmpty || t.blocking.isNotEmpty) return true;
    return all.any((x) => x.waitingOn.contains(t.id));
  }

  Widget _depsCard(
      OpsTask t, List<String> waitingOn, List<OpsTask> all, bool locked) {
    // The record labels its own edges, so a chip needs neither a second fetch
    // nor a scan of the full task list. `all` is only the mock-mode fallback.
    final labelled = {for (final d in t.deps) d.taskId: d};

    final waitChips = <Widget>[];
    for (final id in waitingOn) {
      final edge = labelled[id];
      final wt = all.where((x) => x.id == id).firstOrNull;
      final unres = edge != null
          ? !edge.isClosed
          : wt != null && wt.status != 'completed' && wt.status != 'cancelled';
      final label = edge?.subject.isNotEmpty == true
          ? edge!.subject
          : (wt?.subject ?? id);
      waitChips.add(_depChip(
        label: label,
        unres: unres,
        // Openable off the edge alone — the blocker need not be in the loaded
        // list, and often is not.
        onOpen: () => context.push('${Routes.opsTaskDetail}?id=$id'),
        onRemove: locked ? null : () => _removeDep(t, id, edge?.edgeId),
      ));
    }

    final blocking = t.blocking.isNotEmpty
        ? [for (final d in t.blocking) (id: d.taskId, subject: d.subject)]
        : [
            for (final x in all.where((x) => x.waitingOn.contains(t.id)))
              (id: x.id, subject: x.subject)
          ];
    final showWait = !locked || waitChips.isNotEmpty;

    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.linkSimple,
                  size: 16.sp, color: AppColors.textLabelAlt),
              SizedBox(width: 7.w),
              Text('Dependencies',
                  style: AppText.custom(
                      size: 15,
                      weight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ],
          ),
          if (showWait) ...[
            _depSectionLabel('Waiting on'),
            Wrap(
              spacing: 7.w,
              runSpacing: 7.h,
              children: [
                ...waitChips,
                if (waitChips.isEmpty &&
                    (locked || t.projId.isEmpty || !_canWrite(t)))
                  Text('Nothing yet',
                      style: AppText.custom(
                          size: 12.5,
                          weight: FontWeight.w500,
                          color: AppColors.textPlaceholder)),
                // Not available on a standalone task (blockers come from its project).
                if (!locked && t.projId.isNotEmpty && _canWrite(t))
                  GestureDetector(
                    onTap: () => _addDep(t, waitingOn, all),
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 11.w, vertical: 7.h),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(9.r),
                        border: Border.all(
                            color: const Color(0xFFC9CCD2), width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsBold.plus,
                              size: 11.sp, color: AppColors.textSecondary),
                          SizedBox(width: 5.w),
                          Text('Add',
                              style: AppText.custom(
                                  size: 12,
                                  weight: FontWeight.w700,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (blocking.isNotEmpty) ...[
            _depSectionLabel('Blocking'),
            Wrap(
              spacing: 7.w,
              runSpacing: 7.h,
              children: [
                for (final b in blocking)
                  _depChip(
                      label: b.subject,
                      unres: false,
                      blocking: true,
                      onOpen: () =>
                          context.push('${Routes.opsTaskDetail}?id=${b.id}')),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _depSectionLabel(String text) => Padding(
        padding: EdgeInsets.only(top: 13.h, bottom: 8.h),
        child: Text(text.toUpperCase(),
            style: AppText.custom(
                size: 11,
                weight: FontWeight.w700,
                color: AppColors.textPlaceholder,
                letterSpacing: 0.6)),
      );

  Widget _depChip(
      {required String label,
      required bool unres,
      bool blocking = false,
      VoidCallback? onOpen,
      VoidCallback? onRemove}) {
    final fg = unres ? const Color(0xFFB45C00) : AppColors.textLabelAlt;
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 11.w, vertical: 7.h),
        decoration: BoxDecoration(
          color: unres ? AppColors.tintAmber : AppColors.bgChipGrey,
          borderRadius: BorderRadius.circular(9.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              blocking
                  ? PhosphorIconsRegular.arrowUUpLeft
                  : (unres
                      ? PhosphorIconsFill.clock
                      : PhosphorIconsFill.checkCircle),
              size: 12.sp,
              color: blocking
                  ? AppColors.textMuted2
                  : (unres ? const Color(0xFFB45C00) : AppColors.success),
            ),
            SizedBox(width: 6.w),
            Text(label,
                style: AppText.custom(
                    size: 12,
                    weight: FontWeight.w600,
                    color: blocking ? AppColors.textLabelAlt : fg)),
            if (onRemove != null) ...[
              SizedBox(width: 6.w),
              GestureDetector(
                onTap: onRemove,
                child: Icon(PhosphorIconsBold.x,
                    size: 11.sp, color: AppColors.textPlaceholder),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The task's own audit trail — `GET /projects/tasks/{id}/activity/` (§3B).
  ///
  /// This card used to be five hardcoded rows naming two prototype users and
  /// fixed June dates, on every task in the org.
  ///
  /// In API mode the real feed is the only source: an empty one means the task
  /// genuinely has no recorded history (or the call failed), and no card at all
  /// beats a fabricated timeline. The derived rows survive for mock mode, which
  /// has no endpoint behind it.
  Widget _auditLog(OpsTask t, List<String> waitingOn) {
    final entries =
        ref.watch(opsTaskActivityProvider(t.id)).valueOrNull ?? const [];
    if (entries.isEmpty) {
      if (ApiConfig.apiEnabled) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.only(top: 14.h),
        child: OpsAuditLog(entries: _audit(t, waitingOn)),
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: 14.h),
      child: OpsAuditLog(entries: [for (final e in entries) _auditRow(e)]),
    );
  }

  /// One feed row as a timeline entry. `summary` is already a sentence — the
  /// server humanizes this feed, unlike the raw-diff audit endpoint — so only
  /// the icon and the actor/time line are chosen here.
  AuditEntry _auditRow(crm_audit.AuditEntry e) {
    final (icon, tone, bg) = switch (e.kind) {
      AuditEventKind.created => (
          PhosphorIconsRegular.plusCircle,
          AppColors.navy,
          AppColors.tintNavy
        ),
      AuditEventKind.statusChanged => (
          PhosphorIconsRegular.arrowsClockwise,
          AppColors.blueBright,
          AppColors.blueSubtle
        ),
      AuditEventKind.noteAdded => (
          PhosphorIconsRegular.note,
          AppColors.pending,
          AppColors.tintPurple
        ),
      AuditEventKind.childAdded => (
          PhosphorIconsRegular.listChecks,
          AppColors.success,
          AppColors.tintGreen
        ),
      AuditEventKind.deleted => (
          PhosphorIconsRegular.trash,
          AppColors.error,
          AppColors.tintRed
        ),
      _ => (
          PhosphorIconsRegular.pencilSimple,
          AppColors.blueBright,
          AppColors.blueSubtle
        ),
    };
    final when = e.at == null ? '' : relativeTime(e.at);
    final sub = [e.actor, when].where((s) => s.isNotEmpty).join(' · ');
    return AuditEntry(icon: icon, tone: tone, bg: bg, title: e.title, sub: sub);
  }

  /// The prototype's derived rows. Mock mode only — see [_auditLog].
  List<AuditEntry> _audit(OpsTask t, List<String> waitingOn) {
    final first =
        t.assignees.isEmpty ? '—' : MockUsers.of(t.assignees.first).name;
    final entries = <AuditEntry>[];
    if (t.status == 'completed') {
      entries.add(AuditEntry(
          icon: PhosphorIconsRegular.checkCircle,
          tone: AppColors.success,
          bg: AppColors.tintGreen,
          title: 'Completed by Manoj Varma',
          sub: t.actualEndFull ?? '18 Jun, 4:32 PM'));
    }
    if (waitingOn.isNotEmpty) {
      entries.add(AuditEntry(
          icon: PhosphorIconsRegular.linkSimple,
          tone: const Color(0xFFB45C00),
          bg: AppColors.tintAmber,
          title: 'Dependency added',
          sub: 'Waiting on ${waitingOn.join(', ')} · Anjana Menon · 14 Jun'));
    }
    entries.addAll([
      AuditEntry(
          icon: PhosphorIconsRegular.userPlus,
          tone: AppColors.pending,
          bg: AppColors.tintPurple,
          title: 'Assignee changed',
          sub: '$first added · Anjana Menon · 12 Jun'),
      AuditEntry(
          icon: PhosphorIconsRegular.arrowsClockwise,
          tone: AppColors.blueBright,
          bg: AppColors.blueSubtle,
          title: 'Status changed — Open → Working',
          sub: 'Manoj Varma · 10 Jun, 9:40 AM'),
      AuditEntry(
          icon: PhosphorIconsRegular.plusCircle,
          tone: AppColors.navy,
          bg: AppColors.tintNavy,
          title: 'Task created',
          sub: 'Anjana Menon · ${t.start}'),
    ]);
    return entries;
  }

  /// `PATCH /projects/tasks/{subtask_id}/ {"status": …}` (§3C).
  ///
  /// A tick can be refused: closing the last open subtask of a parent that
  /// still has open dependencies comes back as a `400`, and that message is the
  /// whole explanation.
  Future<void> _toggleSubtask(String taskId, int index) async {
    if (!_ensureCanEdit(taskId)) return;
    // Completing a subtask needs a note too (C14).
    final subs = ref.read(opsSubtasksProvider(taskId));
    if (index >= 0 && index < subs.length && !subs[index].done) {
      final s = subs[index];
      if (s.id.isNotEmpty &&
          !await ensureOpsClosingNote(context, ref,
              taskId: s.id, title: s.title)) {
        return;
      }
      if (!mounted) return;
    }
    final err =
        await ref.read(opsSubtasksProvider(taskId).notifier).toggle(index);
    if (!mounted || err == null) return;
    ref.read(toastProvider.notifier).showError(err);
  }

  Widget _subChip(IconData icon, String label,
      {required bool active, VoidCallback? onTap, VoidCallback? onClear}) {
    final c = onTap == null
        ? AppColors.textPlaceholder
        : (active ? AppColors.navy : AppColors.textMuted);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 5.h),
        decoration: BoxDecoration(
          color: active ? AppColors.tintBlue : AppColors.bgChipGrey,
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13.sp, color: c),
          SizedBox(width: 5.w),
          Text(label,
              style:
                  AppText.custom(size: 12, weight: FontWeight.w600, color: c)),
          if (onClear != null) ...[
            SizedBox(width: 4.w),
            GestureDetector(
              onTap: onClear,
              child: Icon(PhosphorIconsBold.x,
                  size: 11.sp, color: AppColors.textMuted),
            ),
          ],
        ]),
      ),
    );
  }

  Future<void> _pickSubAssignee() async {
    List<CatalogOption> users;
    try {
      users =
          await ref.read(opsAssignableUsersProvider('project_task').future) ??
              const [];
    } on Object {
      users = const [];
    }
    if (!mounted) return;
    final picked = await showOpsOptionPicker(
      context: context,
      title: 'Assign subtask to',
      options: [
        (value: '', label: "Parent's assignee"),
        for (final u in users) (value: u.id, label: u.name),
      ],
      currentValue: _subAssignee ?? '',
      searchHint: 'Search people',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _subAssignee = picked.isEmpty ? null : picked;
      _subAssigneeName = picked.isEmpty
          ? null
          : users.where((u) => u.id == picked).firstOrNull?.name;
    });
  }

  /// `POST /projects/tasks/` with `parent_task` (§3C) — plus the picked due
  /// date / time and assignee (C13). The server copies project, group, type
  /// and assignee from the parent (C15); a due outside the parent's window is
  /// refused here first, in the web's words. Cleared only once the write
  /// lands, so a refusal keeps what was typed.
  Future<void> _addSubtask(String taskId) async {
    final text = _subCtrl.text.trim();
    if (text.isEmpty) return;
    if (!ensurePermission(ref, 'project_task', PermVerb.create) ||
        !_ensureCanEdit(taskId)) return;
    String? endIso;
    if (_subDate != null) {
      final d = _subDate!;
      final t = _subTime ?? const TimeOfDay(hour: 0, minute: 0);
      final parent = ref.read(opsTaskDetailOrListProvider(taskId));
      final window = subtaskWindowError(
          DateTime(d.year, d.month, d.day, t.hour, t.minute),
          parentStartIso: parent?.startISO,
          parentEndIso: parent?.endISO);
      if (window != null) {
        ref.read(toastProvider.notifier).showError(window);
        return;
      }
      endIso = opsTaskEndStampAt(d, _subTime);
    }
    final assignee = UserDirectory.realUserId(_subAssignee);
    final err = await ref
        .read(opsSubtasksProvider(taskId).notifier)
        .add(text, endIso: endIso, assigneeId: assignee);
    if (!mounted) return;
    if (err != null) {
      ref.read(toastProvider.notifier).showError(err);
      return;
    }
    _subCtrl.clear();
    setState(() {
      _subDate = null;
      _subTime = null;
      _subAssignee = null;
      _subAssigneeName = null;
    });
  }

  /// The original's assignees as real user ids, or null when none survive —
  /// `'me'` is a UI sentinel and prototype seed ids must never reach the API.
  List<String>? _copyableAssignees(OpsTask t) {
    final out = [
      for (final id in t.assignees)
        if (UserDirectory.realUserId(id) case final real?) real,
    ];
    return out.isEmpty ? null : out;
  }

  /// Copies the task with a fresh subject.
  ///
  /// There is no duplicate endpoint — it is a plain `POST /projects/tasks/` of
  /// the same field set. Deliberately *not* copied: the dependency edges,
  /// subtasks and progress, which belong to the original's own history. The
  /// copy opens for editing rather than being filed silently.
  Future<void> _duplicate(OpsTask t) async {
    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show('Task duplicated');
      return;
    }
    try {
      final created = await ref.read(opsTasksRepositoryProvider).createOpsTask({
        'subject': '${t.subject} (copy)',
        if (t.projId.isNotEmpty) 'project': t.projId,
        if (t.groupId.isNotEmpty) 'task_group': t.groupId,
        if (t.typeId.isNotEmpty) 'type': t.typeId,
        'priority': t.pri,
        'description': t.desc,
        'is_milestone': t.milestone,
        if (t.dept.isNotEmpty) 'department': t.dept,
        // Status is left out on purpose: a copy starts at the org's default
        // rather than inheriting "Completed" from the task it came from.
        if (_copyableAssignees(t) case final a?) 'assignees': a,
        if (t.endISO.isNotEmpty) 'exp_end_date': t.endISO,
      });
      if (!mounted) return;
      ref.invalidate(opsTasksProvider);
      ref.invalidate(opsTasksScopedProvider);
      ref.read(toastProvider.notifier).show('Task duplicated');
      if (created != null) context.push('${Routes.editTask}?id=${created.id}');
    } on AppError catch (e) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).showError(e.message);
    }
  }

  /// `DELETE /projects/tasks/{id}/`, behind a confirm.
  Future<void> _delete(OpsTask t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this task?'),
        content: Text('This permanently removes "${t.subject}". Remove its '
            "dependencies and subtasks first if it's blocking others."),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show('Task deleted');
      context.pop();
      return;
    }
    try {
      // Its files go too (UI/UX audit #09 — the server keeps them).
      await deleteRecordWithFiles(ref.read(attachmentsRepositoryProvider),
          relatedTo: 'project_task',
          recordId: t.id,
          deleteRecord: () =>
              ref.read(opsTasksRepositoryProvider).deleteOpsTask(t.id));
      if (!mounted) return;
      ref.invalidate(opsTasksProvider);
      ref.invalidate(opsTasksScopedProvider);
      ref.read(toastProvider.notifier).show('Task deleted');
      // Back to where the task was opened from — or the Tasks list when it
      // was opened directly, instead of sitting on "Task not found".
      context.canPop() ? context.pop() : context.go(Routes.opsTasks);
    } on AppError catch (e) {
      if (!mounted) return;
      // A 409 names the tasks depending on this one. The menu already disables
      // delete for blockers it can see, but the server sees edges this screen
      // does not — so the message still has to land.
      ref.read(toastProvider.notifier).showError(e.message);
    }
  }

  /// `GET/POST /crm/notes/` with `related_to=project_task`.
  ///
  /// This used to be an in-memory store seeded from the record's mock notes, so
  /// nothing typed here ever left the device.
  ///
  /// Note the discriminator: `project_task` is the PMO task, `task` is the CRM
  /// interactions task — a different resource. Both models are named "task"
  /// underneath, so the wrong value quietly returns the wrong thread.
  Widget _notes(String taskId) {
    final seed = CrmNotesSeed(taskId, () => const <NoteEntry>[],
        apiModel: 'project_task');
    final notes = ref.read(crmNotesProvider(seed).notifier);
    return NotesThread(
      key: _notesKey,
      author: ref.watch(noteAuthorProvider),
      notes: ref.watch(crmNotesProvider(seed)),
      onAddNote: (body, atts) =>
          notes.addNote(body, atts, ref.read(noteAuthorProvider)),
      onAddReply: (noteId, body) =>
          notes.addReply(noteId, body, ref.read(noteAuthorProvider)),
      // Webapp NotesPanel (related_to=project_task): Tag · @mention ·
      // Insert, author-only pin / edit / delete.
      webappToolbar: true,
      noteTypes: ref.watch(noteTypesProvider).valueOrNull ?? const [],
      // @mention: the module's assignable users, as the webapp's source for
      // `project_task` notes (a role without access gets none → no picker).
      mentionables: [
        for (final u in ref
                .watch(opsAssignableUsersProvider('project_task'))
                .valueOrNull ??
            const <CatalogOption>[])
          (id: UserDirectory.realUserId(u.id) ?? u.id, name: u.name),
      ],
      currentUserId: UserDirectory.currentUserId,
      onAddTypedNote: (body, atts, typeId, typeName, mentions) => notes.addNote(
          body, atts, ref.read(noteAuthorProvider),
          noteTypeId: typeId,
          noteTypeName: typeName,
          mentionedUserIds: mentions,
          authorId: UserDirectory.currentUserId),
      onTogglePin: (id) => notes.togglePin(id),
      onEditNote: (id, body) => notes.editNote(id, body),
      onDeleteNote: (id) => notes.deleteNote(id),
    );
  }

  Future<void> _openMenu() async {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final task = ref.read(opsTaskDetailOrListProvider(id));
    if (task == null) return;
    final status = _status ?? task.status;
    final locked = status == 'completed' || status == 'cancelled';
    final all = ref.read(opsTasksListProvider);
    final wait = _waitingOn ?? task.waitingOn;
    final hasUnresolvedDep = wait.any((wid) {
      final wt = all.where((x) => x.id == wid).firstOrNull;
      return wt != null && wt.status != 'completed' && wt.status != 'cancelled';
    });
    final blockedDel = hasUnresolvedDep ||
        ref.read(opsSubtasksProvider(id)).any((s) => !s.done);
    // Webapp gates: the module's verbs, narrowed by the record's own
    // `can_update` / `can_delete` (a view-only record).
    final modUpdate = hasPermission(ref, 'project_task', PermVerb.update);
    final canEdit = modUpdate && task.canUpdate != false;
    final editReason =
        modUpdate ? _viewOnlyCopy : permissionCopy(PermVerb.update);
    final canCreate = hasPermission(ref, 'project_task', PermVerb.create);
    final modDelete = hasPermission(ref, 'project_task', PermVerb.delete);
    final canDelete = modDelete && task.canDelete != false;

    await showActionMenu(
      context,
      title: task.subject,
      actions: [
        MenuAction(
          icon: PhosphorIconsRegular.pencilSimple,
          label: 'Edit task',
          enabled: !locked && canEdit,
          sublabel: locked
              ? 'Locked while $status'
              : canEdit
                  ? null
                  : editReason,
          onTap: () => context.push('${Routes.editTask}?id=${task.id}'),
        ),
        MenuAction(
          icon: PhosphorIconsRegular.arrowsClockwise,
          label: 'Change status',
          enabled: canEdit,
          sublabel: canEdit ? null : editReason,
          onTap: _openStatusSheet,
        ),
        MenuAction(
          icon: PhosphorIconsRegular.notePencil,
          label: 'Add note',
          onTap: () => _notesKey.currentState?.focusComposer(),
        ),
        MenuAction(
          icon: PhosphorIconsRegular.copy,
          label: 'Duplicate task',
          enabled: canCreate,
          sublabel: canCreate ? null : permissionCopy(PermVerb.create),
          onTap: () => _duplicate(task),
        ),
        MenuAction(
          icon: PhosphorIconsRegular.trash,
          label: 'Delete task',
          destructive: true,
          enabled: canDelete && !blockedDel,
          sublabel: !canDelete
              ? (modDelete ? _viewOnlyCopy : permissionCopy(PermVerb.delete))
              : blockedDel
                  ? 'Resolve subtasks & dependencies first'
                  : null,
          onTap: () => _delete(task),
        ),
      ],
    );
  }

  /// `PATCH /projects/tasks/{id}/ {"status": "<uuid>"}`.
  ///
  /// This used to offer the built-in vocabulary and only set local state, so
  /// the pill changed on screen and the server never heard about it.
  ///
  /// Changing status is the one edit a closed task always accepts — it *is* the
  /// reopen (§3A) — so this stays enabled while Edit is locked.
  /// "Mark complete" (UI/UX audit #15 — CRM Task has it, Ops had only the
  /// status sheet): the org's first completed status.
  Future<void> _markComplete(OpsTask task) async {
    if (!_ensureCanEdit(task.id)) return;
    await ref.read(opsTaskStatusCatalogProvider.future);
    if (!mounted) return;
    final catalog = ref.read(opsTaskStatusOptionsProvider);
    final done = catalog
        .where((s) => opsTaskStatusKey(name: s.name) == 'completed')
        .firstOrNull;
    final name = done?.name ?? (catalog.isEmpty ? 'completed' : null);
    if (name == null) {
      ref
          .read(toastProvider.notifier)
          .showError("Your organisation has no completed status for tasks");
      return;
    }
    await _applyStatus(task, name, success: 'Task marked complete');
  }

  Future<void> _openStatusSheet() async {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final task = ref.read(opsTaskDetailOrListProvider(id));
    if (task == null) return;
    if (!_ensureCanEdit(task.id)) return;

    // Wait for the catalog before opening. `read` alone returned whatever was
    // cached — which on a detail screen reached directly is nothing, so every
    // pick then failed to resolve to an id.
    await ref.read(opsTaskStatusCatalogProvider.future);
    if (!mounted) return;

    // The org's own statuses, keyed **and labelled** by their own name; the
    // built-ins only stand in in mock mode. Borrowing the built-in `label` here
    // meant the sheet listed "Open"/"Working" while returning the org's names.
    final catalog = ref.read(opsTaskStatusOptionsProvider);
    final statuses = <String, StatusMeta>{
      if (catalog.isEmpty)
        ...StatusMeta$.opsTask
      else
        for (final s in catalog)
          s.name: StatusMeta(
            s.name,
            s.color ??
                (StatusMeta$.opsTask[opsTaskStatusKey(name: s.name)] ??
                        StatusMeta$.opsTask['open']!)
                    .color,
          ),
    };
    final current = _statusName ??
        (task.statusName.isNotEmpty ? task.statusName : task.status);

    final chosen = await showOpsStatusPicker(
      context: context,
      title: 'Task status',
      statuses: statuses,
      // Matched case-insensitively: the stored value may be the folded key
      // ('open') while the catalog keys are the org's names ('Open').
      currentKey: statuses.keys.firstWhere(
        (k) => k.toLowerCase() == current.trim().toLowerCase(),
        orElse: () => current,
      ),
    );
    if (chosen == null || !mounted) return;
    await _applyStatus(task, chosen);
  }

  /// Moves [task] to the org status named [chosen] (approval / blocker rules
  /// included). Shared by the status sheet and "Mark complete".
  Future<void> _applyStatus(OpsTask task, String chosen,
      {String success = 'Status updated'}) async {
    final catalog = ref.read(opsTaskStatusOptionsProvider);
    // The pill and the lock read the folded key; the picker and the write use
    // the org's name. Keep both in step.
    void applyLocally() => setState(() {
          _statusName = chosen;
          _status = catalog.isEmpty ? chosen : opsTaskStatusKey(name: chosen);
        });

    if (!ApiConfig.apiEnabled) {
      applyLocally();
      return;
    }
    final target = catalog
        .where(
            (s) => s.name.trim().toLowerCase() == chosen.trim().toLowerCase())
        .firstOrNull;
    final statusId = target?.id;
    if (statusId == null) {
      // No id to send. Better to say so than to move the pill and drop the
      // write — and name the actual cause, which is almost always that the
      // org's status list never loaded.
      ref.read(toastProvider.notifier).showError(catalog.isEmpty
          ? "Couldn't load your organisation's task statuses"
          : "Couldn't match “$chosen” to a status");
      return;
    }
    // Completing (not cancelling) needs a note first, unless the org allows
    // closing without remarks (webapp parity C14) — then the approval step.
    if (target!.isClosed &&
        !target.isCancelled &&
        !await ensureOpsClosingNote(context, ref,
            taskId: task.id, title: task.subject)) {
      return;
    }
    if (!mounted) return;
    // Closing (or cancelling, as the org gates it) may need approval.
    final requestNote = await approvalNoteForClose(context, ref,
        module: ApprovalModules.projectTask,
        objectId: task.id,
        statusCode: projectTaskCloseCode(target),
        statusLabel: chosen);
    if (requestNote == null || !mounted) return;
    try {
      final held = await writeWasHeld(
          ref,
          task.id,
          () => ref.read(opsTasksRepositoryProvider).updateOpsTask(
              task.id, {'status': statusId, ...requestNoteField(requestNote)}));
      if (!mounted) return;
      // Held for approval: the task keeps its status; the shell says so.
      if (!held) applyLocally();
      ref.invalidate(opsTaskDetailProvider(task.id));
      ref.invalidate(opsTasksProvider);
      ref.invalidate(opsTasksScopedProvider);
      if (!held) ref.read(toastProvider.notifier).show(success);
    } on AppError catch (e) {
      if (!mounted) return;
      // Completing is refused while subtasks or dependencies are still open,
      // and the 400 names the blockers — that message is the whole explanation.
      ref.read(toastProvider.notifier).showError(e.message);
    }
  }
}

extension _IfEmpty on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
