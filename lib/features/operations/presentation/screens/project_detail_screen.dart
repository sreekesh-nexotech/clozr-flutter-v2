import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/notes_thread.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/ops_notes_providers.dart';
import '../../application/providers/ops_tasks_providers.dart';
import '../../application/providers/projects_providers.dart';
import '../../domain/entities/ops_task.dart';
import '../../domain/entities/project.dart';
import '../components/ops_detail_widgets.dart';
import '../components/ops_widgets.dart';

/// Project detail — summary card with a tappable status pill, a Details/Tasks/
/// Files tab card, notes and an audit log.
class ProjectDetailScreen extends ConsumerStatefulWidget {
  const ProjectDetailScreen({super.key});

  @override
  ConsumerState<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  String _tab = 'details';
  String? _status;
  final Set<String> _closedGroups = {};
  final _notesKey = GlobalKey<NotesThreadState>();

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final project = ref.watch(projectByIdProvider(id));
    final tasks = ref.watch(opsTasksListProvider);

    if (project == null) {
      return Container(
        color: AppColors.bgScreen,
        child: Column(
          children: [
            _appBar('Project', null),
            const Expanded(child: Center(child: Text('Project not found'))),
          ],
        ),
      );
    }

    final status = _status ?? project.status;
    final meta = StatusMeta$.project[status] ?? StatusMeta$.project['planning']!;
    final priColor = StatusMeta$.projectPriority[project.pri] ?? AppColors.textMuted;
    final mgr = MockUsers.of(project.manager);
    final overdue = isProjectOverdue(project);
    final locked = status == 'completed' || status == 'cancelled';
    final projTasks = tasks.where((t) => t.projId == project.id).toList();

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          _appBar('Project', project.name),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 40.h),
              children: [
                _summaryCard(project, meta, priColor, mgr, overdue),
                if (locked) ...[SizedBox(height: 14.h), _lockBanner(status)],
                SizedBox(height: 14.h),
                _tabsCard(project, meta, projTasks, locked),
                NotesThread(
                  key: _notesKey,
                  notes: ref.watch(opsNotesProvider(project.id)),
                  onAddNote: (body, atts) => ref.read(opsNotesProvider(project.id).notifier).addNote(body, atts),
                  onAddReply: (noteId, body) => ref.read(opsNotesProvider(project.id).notifier).addReply(noteId, body),
                ),
                SizedBox(height: 14.h),
                OpsAuditLog(entries: _audit(project, meta, mgr.name)),
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

  Widget _summaryCard(Project p, StatusMeta meta, Color priColor, AppUser mgr, bool overdue) {
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
                    Text(p.name, style: AppText.custom(size: 18, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                    SizedBox(height: 3.h),
                    Text('${p.id} · ${p.type}', style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ],
                ),
              ),
              SizedBox(width: 12.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GestureDetector(onTap: _openStatusSheet, child: StatusPill.meta(meta)),
                  SizedBox(height: 5.h),
                  StatusPill(label: p.pri, color: priColor),
                ],
              ),
            ],
          ),
          SizedBox(height: 15.h),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4.r),
                  child: LinearProgressIndicator(
                    value: p.progress / 100,
                    minHeight: 8.h,
                    backgroundColor: const Color(0xFFEEF1F4),
                    valueColor: AlwaysStoppedAnimation(meta.color),
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Text('${p.progress}%', style: AppText.custom(size: 13, weight: FontWeight.w800, color: AppColors.textPrimary)),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 14)),
          Row(
            children: [
              Container(
                width: 34.w,
                height: 34.w,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
                child: Text(mgr.initials, style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.white)),
              ),
              SizedBox(width: 11.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mgr.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 1.h),
                    Text('Project manager', style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
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
              Text('${p.start} – ${p.end}', style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
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
                Text('This project is $status — fields are locked.',
                    style: AppText.custom(size: 13, weight: FontWeight.w700, color: completed ? AppColors.success : AppColors.textLabelAlt)),
                SizedBox(height: 2.h),
                Text('Reopen it from the web app to make changes.',
                    style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabsCard(Project p, StatusMeta meta, List<OpsTask> projTasks, bool locked) {
    const tabs = [('details', 'Details'), ('ptasks', 'Tasks'), ('pfiles', 'Files')];
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderCardSoft))),
            child: Row(
              children: [
                for (final (k, label) in tabs) ...[
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _tab = k),
                    child: Container(
                      padding: EdgeInsets.only(bottom: 12.h),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: _tab == k ? AppColors.navy : Colors.transparent, width: 2.5)),
                      ),
                      child: Text(label,
                          style: AppText.custom(size: 14, weight: _tab == k ? FontWeight.w700 : FontWeight.w500, color: _tab == k ? AppColors.navy : AppColors.textPlaceholder)),
                    ),
                  ),
                  SizedBox(width: 22.w),
                ],
              ],
            ),
          ),
          SizedBox(height: 4.h),
          if (_tab == 'details') _detailsTab(p, locked),
          if (_tab == 'ptasks') _tasksTab(projTasks),
          if (_tab == 'pfiles') _filesTab(),
        ],
      ),
    );
  }

  Widget _detailsTab(Project p, bool locked) {
    final mgr = MockUsers.of(p.manager);
    final rows = <(String, String)>[
      ('Customer', p.internal ? 'Internal project' : (p.company ?? '—')),
      ('Project type', p.type),
      ('Visibility', p.visibility),
      ('Progress method', p.method),
      ('Estimated cost', p.cost),
      ('Assigned team', mgr.team.isNotEmpty ? mgr.team : 'Team Kochi'),
      ('Assignees', p.assignees.map((id) => MockUsers.of(id).firstName).join(', ').ifEmpty('—')),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(2.w, 12.h, 2.w, 4.h),
          child: Text(p.desc, style: AppText.custom(size: 14, weight: FontWeight.w500, color: AppColors.textLabelAlt, height: 1.6)),
        ),
        if (!locked)
          GestureDetector(
            onTap: () => context.push('${Routes.editProject}?id=${p.id}'),
            child: Container(
              height: 44.h,
              margin: EdgeInsets.symmetric(vertical: 12.h),
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
                  Text('Edit project', style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        for (final r in rows)
          Container(
            padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 2.w),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.$1, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                SizedBox(width: 14.w),
                Expanded(
                  child: Text(r.$2,
                      textAlign: TextAlign.right,
                      style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _tasksTab(List<OpsTask> projTasks) {
    if (projTasks.isEmpty) {
      return _tabEmpty(PhosphorIconsRegular.listChecks, 'No tasks yet',
          'Tasks created for this project will appear here, grouped by stage.');
    }
    final groups = <String, List<OpsTask>>{};
    for (final t in projTasks) {
      groups.putIfAbsent(t.group, () => []).add(t);
    }
    return Padding(
      padding: EdgeInsets.only(top: 6.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in groups.entries) ...[
            _groupHeader(entry.key, entry.value),
            if (!_closedGroups.contains(entry.key))
              for (final t in entry.value) _groupTaskRow(t),
          ],
        ],
      ),
    );
  }

  Widget _groupHeader(String name, List<OpsTask> arr) {
    final open = !_closedGroups.contains(name);
    final done = arr.where((t) => t.status == 'completed').length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        if (open) {
          _closedGroups.add(name);
        } else {
          _closedGroups.remove(name);
        }
      }),
      child: Container(
        padding: EdgeInsets.fromLTRB(2.w, 12.h, 2.w, 10.h),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
        child: Row(
          children: [
            Icon(open ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown, size: 12.sp, color: AppColors.textMuted2),
            SizedBox(width: 9.w),
            Expanded(child: Text(name, style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary))),
            Text('$done/${arr.length} done', style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _groupTaskRow(OpsTask t) {
    final meta = StatusMeta$.opsTask[t.status] ?? StatusMeta$.opsTask['open']!;
    final completed = t.status == 'completed';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('${Routes.opsTaskDetail}?id=${t.id}'),
      child: Container(
        padding: EdgeInsets.fromLTRB(23.w, 11.h, 2.w, 11.h),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF7F8F9)))),
        child: Row(
          children: [
            if (t.milestone) ...[
              Icon(PhosphorIconsFill.flag, size: 13.sp, color: AppColors.warningDeep),
              SizedBox(width: 8.w),
            ],
            Expanded(
              child: Text(t.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.custom(
                      size: 13.5,
                      weight: FontWeight.w600,
                      color: completed ? AppColors.textPlaceholder : AppColors.textBody,
                      decoration: completed ? TextDecoration.lineThrough : null)),
            ),
            SizedBox(width: 8.w),
            StatusPill.meta(meta),
            SizedBox(width: 8.w),
            Container(
              width: 24.w,
              height: 24.w,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
              child: Text(MockUsers.of(t.assignees.isEmpty ? '' : t.assignees.first).initials,
                  style: AppText.custom(size: 8.5, weight: FontWeight.w700, color: AppColors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filesTab() => _tabEmpty(PhosphorIconsRegular.paperclip, 'No files attached',
      'Drawings, BOQs and site photos shared on this project will appear here.');

  Widget _tabEmpty(IconData icon, String title, String body) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 34.h, 20.w, 20.h),
      child: Column(
        children: [
          Container(
            width: 56.w,
            height: 56.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(16.r)),
            child: Icon(icon, size: 26.sp, color: AppColors.textPlaceholder),
          ),
          SizedBox(height: 14.h),
          Text(title, style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 5.h),
          Text(body,
              textAlign: TextAlign.center,
              style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted, height: 1.5)),
        ],
      ),
    );
  }

  List<AuditEntry> _audit(Project p, StatusMeta meta, String mgrName) {
    final first = p.assignees.isEmpty ? '—' : MockUsers.of(p.assignees.first).firstName;
    return [
      AuditEntry(icon: PhosphorIconsRegular.userPlus, tone: AppColors.success, bg: AppColors.tintGreen, title: 'Assignee added', sub: '$first · $mgrName · 02 Jul 2026'),
      AuditEntry(icon: PhosphorIconsRegular.arrowsClockwise, tone: AppColors.blueBright, bg: AppColors.blueSubtle, title: 'Status changed to ${meta.label}', sub: '$mgrName · 28 Jun 2026'),
      AuditEntry(icon: PhosphorIconsRegular.plusCircle, tone: AppColors.pending, bg: AppColors.tintPurple, title: 'Project created', sub: '$mgrName · ${p.start}'),
    ];
  }

  Future<void> _openMenu() async {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final project = ref.read(projectByIdProvider(id));
    if (project == null) return;
    final status = _status ?? project.status;
    final locked = status == 'completed' || status == 'cancelled';

    await showActionMenu(
      context,
      title: project.name,
      actions: [
        MenuAction(
          icon: PhosphorIconsRegular.pencilSimple,
          label: 'Edit project',
          enabled: !locked,
          sublabel: locked ? 'Locked while $status' : null,
          onTap: () => context.push('${Routes.editProject}?id=${project.id}'),
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
          icon: PhosphorIconsRegular.archive,
          label: 'Archive project',
          destructive: true,
          onTap: () => ref.read(toastProvider.notifier).show('Archive project — coming soon'),
        ),
      ],
    );
  }

  Future<void> _openStatusSheet() async {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final project = ref.read(projectByIdProvider(id));
    if (project == null) return;
    final chosen = await showOpsStatusPicker(
      context: context,
      title: 'Project status',
      statuses: StatusMeta$.project,
      currentKey: _status ?? project.status,
    );
    if (chosen != null && mounted) setState(() => _status = chosen);
  }
}

extension _IfEmpty on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
