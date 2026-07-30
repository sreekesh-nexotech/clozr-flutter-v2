import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/notes_thread.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/ops_notes_providers.dart';
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
  String? _status;
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
    final task = ref.watch(opsTaskByIdProvider(id));
    final allTasks = ref.watch(opsTasksListProvider);
    final projects = ref.watch(projectsListProvider);

    if (task == null) {
      return Container(
        color: AppColors.bgScreen,
        child: Column(
          children: [
            _appBar('Task', null),
            const Expanded(child: Center(child: Text('Task not found'))),
          ],
        ),
      );
    }

    // Subtasks come from the shared provider so toggles stay in sync with the
    // standalone subtask page (#12). Dependencies remain a local working copy.
    final subtasks = ref.watch(opsSubtasksProvider(id));
    final waitingOn = _waitingOn ??= List.of(task.waitingOn);
    final status = _status ?? task.status;

    final meta = StatusMeta$.opsTask[status] ?? StatusMeta$.opsTask['open']!;
    final priColor = StatusMeta$.projectPriority[task.pri] ?? AppColors.textMuted;
    final locked = status == 'completed' || status == 'cancelled';
    final project = projects.where((p) => p.id == task.projId).firstOrNull;
    final overdue = isTaskOverdue(task);
    final progress = task.computedProgress(subtasks);

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          _appBar('Task', task.subject),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 40.h),
              children: [
                _summaryCard(task, meta, priColor, project?.name ?? '—', overdue),
                if (locked) ...[SizedBox(height: 14.h), _lockBanner(status)],
                SizedBox(height: 14.h),
                _detailsCard(task, meta, progress, locked),
                SizedBox(height: 14.h),
                _subtasksCard(task.id, subtasks, locked),
                if (!locked || _hasDeps(task, waitingOn, allTasks)) ...[
                  SizedBox(height: 14.h),
                  _depsCard(task, waitingOn, allTasks, locked),
                ],
                NotesThread(
                  key: _notesKey,
                  notes: ref.watch(opsNotesProvider(task.id)),
                  onAddNote: (body, atts) => ref.read(opsNotesProvider(task.id).notifier).addNote(body, atts),
                  onAddReply: (noteId, body) => ref.read(opsNotesProvider(task.id).notifier).addReply(noteId, body),
                ),
                SizedBox(height: 14.h),
                OpsAuditLog(entries: _audit(task, waitingOn)),
              ],
            ),
          ),
        ],
      ),
    );
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
      ('Expected start', '${t.start.replaceAll(' 2026', '')}${t.startTime.isNotEmpty ? ' · ${t.startTime}' : ''}'),
      ('Expected end', '${t.end.replaceAll(' 2026', '')}${t.endTime.isNotEmpty ? ' · ${t.endTime}' : ''}'),
      ('Expected time', '${t.expHrs} hrs'),
      ('Task weight', '${t.weight}'),
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
          if (t.status == 'completed') ...[
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

  Widget _subtasksCard(String taskId, List<Subtask> subs, bool locked) {
    final done = subs.where((s) => s.done).length;
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
              if (subs.isNotEmpty)
                Text('$done/${subs.length} done', style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textMuted)),
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

  Widget _subtaskRow(Subtask s, bool locked) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 11.h),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
      child: Row(
        children: [
          GestureDetector(
            onTap: locked ? null : () => setState(() => s.done = !s.done),
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
          Container(
            width: 24.w,
            height: 24.w,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
            child: Text(MockUsers.of(s.who).initials, style: AppText.custom(size: 8.5, weight: FontWeight.w700, color: AppColors.white)),
          ),
        ],
      ),
    );
  }

  bool _hasDeps(OpsTask t, List<String> waitingOn, List<OpsTask> all) {
    if (waitingOn.isNotEmpty) return true;
    return all.any((x) => x.waitingOn.contains(t.id));
  }

  Widget _depsCard(OpsTask t, List<String> waitingOn, List<OpsTask> all, bool locked) {
    final waitChips = <Widget>[];
    for (final id in waitingOn) {
      final wt = all.where((x) => x.id == id).firstOrNull;
      final unres = wt != null && wt.status != 'completed' && wt.status != 'cancelled';
      waitChips.add(_depChip(
        label: wt?.subject ?? id,
        unres: unres,
        onOpen: wt == null ? null : () => context.push('${Routes.opsTaskDetail}?id=${wt.id}'),
        onRemove: locked ? null : () => setState(() => waitingOn.remove(id)),
      ));
    }
    final blocking = all.where((x) => x.waitingOn.contains(t.id)).toList();
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
                    onTap: () => ref.read(toastProvider.notifier).show('Add a dependency'),
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

  void _addSubtask(List<Subtask> subs) {
    final text = _subCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      subs.add(Subtask(title: text, done: false, who: 'me', due: ''));
      _subCtrl.clear();
    });
  }

  Future<void> _openMenu() async {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final task = ref.read(opsTaskByIdProvider(id));
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
          onTap: () => ref.read(toastProvider.notifier).show('Duplicate task — coming soon'),
        ),
        MenuAction(
          icon: PhosphorIconsRegular.trash,
          label: 'Delete task',
          destructive: true,
          enabled: !blockedDel,
          sublabel: blockedDel ? 'Resolve subtasks & dependencies first' : null,
          onTap: () => ref.read(toastProvider.notifier).show('Delete task — coming soon'),
        ),
      ],
    );
  }

  Future<void> _openStatusSheet() async {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final task = ref.read(opsTaskByIdProvider(id));
    if (task == null) return;
    final chosen = await showOpsStatusPicker(
      context: context,
      title: 'Task status',
      statuses: StatusMeta$.opsTask,
      currentKey: _status ?? task.status,
    );
    if (chosen != null && mounted) setState(() => _status = chosen);
  }
}

extension _IfEmpty on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
