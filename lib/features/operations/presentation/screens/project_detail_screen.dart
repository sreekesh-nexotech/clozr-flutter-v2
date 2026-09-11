import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/api/roster.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/models/note.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../../core/widgets/notes_thread.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
// The shared CRM notes engine and audit trail — `related_to=project` and
// `model_name=Project` are both accepted, so Operations reuses them rather
// than keeping a second, local-only implementation.
import '../../../crm/application/providers/audit_log_providers.dart';
import '../../../crm/application/providers/crm_notes_providers.dart';
import '../../../crm/domain/entities/audit_entry.dart' hide AuditEntry;
import '../../../crm/domain/entities/audit_entry.dart' as crm_audit show AuditEntry;
import '../../application/providers/ops_tasks_providers.dart';
import '../../application/providers/projects_providers.dart';
import '../../domain/entities/ops_task.dart';
import 'package:file_picker/file_picker.dart';

import '../../../../core/utils/attachment_link.dart';
import '../../../crm/domain/entities/lead_file.dart';
import '../../../../data/api/status_keys.dart';
import '../../../crm/domain/entities/crm_catalog.dart';
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

  /// True while a Files-tab upload is in flight, so the button reports itself
  /// instead of looking ignored on a slow connection.
  bool _uploading = false;
  final Set<String> _closedGroups = {};
  final _notesKey = GlobalKey<NotesThreadState>();

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final projectsAsync = ref.watch(projectsProvider);
    // The full record once `GET /projects/projects/{id}/` lands, the list row
    // until then — so the page paints straight away and fills in.
    final project = ref.watch(projectDetailOrListProvider(id));
    // Scoped to this project by the server. The org-wide list is still read for
    // dependency counts, which need every task, not just this project's.
    final projectTasks = ref.watch(projectTasksProvider(id)).valueOrNull;
    final tasks = ref.watch(opsTasksListProvider);

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          _appBar('Project', project?.name),
          Expanded(
            child: AsyncStateView<List<Project>>(
              value: projectsAsync,
              onRetry: () => ref.invalidate(projectsProvider),
              onRefresh: () => _refresh(id),
              loading: () => const DetailSkeleton(),
              data: (_) {
                if (project == null) {
                  return const EmptyState(
                    icon: PhosphorIconsRegular.folderOpen,
                    title: 'Project not found',
                    body: 'This project may have been removed, or you may not have access to it.',
                  );
                }
                final status = _status ?? project.status;
                // The org's own lane name ("In Delivery"), not the built-in
                // bucket it folds into. A locally-changed status has no name
                // yet, so the fold names it until the record comes back.
                final meta = projectStatusMeta(
                  key: status,
                  statusName: _status == null ? project.statusName : '',
                  statuses: ref.watch(projectStatusOptionsProvider),
                );
                final priColor = StatusMeta$.projectPriority[project.pri] ?? AppColors.textMuted;
                final mgr = MockUsers.of(project.manager);
                final overdue = isProjectOverdue(project);
                final locked = status == 'completed' || status == 'cancelled';
                // The scoped fetch once it lands; the org-wide list filtered
                // down until then, so the tab paints immediately.
                final projTasks = projectTasks ??
                    tasks.where((t) => t.projId == project.id).toList();

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 40.h),
                  children: [
                    _summaryCard(project, meta, priColor, mgr, overdue),
                    if (locked) ...[SizedBox(height: 14.h), _lockBanner(status)],
                    SizedBox(height: 14.h),
                    _tabsCard(project, meta, projTasks, locked),
                    _notes(project),
                    SizedBox(height: 14.h),
                    _auditLog(project, meta, mgr.name),
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
  /// list-row fallback), this project's tasks, its attachments and its notes
  /// and audit log together.
  Future<void> _refresh(String id) async {
    ref.invalidate(projectDetailProvider(id));
    ref.invalidate(projectsProvider);
    ref.invalidate(projectTasksProvider(id));
    ref.invalidate(projectAttachmentsProvider(id));
    ref.invalidate(projectActivityLogProvider(id));
    // Whole family: the notifier loads in its constructor, so dropping it is
    // what re-reads the thread. Not awaited — nothing exposes that future —
    // but the record fetches below outlast it comfortably.
    ref.invalidate(crmNotesProvider);
    await settle([
      ref.read(projectDetailProvider(id).future),
      ref.read(projectsProvider.future),
      ref.read(projectTasksProvider(id).future),
      ref.read(projectAttachmentsProvider(id).future),
      ref.read(projectActivityLogProvider(id).future),
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
                    // The type alone. The project's UUID used to lead this line
                    // — unreadable, and it crowded out the only part anyone
                    // reads.
                    if (p.type.trim().isNotEmpty)
                      Text(p.type, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
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
          if (_tab == 'ptasks') _tasksTab(p, projTasks),
          if (_tab == 'pfiles') _filesTab(p),
        ],
      ),
    );
  }

  Widget _detailsTab(Project p, bool locked) {
    // Every row is the record's own value now. Visibility and Progress method
    // were the constants "Team" and "Task-based" whatever the project was, and
    // Assigned team fell back to the manager's seed team, then to the literal
    // "Team Kochi". All four are detail-only fields the list row omits, so
    // until the record lands — or where the project genuinely has none — they
    // read "—" rather than a confident wrong answer.
    const dash = '—';
    String orDash(String v) => v.trim().isEmpty ? dash : v.trim();
    final rows = <(String, String)>[
      ('Customer', p.internal ? 'Internal project' : orDash(p.company ?? '')),
      ('Project type', orDash(p.type)),
      ('Visibility', orDash(p.visibility)),
      ('Progress method', orDash(p.method)),
      ('Estimated cost', orDash(p.cost)),
      ('Assigned team', p.team.isEmpty ? 'No team' : p.team),
      ('Assignees',
          p.assignees.map((id) => MockUsers.of(id).firstName).join(', ').ifEmpty(dash)),
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

  Widget _tasksTab(Project p, List<OpsTask> projTasks) {
    if (projTasks.isEmpty) {
      return _tabEmpty(
        PhosphorIconsRegular.listChecks,
        'No tasks yet',
        'Tasks created for this project will appear here, grouped by stage.',
        action: _addTaskButton(p),
      );
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
          SizedBox(height: 8.h),
          _addTaskButton(p),
          SizedBox(height: 4.h),
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

  /// The Files tab — `GET /projects/project-attachments/?project={id}` (§15).
  ///
  /// Was a hard-coded empty state that never fetched, so a project with files
  /// still read "No files attached". Rows are tappable and open in the OS
  /// viewer; the empty state is unchanged for a project that genuinely has none.
  Widget _filesTab(Project p) {
    final async = ref.watch(projectAttachmentsProvider(p.id));
    final files = async.valueOrNull ?? const <LeadFile>[];
    if (async.isLoading && files.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 24.h, horizontal: 20.w),
        child: Text('Loading files…',
            style: AppText.custom(
                size: 13.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
      );
    }
    if (files.isEmpty) {
      return _tabEmpty(
        PhosphorIconsRegular.paperclip,
        'No files attached',
        'Drawings, BOQs and site photos shared on this project will appear here.',
        action: _uploadButton(p),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
      child: Column(
        children: [
          for (final f in files)
            InkWell(
              onTap: () async {
                final failure = await openAttachment(f.url);
                if (failure != null && mounted) {
                  ref.read(toastProvider.notifier).showError(failure);
                }
              },
              borderRadius: BorderRadius.circular(10.r),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 2.w),
                child: Row(
                  children: [
                    Container(
                      width: 36.w,
                      height: 36.w,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: AppColors.bgChipGrey,
                          borderRadius: BorderRadius.circular(10.r)),
                      child: Icon(PhosphorIconsRegular.paperclip,
                          size: 17.sp, color: AppColors.textSecondary),
                    ),
                    SizedBox(width: 11.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.custom(
                                  size: 13.5,
                                  weight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                          SizedBox(height: 2.h),
                          Text(
                              [f.ext, if (f.uploadedAt.isNotEmpty) f.uploadedAt]
                                  .join(' · '),
                              style: AppText.caption()),
                        ],
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Icon(PhosphorIconsRegular.arrowSquareOut,
                        size: 16.sp, color: AppColors.textPlaceholder),
                  ],
                ),
              ),
            ),
          SizedBox(height: 6.h),
          _uploadButton(p),
        ],
      ),
    );
  }

  /// The Tasks tab's add affordance — the tab could list a project's tasks but
  /// not start one, so a task for this project had to be created from the
  /// Operations task screen and pointed back at it by hand.
  ///
  /// Opens the existing create-task form with the project already chosen.
  Widget _addTaskButton(Project p) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('${Routes.createTask}?project=${p.id}'),
      child: Container(
        height: 44.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11.r),
          border: Border.all(color: AppColors.borderInput),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsRegular.plus, size: 15.sp, color: AppColors.navy),
            SizedBox(width: 8.w),
            Text('Add task',
                style: AppText.custom(
                    size: 13.5, weight: FontWeight.w600, color: AppColors.textBody)),
          ],
        ),
      ),
    );
  }

  /// The Files tab's upload affordance — the tab could read files but never
  /// add one, so a project's drawings could only arrive from another client.
  Widget _uploadButton(Project p) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _uploading ? null : () => _pickAndUpload(p),
      child: Container(
        height: 44.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11.r),
          border: Border.all(color: AppColors.borderInput),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                _uploading
                    ? PhosphorIconsRegular.circleNotch
                    : PhosphorIconsRegular.uploadSimple,
                size: 15.sp,
                color: AppColors.navy),
            SizedBox(width: 8.w),
            Text(_uploading ? 'Uploading…' : 'Upload file',
                style: AppText.custom(
                    size: 13.5, weight: FontWeight.w600, color: AppColors.textBody)),
          ],
        ),
      ),
    );
  }

  /// Picks a file and posts it (`POST /projects/project-attachments/`, §15).
  ///
  /// The list refetches off the app-wide write tick, so a successful upload
  /// shows up without invalidating anything by hand.
  Future<void> _pickAndUpload(Project p) async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(withData: false);
    } on Object catch (e) {
      // The picker is a native plugin: silence here reads as a dead button.
      if (!mounted) return;
      ref.read(toastProvider.notifier).showError('Could not open the file picker: $e');
      return;
    }
    final file = picked?.files.singleOrNull;
    final path = file?.path;
    if (file == null || path == null || !mounted) return; // cancelled

    setState(() => _uploading = true);
    try {
      await ref.read(projectsRepositoryProvider).uploadProjectAttachment(
            projectId: p.id,
            path: path,
            name: file.name,
          );
      if (!mounted) return;
      ref.invalidate(projectAttachmentsProvider(p.id));
      ref.read(toastProvider.notifier).show('${file.name} uploaded');
    } on AppError catch (e) {
      if (mounted) ref.read(toastProvider.notifier).showError(e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _tabEmpty(IconData icon, String title, String body, {Widget? action}) {
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
          if (action != null) ...[SizedBox(height: 16.h), action],
        ],
      ),
    );
  }

  /// The project's notes, on the shared CRM notes engine.
  ///
  /// `related_to=project` — the API's accepted set includes it. This used to be
  /// [opsNotesProvider], which is in-memory only and seeded from an *ops task*
  /// lookup, so on a project id it always started empty and nothing typed here
  /// ever left the device.
  Widget _notes(Project p) {
    final seed = CrmNotesSeed(
      p.id,
      () => const <NoteEntry>[],
      apiModel: 'project',
    );
    return NotesThread(
      key: _notesKey,
      author: ref.watch(noteAuthorProvider),
      notes: ref.watch(crmNotesProvider(seed)),
      onAddNote: (body, atts) =>
          ref.read(crmNotesProvider(seed).notifier).addNote(body, atts, ref.read(noteAuthorProvider)),
      onAddReply: (noteId, body) => ref
          .read(crmNotesProvider(seed).notifier)
          .addReply(noteId, body, ref.read(noteAuthorProvider)),
    );
  }

  /// The project's real audit trail —
  /// `GET /access-control/audit-logs/?model_name=Project&record_id=<id>`.
  ///
  /// Refetched off the API write tick, so a status change, an edit or a note
  /// made on this screen shows up without each action saying so.
  ///
  /// Falls back to the derived rows when the log is empty: mock mode, or a role
  /// without `view_audit_log`, which 403s.
  Widget _auditLog(Project p, StatusMeta meta, String mgrName) {
    final entries = ref.watch(projectActivityLogProvider(p.id)).valueOrNull ?? const [];
    return OpsAuditLog(
      entries: entries.isEmpty
          ? _audit(p, meta, mgrName)
          : [for (final e in entries) _auditRow(e)],
    );
  }

  /// One audit row as a timeline entry, iconed by what kind of event it was.
  AuditEntry _auditRow(crm_audit.AuditEntry e) {
    final (icon, tone, bg) = switch (e.kind) {
      AuditEventKind.created => (PhosphorIconsRegular.plusCircle, AppColors.pending, AppColors.tintPurple),
      AuditEventKind.statusChanged => (PhosphorIconsRegular.arrowsClockwise, AppColors.blueBright, AppColors.blueSubtle),
      AuditEventKind.noteAdded => (PhosphorIconsRegular.note, AppColors.pending, AppColors.tintPurple),
      AuditEventKind.childAdded => (PhosphorIconsRegular.userPlus, AppColors.success, AppColors.tintGreen),
      AuditEventKind.deleted => (PhosphorIconsRegular.trash, AppColors.error, AppColors.tintRed),
      _ => (PhosphorIconsRegular.pencilSimple, AppColors.blueBright, AppColors.blueSubtle),
    };
    final when = e.at == null ? '' : relativeTime(e.at);
    final sub = [e.subtitle, e.actor, when].where((s) => s.isNotEmpty).join(' · ');
    return AuditEntry(icon: icon, tone: tone, bg: bg, title: e.title, sub: sub);
  }

  /// The derived rows, used only when the real log is unavailable.
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
    // The enriched record, so the Archive entry knows whether the project is
    // already archived and can offer Restore instead.
    final project = ref.read(projectDetailOrListProvider(id));
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
          label: project.isArchived ? 'Restore project' : 'Archive project',
          sublabel: project.isArchived ? 'Currently archived' : null,
          destructive: !project.isArchived,
          onTap: () => _archive(project),
        ),
      ],
    );
  }

  /// Archives the project, or restores it — one endpoint, toggled by
  /// `is_archive` (`operations.md` §8).
  ///
  /// Archiving asks first: it takes the project out of every default list, so
  /// it is not something to do on a mis-tap. Restoring does not ask — it only
  /// puts something back.
  Future<void> _archive(Project project) async {
    final archiving = !project.isArchived;
    if (archiving) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Archive project?'),
          content: Text('"${project.name}" will be hidden from the projects '
              'list. You can restore it from here afterwards.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Archive', style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    final toast = ref.read(toastProvider.notifier);
    try {
      await ref
          .read(projectsRepositoryProvider)
          .archiveProject(project.id, archive: archiving);
    } on AppError catch (e) {
      // Restoring into a name an active project already holds is a 400 — the
      // message is the only thing that explains why nothing happened.
      if (mounted) toast.showError(e.message);
      return;
    }
    if (!mounted) return;
    // The whole family: the list renders under whatever filter is active, and
    // archived rows are excluded from it by default.
    ref.invalidate(projectsScopedProvider);
    ref.invalidate(projectsProvider);
    ref.invalidate(projectDetailProvider(project.id));
    toast.show(archiving ? 'Project archived' : 'Project restored');
    // An archived project is gone from the list this screen was opened from.
    if (archiving) context.pop();
  }

  /// Opens the status picker and **writes** the choice.
  ///
  /// Was purely cosmetic: it offered the built-in vocabulary regardless of what
  /// the org calls its statuses, and the pick only set a local field — so a
  /// status change tinted the pill and was gone on the next rebuild, with
  /// nothing sent to the server.
  ///
  /// With the catalog loaded the options are the org's own statuses, keyed by
  /// `project_status_id` so the pick *is* the value to PATCH. Without it (mock
  /// mode, failed fetch) it falls back to the built-ins and stays local, which
  /// is the old behaviour and the only thing possible with no id to send.
  Future<void> _openStatusSheet() async {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final project = ref.read(projectDetailOrListProvider(id));
    if (project == null) return;

    final catalog = ref.read(projectStatusOptionsProvider);
    final orgDriven = catalog.isNotEmpty;
    final statuses = orgDriven
        ? {
            for (final s in catalog)
              s.id: StatusMeta(
                s.name,
                s.color ??
                    (StatusMeta$.project[projectStatusKey(name: s.name)] ??
                            StatusMeta$.project['planning']!)
                        .color,
              ),
          }
        : StatusMeta$.project;

    final chosen = await showOpsStatusPicker(
      context: context,
      title: 'Project status',
      statuses: statuses,
      currentKey: orgDriven
          ? (project.statusId.isNotEmpty
              ? project.statusId
              : _idForName(catalog, project.statusName))
          : (_status ?? project.status),
    );
    if (chosen == null || !mounted) return;

    if (!orgDriven) {
      setState(() => _status = chosen);
      return;
    }

    // Optimistic, so the pill moves at once; rolled back if the write is
    // refused — completing a project can be blocked server-side.
    final previous = _status;
    final picked = catalog.where((s) => s.id == chosen).firstOrNull;
    setState(() => _status = projectStatusKey(name: picked?.name));

    final toast = ref.read(toastProvider.notifier);
    try {
      await ref
          .read(projectsRepositoryProvider)
          .updateProject(project.id, {'status': chosen});
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _status = previous);
      toast.showError(e is AppError ? e.message : 'Could not update the status.');
      return;
    }
    if (!mounted) return;
    // The record, every list query and the tab counts all moved.
    ref.invalidate(projectDetailProvider(project.id));
    ref.invalidate(projectsScopedProvider);
    ref.invalidate(projectStatusCountsProvider);
    toast.show('Status updated');

    // Then hand the pill back to the server: a workflow may have landed the
    // project somewhere other than the pick, and the optimistic override would
    // otherwise hide that until the screen is reopened.
    try {
      await ref.read(projectDetailProvider(project.id).future);
    } on Object catch (_) {
      return; // Keep the override rather than reverting to a stale status.
    }
    if (mounted) setState(() => _status = null);
  }

  /// A status name → its `project_status_id`, for a record that arrived without
  /// the raw id (a slim list row carries the name only).
  static String _idForName(List<CatalogOption> catalog, String name) {
    final needle = name.trim().toLowerCase();
    for (final s in catalog) {
      if (s.name.trim().toLowerCase() == needle) return s.id;
    }
    return '';
  }
}

extension _IfEmpty on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
