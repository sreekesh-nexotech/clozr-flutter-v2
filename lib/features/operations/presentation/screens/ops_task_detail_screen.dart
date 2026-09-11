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
import '../../../../core/utils/relative_time.dart';
import '../../../../data/api/status_keys.dart';
import '../../../../data/api/user_directory.dart';
import '../../../crm/application/providers/crm_notes_providers.dart';
import '../../../crm/domain/entities/audit_entry.dart' hide AuditEntry;
import '../../../crm/domain/entities/audit_entry.dart' as crm_audit show AuditEntry;
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/notes_thread.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
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
  ConsumerState<OpsTaskDetailScreen> createState() => _OpsTaskDetailScreenState();
}

class _OpsTaskDetailScreenState extends ConsumerState<OpsTaskDetailScreen> {
  /// Local override of the folded status key — what drives the pill colour and
  /// the completed-lock. [_statusName] is the org's own name for the same
  /// choice, which is what the picker and the write need.
  String? _status;
  String? _statusName;
  List<String>? _waitingOn;
  final _subCtrl = TextEditingController();
  final _notesKey = GlobalKey<NotesThreadState>();

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
    final gate = task != null
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
              onRetry: () => ref.invalidate(opsTasksProvider),
              onRefresh: () => _refresh(id),
              loading: () => const DetailSkeleton(),
              data: (_) {
                if (task == null) {
                  return const EmptyState(
                    icon: PhosphorIconsRegular.listChecks,
                    title: 'Task not found',
                    body: 'This task may have been removed, or you may not have access to it.',
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
                if (_waitingOn == null &&
                    ref.watch(opsTaskDetailProvider(id)).valueOrNull != null) {
                  _waitingOn = List.of(task.waitingOn);
                }
                final waitingOn = _waitingOn ?? task.waitingOn;
                final status = _status ?? task.status;

                final meta = StatusMeta$.opsTask[status] ?? StatusMeta$.opsTask['open']!;
                final priColor = StatusMeta$.projectPriority[task.pri] ?? AppColors.textMuted;
                final locked = status == 'completed' || status == 'cancelled';
                final project = projects.where((p) => p.id == task.projId).firstOrNull;
                final overdue = isTaskOverdue(task);
                final progress = task.computedProgress(subtasks);

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 40.h),
                  children: [
                    _summaryCard(task, meta, priColor, project?.name ?? '—', overdue),
                    if (locked) ...[SizedBox(height: 14.h), _lockBanner(status)],
                    SizedBox(height: 14.h),
                    _detailsCard(task, meta, progress, locked),
                    SizedBox(height: 14.h),
                    _subtasksCard(task, subtasks, locked),
                    if (!locked || _hasDeps(task, waitingOn, allTasks)) ...[
                      SizedBox(height: 14.h),
                      _depsCard(task, waitingOn, allTasks, locked),
                    ],
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

  Widget _summaryCard(OpsTask t, StatusMeta meta, Color priColor, String projName, bool overdue) {
    final ids = t.assignees.take(2).toList();
    final more = t.assignees.length - ids.length;
    final names = t.assignees.map((id) => MockUsers.of(id).firstName).join(', ').ifEmpty('—');
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (t.milestone)
                          Padding(
                            padding: EdgeInsets.only(top: 2.h, right: 7.w),
                            child: Icon(PhosphorIconsFill.flag, size: 16.sp, color: AppColors.warningDeep),
                          ),
                        Expanded(
                          child: Text(t.subject, style: AppText.custom(size: 18, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                        ),
                      ],
                    ),
                    SizedBox(height: 4.h),
                    GestureDetector(
                      onTap: () {
                        if (t.projId.isNotEmpty) context.push('${Routes.projectDetail}?id=${t.projId}');
                      },
                      child: Text('$projName › ${t.group}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.blueBright)),
                    ),
                    if (t.hasFromTicket) ...[
                      SizedBox(height: 8.h),
                      GestureDetector(
                        onTap: () => ref.read(toastProvider.notifier).show('Open ${t.fromTicket}'),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                          decoration: BoxDecoration(color: AppColors.blueSubtle, borderRadius: BorderRadius.circular(8.r)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(PhosphorIconsFill.ticket, size: 12.sp, color: AppColors.blueBright),
                              SizedBox(width: 6.w),
                              Text('From ticket ${t.fromTicket}', style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.blueBright)),
                              SizedBox(width: 6.w),
                              Icon(PhosphorIconsBold.arrowRight, size: 10.sp, color: AppColors.blueBright),
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
                  GestureDetector(onTap: _openStatusSheet, child: StatusPill.meta(meta)),
                  SizedBox(height: 5.h),
                  StatusPill(label: t.pri, color: priColor),
                ],
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 14)),
          Row(
            children: [
              AvatarStack(size: 28, overlap: 7, items: [for (final id in ids) (MockUsers.of(id).initials, AppColors.navy)]),
              if (more > 0) ...[
                SizedBox(width: 5.w),
                Text('+$more', style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textMuted2)),
              ],
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(names, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 1.h),
                    Text('Assignees', style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Icon(PhosphorIconsRegular.calendarBlank, size: 15.sp, color: AppColors.textPlaceholder),
              SizedBox(width: 7.w),
              Text('Due ${t.end.replaceAll(' 2026', '')}${t.endTime.isNotEmpty ? ' · ${t.endTime}' : ''}',
                  style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
              if (overdue) ...[
                const Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(color: AppColors.tintRed, borderRadius: BorderRadius.circular(7.r)),
                  child: Text('Overdue', style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.error)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
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
          Icon(completed ? PhosphorIconsFill.sealCheck : PhosphorIconsFill.prohibit,
              size: 18.sp, color: completed ? AppColors.success : AppColors.textMuted2),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This task is $status — fields are locked.',
                    style: AppText.custom(size: 13, weight: FontWeight.w700, color: completed ? AppColors.success : AppColors.textLabelAlt)),
                SizedBox(height: 2.h),
                Text('Status and notes stay editable.', style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailsCard(OpsTask t, StatusMeta meta, int progress, bool locked) {
    final valueColor = locked ? AppColors.textPlaceholder : AppColors.textPrimary;
    final rows = <(String, String)>[
      // `task_code` ("PRJ-1010-t3"), display-only and stable. Absent on a
      // standalone task and on the slim list row, so the row waits for the
      // retrieve rather than showing the UUID.
      if (t.code.isNotEmpty) ('Task ID', t.code),
      ('Expected start', '${t.start.replaceAll(' 2026', '')}${t.startTime.isNotEmpty ? ' · ${t.startTime}' : ''}'),
      ('Expected end', '${t.end.replaceAll(' 2026', '')}${t.endTime.isNotEmpty ? ' · ${t.endTime}' : ''}'),
      // Detail-only decimals, so both wait for the retrieve rather than
      // printing the "0 hrs" / "1" the mapper used to hardcode.
      if (t.expHrs != null) ('Expected time', '${opsDecimalLabel(t.expHrs!)} hrs'),
      if (t.weight != null) ('Task weight', opsDecimalLabel(t.weight!)),
      ('Milestone', t.milestone ? 'Yes' : 'No'),
      ('Department', t.dept),
    ];
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Details', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          Padding(
            padding: EdgeInsets.fromLTRB(2.w, 12.h, 2.w, 4.h),
            child: Text(t.desc, style: AppText.custom(size: 14, weight: FontWeight.w500, color: locked ? AppColors.textPlaceholder : AppColors.textLabelAlt, height: 1.6)),
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
              Text('$progress%', style: AppText.custom(size: 13, weight: FontWeight.w800, color: AppColors.textPrimary)),
            ],
          ),
          if (t.progress == null) ...[
            SizedBox(height: 4.h),
            Text('Calculated from subtasks', style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
          ],
          // Only when the record actually carries one of them — a completed
          // task whose dates were never stamped would otherwise read
          // "started — · completed —".
          if (t.status == 'completed' && (t.actualStart != null || t.actualEnd != null)) ...[
            SizedBox(height: 4.h),
            Text('Actual: started ${t.actualStart ?? '—'} · completed ${t.actualEnd ?? '—'}',
                style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
          ],
          SizedBox(height: 6.h),
          for (final r in rows)
            Container(
              padding: EdgeInsets.symmetric(vertical: 10.h),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.$1, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                  SizedBox(width: 14.w),
                  Expanded(child: Text(r.$2, textAlign: TextAlign.right, style: AppText.custom(size: 14, weight: FontWeight.w700, color: valueColor))),
                ],
              ),
            ),
          if (!locked)
            GestureDetector(
              onTap: () => context.push('${Routes.editTask}?id=${t.id}'),
              child: Container(
                height: 44.h,
                margin: EdgeInsets.only(top: 14.h),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: const Color(0xFFE6E7EA), width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsRegular.pencilSimple, size: 15.sp, color: AppColors.textSecondary),
                    SizedBox(width: 7.w),
                    Text('Edit task', style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _subtasksCard(OpsTask t, List<Subtask> subs, bool locked) {
    final taskId = t.id;
    // The child rows are their own fetch (§3C), so until they land the record's
    // own `subtask_done_count` / `subtask_count` are what the counter has —
    // showing "0/0 done" on a task the server says has five would be wrong.
    final done = subs.isEmpty ? t.subtaskDoneCount : subs.where((s) => s.done).length;
    final total = subs.isEmpty ? t.subtaskCount : subs.length;
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.listChecks, size: 16.sp, color: AppColors.textLabelAlt),
              SizedBox(width: 7.w),
              Text('Subtasks', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
              const Spacer(),
              if (total > 0)
                Text('$done/$total done', style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textMuted)),
            ],
          ),
          for (int i = 0; i < subs.length; i++) _subtaskRow(taskId, i, subs[i], locked),
          if (!locked) ...[
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
                      style: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textBody),
                      cursorColor: AppColors.blueBright,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addSubtask(taskId),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '+ Add subtask',
                        hintStyle: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textPlaceholder),
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
                    decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(11.r)),
                    child: Icon(PhosphorIconsBold.plus, size: 16.sp, color: AppColors.white),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _subtaskRow(String taskId, int index, Subtask s, bool locked) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('${Routes.opsSubtask}?taskId=$taskId&i=$index'),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 11.h),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
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
                  border: s.done ? null : Border.all(color: const Color(0xFFC9CCD2), width: 1.5),
                ),
                child: Icon(PhosphorIconsBold.check, size: 13.sp, color: s.done ? AppColors.white : Colors.transparent),
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
                      color: s.done ? AppColors.textPlaceholder : AppColors.textBody,
                      decoration: s.done ? TextDecoration.lineThrough : null)),
            ),
            if (s.due.isNotEmpty) ...[
              SizedBox(width: 8.w),
              Text(s.due, style: AppText.custom(size: 11, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
            ],
            SizedBox(width: 8.w),
            // Unassigned subtasks are ordinary — the avatar is dropped rather
            // than drawn as an "Unknown" placeholder.
            if (s.who.isNotEmpty) ...[
              Container(
                width: 24.w,
                height: 24.w,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
                child: Text(MockUsers.of(s.who).initials, style: AppText.custom(size: 8.5, weight: FontWeight.w700, color: AppColors.white)),
              ),
              SizedBox(width: 6.w),
            ],
            Icon(PhosphorIconsRegular.caretRight, size: 13.sp, color: AppColors.textPlaceholder),
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
      ref.read(toastProvider.notifier).showError(e.message);
    }
  }

  /// `POST /projects/task-dependencies/`. Picks the blocker from the org's
  /// tasks, minus this task and the ones it already waits on.
  Future<void> _addDep(OpsTask t, List<String> waitingOn, List<OpsTask> all) async {
    final taken = {t.id, ...waitingOn};
    final options = [
      for (final x in all)
        if (!taken.contains(x.id)) (value: x.id, label: x.subject),
    ];
    if (options.isEmpty) {
      ref.read(toastProvider.notifier).show('No other tasks to depend on');
      return;
    }
    final chosen = await showOpsOptionPicker(
      context: context,
      title: 'Waiting on',
      options: options,
      currentValue: '',
    );
    if (chosen == null || !mounted) return;

    if (!ApiConfig.apiEnabled) {
      setState(() => _waitingOn = [...waitingOn, chosen]);
      return;
    }
    try {
      await ref.read(opsTasksRepositoryProvider).addDependency(taskId: t.id, dependsOn: chosen);
      if (!mounted) return;
      _refreshDeps(t.id);
      ref.read(toastProvider.notifier).show('Dependency added');
    } on AppError catch (e) {
      if (!mounted) return;
      // A cycle, a duplicate or a cross-project blocker all land here, and the
      // backend's message is the only thing that says which.
      ref.read(toastProvider.notifier).showError(e.message);
    }
  }

  bool _hasDeps(OpsTask t, List<String> waitingOn, List<OpsTask> all) {
    if (waitingOn.isNotEmpty || t.blocking.isNotEmpty) return true;
    return all.any((x) => x.waitingOn.contains(t.id));
  }

  Widget _depsCard(OpsTask t, List<String> waitingOn, List<OpsTask> all, bool locked) {
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
      final label = edge?.subject.isNotEmpty == true ? edge!.subject : (wt?.subject ?? id);
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
              Icon(PhosphorIconsRegular.linkSimple, size: 16.sp, color: AppColors.textLabelAlt),
              SizedBox(width: 7.w),
              Text('Dependencies', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          if (showWait) ...[
            _depSectionLabel('Waiting on'),
            Wrap(
              spacing: 7.w,
              runSpacing: 7.h,
              children: [
                ...waitChips,
                if (!locked)
                  GestureDetector(
                    onTap: () => _addDep(t, waitingOn, all),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 11.w, vertical: 7.h),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(9.r),
                        border: Border.all(color: const Color(0xFFC9CCD2), width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsBold.plus, size: 11.sp, color: AppColors.textSecondary),
                          SizedBox(width: 5.w),
                          Text('Add', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textSecondary)),
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
                  _depChip(label: b.subject, unres: false, blocking: true, onOpen: () => context.push('${Routes.opsTaskDetail}?id=${b.id}')),
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
            style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.6)),
      );

  Widget _depChip({required String label, required bool unres, bool blocking = false, VoidCallback? onOpen, VoidCallback? onRemove}) {
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
                  : (unres ? PhosphorIconsFill.clock : PhosphorIconsFill.checkCircle),
              size: 12.sp,
              color: blocking ? AppColors.textMuted2 : (unres ? const Color(0xFFB45C00) : AppColors.success),
            ),
            SizedBox(width: 6.w),
            Text(label, style: AppText.custom(size: 12, weight: FontWeight.w600, color: blocking ? AppColors.textLabelAlt : fg)),
            if (onRemove != null) ...[
              SizedBox(width: 6.w),
              GestureDetector(
                onTap: onRemove,
                child: Icon(PhosphorIconsBold.x, size: 11.sp, color: AppColors.textPlaceholder),
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
    final entries = ref.watch(opsTaskActivityProvider(t.id)).valueOrNull ?? const [];
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
      AuditEventKind.created => (PhosphorIconsRegular.plusCircle, AppColors.navy, AppColors.tintNavy),
      AuditEventKind.statusChanged => (PhosphorIconsRegular.arrowsClockwise, AppColors.blueBright, AppColors.blueSubtle),
      AuditEventKind.noteAdded => (PhosphorIconsRegular.note, AppColors.pending, AppColors.tintPurple),
      AuditEventKind.childAdded => (PhosphorIconsRegular.listChecks, AppColors.success, AppColors.tintGreen),
      AuditEventKind.deleted => (PhosphorIconsRegular.trash, AppColors.error, AppColors.tintRed),
      _ => (PhosphorIconsRegular.pencilSimple, AppColors.blueBright, AppColors.blueSubtle),
    };
    final when = e.at == null ? '' : relativeTime(e.at);
    final sub = [e.actor, when].where((s) => s.isNotEmpty).join(' · ');
    return AuditEntry(icon: icon, tone: tone, bg: bg, title: e.title, sub: sub);
  }

  /// The prototype's derived rows. Mock mode only — see [_auditLog].
  List<AuditEntry> _audit(OpsTask t, List<String> waitingOn) {
    final first = t.assignees.isEmpty ? '—' : MockUsers.of(t.assignees.first).name;
    final entries = <AuditEntry>[];
    if (t.status == 'completed') {
      entries.add(AuditEntry(icon: PhosphorIconsRegular.checkCircle, tone: AppColors.success, bg: AppColors.tintGreen, title: 'Completed by Manoj Varma', sub: t.actualEndFull ?? '18 Jun, 4:32 PM'));
    }
    if (waitingOn.isNotEmpty) {
      entries.add(AuditEntry(icon: PhosphorIconsRegular.linkSimple, tone: const Color(0xFFB45C00), bg: AppColors.tintAmber, title: 'Dependency added', sub: 'Waiting on ${waitingOn.join(', ')} · Anjana Menon · 14 Jun'));
    }
    entries.addAll([
      AuditEntry(icon: PhosphorIconsRegular.userPlus, tone: AppColors.pending, bg: AppColors.tintPurple, title: 'Assignee changed', sub: '$first added · Anjana Menon · 12 Jun'),
      AuditEntry(icon: PhosphorIconsRegular.arrowsClockwise, tone: AppColors.blueBright, bg: AppColors.blueSubtle, title: 'Status changed — Open → Working', sub: 'Manoj Varma · 10 Jun, 9:40 AM'),
      AuditEntry(icon: PhosphorIconsRegular.plusCircle, tone: AppColors.navy, bg: AppColors.tintNavy, title: 'Task created', sub: 'Anjana Menon · ${t.start}'),
    ]);
    return entries;
  }

  /// `PATCH /projects/tasks/{subtask_id}/ {"status": …}` (§3C).
  ///
  /// A tick can be refused: closing the last open subtask of a parent that
  /// still has open dependencies comes back as a `400`, and that message is the
  /// whole explanation.
  Future<void> _toggleSubtask(String taskId, int index) async {
    final err = await ref.read(opsSubtasksProvider(taskId).notifier).toggle(index);
    if (!mounted || err == null) return;
    ref.read(toastProvider.notifier).showError(err);
  }

  /// `POST /projects/tasks/` with `parent_task` (§3C). The field is cleared
  /// only once the write lands, so a refusal keeps what was typed.
  Future<void> _addSubtask(String taskId) async {
    final text = _subCtrl.text.trim();
    if (text.isEmpty) return;
    final err = await ref.read(opsSubtasksProvider(taskId).notifier).add(text);
    if (!mounted) return;
    if (err != null) {
      ref.read(toastProvider.notifier).showError(err);
      return;
    }
    _subCtrl.clear();
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
        title: const Text('Delete task?'),
        content: Text('"${t.subject}" will be removed for everyone. '
            'This cannot be undone.'),
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

    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show('Task deleted');
      context.pop();
      return;
    }
    try {
      await ref.read(opsTasksRepositoryProvider).deleteOpsTask(t.id);
      if (!mounted) return;
      ref.invalidate(opsTasksProvider);
      ref.invalidate(opsTasksScopedProvider);
      ref.read(toastProvider.notifier).show('Task deleted');
      context.pop();
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
    final seed = CrmNotesSeed(taskId, () => const <NoteEntry>[], apiModel: 'project_task');
    return NotesThread(
      key: _notesKey,
      author: ref.watch(noteAuthorProvider),
      notes: ref.watch(crmNotesProvider(seed)),
      onAddNote: (body, atts) =>
          ref.read(crmNotesProvider(seed).notifier).addNote(body, atts, ref.read(noteAuthorProvider)),
      onAddReply: (noteId, body) =>
          ref.read(crmNotesProvider(seed).notifier).addReply(noteId, body, ref.read(noteAuthorProvider)),
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
    final blockedDel = hasUnresolvedDep || ref.read(opsSubtasksProvider(id)).any((s) => !s.done);

    await showActionMenu(
      context,
      title: task.subject,
      actions: [
        MenuAction(
          icon: PhosphorIconsRegular.pencilSimple,
          label: 'Edit task',
          enabled: !locked,
          sublabel: locked ? 'Locked while $status' : null,
          onTap: () => context.push('${Routes.editTask}?id=${task.id}'),
        ),
        MenuAction(
          icon: PhosphorIconsRegular.arrowsClockwise,
          label: 'Change status',
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
          onTap: () => _duplicate(task),
        ),
        MenuAction(
          icon: PhosphorIconsRegular.trash,
          label: 'Delete task',
          destructive: true,
          enabled: !blockedDel,
          sublabel: blockedDel ? 'Resolve subtasks & dependencies first' : null,
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
  Future<void> _openStatusSheet() async {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final task = ref.read(opsTaskDetailOrListProvider(id));
    if (task == null) return;

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
            (StatusMeta$.opsTask[opsTaskStatusKey(name: s.name)] ??
                    StatusMeta$.opsTask['open']!)
                .color,
          ),
    };
    final current =
        _statusName ?? (task.statusName.isNotEmpty ? task.statusName : task.status);

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
    final statusId = catalog
        .where((s) => s.name.trim().toLowerCase() == chosen.trim().toLowerCase())
        .map((s) => s.id)
        .firstOrNull;
    if (statusId == null) {
      // No id to send. Better to say so than to move the pill and drop the
      // write — and name the actual cause, which is almost always that the
      // org's status list never loaded.
      ref.read(toastProvider.notifier).showError(catalog.isEmpty
          ? "Couldn't load your organisation's task statuses"
          : "Couldn't match “$chosen” to a status");
      return;
    }
    try {
      await ref.read(opsTasksRepositoryProvider).updateOpsTask(task.id, {'status': statusId});
      if (!mounted) return;
      applyLocally();
      ref.invalidate(opsTaskDetailProvider(task.id));
      ref.invalidate(opsTasksProvider);
      ref.invalidate(opsTasksScopedProvider);
      ref.read(toastProvider.notifier).show('Status updated');
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
