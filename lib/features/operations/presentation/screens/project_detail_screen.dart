import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/api/roster.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../accounting/application/providers/accounting_providers.dart';
import '../../../accounting/presentation/components/project_financials_card.dart';
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
import '../../../../core/config/api_config.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../../core/widgets/notes_thread.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../../auth/presentation/components/permission_guard.dart';
// The shared CRM notes engine and audit trail — `related_to=project` and
// `model_name=Project` are both accepted, so Operations reuses them rather
// than keeping a second, local-only implementation.
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
import '../components/project_close.dart';
import '../../../../core/network/network_providers.dart';
import '../components/ops_widgets.dart';
import '../../application/project_task_groups.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../data/api/user_directory.dart';

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
  void initState() {
    super.initState();
    // Fresh notes on every open, like the webapp: the shared notes family
    // outlives a sign-out, so the thread otherwise opened on the previous
    // session's copy (times frozen at "Just now").
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(crmNotesProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final projectsAsync = ref.watch(projectsProvider);
    // The full record once `GET /projects/projects/{id}/` lands, the list row
    // until then — so the page paints straight away and fills in.
    final project = ref.watch(projectDetailOrListProvider(id));
    // The record's own fetch decides whether the page can render. A failed
    // fetch (offline, 403, 404) used to fall back to the slim list row, which
    // painted "—" placeholders and a wrong team as if they were the record —
    // the webapp shows the error with Retry instead.
    final detailAsync = ref.watch(projectDetailProvider(id));
    final detailFailed =
        ApiConfig.apiEnabled && detailAsync.hasError && !detailAsync.isLoading;
    final gate = detailFailed
        ? AsyncValue<List<Project>>.error(
            detailAsync.error!, detailAsync.stackTrace ?? StackTrace.current)
        : projectsAsync;
    // Scoped to this project by the server. The org-wide list is still read for
    // dependency counts, which need every task, not just this project's.
    final projectTasksAsync = ref.watch(projectTasksProvider(id));
    final projectTasks = projectTasksAsync.valueOrNull;
    final tasksFailed = ApiConfig.apiEnabled &&
        projectTasksAsync.hasError &&
        !projectTasksAsync.isLoading;
    final tasks = ref.watch(opsTasksListProvider);

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          _appBar('Project', project?.name),
          Expanded(
            child: AsyncStateView<List<Project>>(
              value: gate,
              onRetry: () {
                ref.invalidate(projectDetailProvider(id));
                ref.invalidate(projectsProvider);
              },
              onRefresh: () => _refresh(id),
              // Webapp `failureCopy`: a removed project reads "Not found", a
              // refused one "You don't have access to this" — never the
              // cached record as if it were still there.
              error: (e, retry) => switch (e.type) {
                AppErrorType.notFound => ErrorState(
                    icon: PhosphorIconsFill.magnifyingGlass,
                    title: 'Not found',
                    body: 'We couldn’t find this project. It may have been deleted or moved.',
                    onRetry: retry,
                  ),
                AppErrorType.forbidden => ErrorState(
                    icon: PhosphorIconsFill.lock,
                    title: 'You don’t have access to this',
                    body: 'Your account isn’t permitted to view this project. Ask a workspace admin if you think that’s wrong.',
                    onRetry: retry,
                  ),
                _ => ErrorState.forError(e, onRetry: retry),
              },
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
                // Webapp: a status with `is_closed` is closed — the bar reads
                // "Closed" and the project is never overdue.
                final closed = _isClosed(project, status);
                final overdue = !closed && (project.isOverdue ?? isProjectOverdue(project));
                final locked = closed;
                // The scoped fetch once it lands; the org-wide list filtered
                // down until then, so the tab paints immediately.
                final projTasks = tasksFailed
                    ? const <OpsTask>[]
                    : projectTasks ??
                        tasks.where((t) => t.projId == project.id).toList();

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 40.h),
                  children: [
                    _summaryCard(project, meta, priColor, mgr, overdue, closed),
                    if (locked) ...[SizedBox(height: 14.h), _lockBanner(project, meta)],
                    SizedBox(height: 14.h),
                    _tabsCard(project, meta, projTasks, locked, overdue,
                        tasksError: tasksFailed ? projectTasksAsync.error : null),
                    // Billed, collected, costs and margin from the ledger —
                    // only while accounting is active and reports are readable.
                    if (ref.watch(accountingActiveProvider) && ref.watch(accPermProvider('acc_report')).read) ...[
                      SizedBox(height: 14.h),
                      ProjectFinancialsCard(projectId: project.id),
                    ],
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
    ref.invalidate(projectFeedProvider(id));
    // Whole family: the notifier loads in its constructor, so dropping it is
    // what re-reads the thread. Not awaited — nothing exposes that future —
    // but the record fetches below outlast it comfortably.
    ref.invalidate(crmNotesProvider);
    await settle([
      ref.read(projectDetailProvider(id).future),
      ref.read(projectsProvider.future),
      ref.read(projectTasksProvider(id).future),
      ref.read(projectAttachmentsProvider(id).future),
      ref.read(projectFeedProvider(id).future),
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

  /// The project's status is a closed one — the org catalogue's `is_closed`,
  /// or the built-in completed / cancelled buckets when it has not loaded.
  bool _isClosed(Project p, String statusKey) {
    if (_status != null) return statusKey == 'completed' || statusKey == 'cancelled';
    final name = p.statusName.trim().toLowerCase();
    final hit = ref
        .read(projectStatusOptionsProvider)
        .where((s) => s.id == p.statusId || s.name.trim().toLowerCase() == name)
        .firstOrNull;
    return hit?.isClosed ?? (statusKey == 'completed' || statusKey == 'cancelled');
  }

  Widget _summaryCard(Project p, StatusMeta meta, Color priColor, AppUser mgr, bool overdue, bool closed) {
    // Webapp header sub-line: "PRJ-code · Type · Customer" (or "Internal project").
    final subtitle = [
      p.code,
      p.type.trim(),
      p.internal ? 'Internal project' : (p.company ?? '').trim(),
    ].where((v) => v.isNotEmpty).join(' · ');
    final archivedOn = absoluteDate(parseApiDate(p.archivedAt));
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
                    if (subtitle.isNotEmpty)
                      Text(subtitle, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                    if (p.isArchived) ...[
                      SizedBox(height: 6.h),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                        decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(999)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(PhosphorIconsRegular.archive, size: 12.sp, color: AppColors.textMuted),
                          SizedBox(width: 5.w),
                          Text(archivedOn.trim().isEmpty ? 'Archived' : 'Archived · $archivedOn',
                              style: AppText.custom(size: 11, weight: FontWeight.w600, color: AppColors.textMuted)),
                        ]),
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
                  StatusPill(label: p.pri, color: priColor),
                ],
              ),
            ],
          ),
          SizedBox(height: 15.h),
          if (closed)
            Row(children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 4.h),
                decoration: BoxDecoration(color: AppColors.tintGreen, borderRadius: BorderRadius.circular(8.r)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(PhosphorIconsFill.checkCircle, size: 13.sp, color: AppColors.success),
                  SizedBox(width: 5.w),
                  Text('Closed', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.success)),
                ]),
              ),
            ])
          else
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Webapp: on a Manual project the progress is set right here.
            onTap: _canSetProgress(p) ? () => _editProgress(p) : null,
            child: Row(
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
              if (_canSetProgress(p)) ...[
                SizedBox(width: 6.w),
                Icon(PhosphorIconsRegular.pencilSimple, size: 13.sp, color: AppColors.textMuted),
              ],
            ],
          ),
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 14)),
          Row(
            children: [
              Container(
                width: 34.w,
                height: 34.w,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
                child: Text(p.manager.trim().isEmpty ? '—' : mgr.initials, style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.white)),
              ),
              SizedBox(width: 11.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.manager.trim().isEmpty ? '—' : mgr.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
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
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${p.start.trim().isEmpty ? '—' : p.start} – '),
                  // Webapp "Expected end": red when the server says overdue.
                  TextSpan(
                      text: p.end.trim().isEmpty ? '—' : p.end,
                      style: overdue ? const TextStyle(color: AppColors.error) : null),
                ]),
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

  Widget _lockBanner(Project p, StatusMeta meta) {
    final completed = !(p.statusName.toLowerCase().contains('cancel') || (_status ?? p.status) == 'cancelled');
    final statusLabel = meta.label.toLowerCase();
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
                Text('This project is $statusLabel — fields are locked.',
                    style: AppText.custom(size: 13, weight: FontWeight.w700, color: completed ? AppColors.success : AppColors.textLabelAlt)),
                SizedBox(height: 2.h),
                // Webapp has no separate Reopen: picking an open status reopens it.
                Text('Change its status to an open one to reopen it and make changes.',
                    style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabsCard(Project p, StatusMeta meta, List<OpsTask> projTasks, bool locked, bool overdue,
      {Object? tasksError}) {
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
          if (_tab == 'details') _detailsTab(p, locked, overdue),
          if (_tab == 'ptasks')
            tasksError != null ? _tasksError(p, tasksError) : _tasksTab(p, projTasks),
          if (_tab == 'pfiles') _filesTab(p),
        ],
      ),
    );
  }

  Widget _detailsTab(Project p, bool locked, bool overdue) {
    // Webapp "Project information" rows, in its order. Detail-only values read
    // "—" until the record lands, never a confident wrong answer.
    const dash = '—';
    String orDash(String v) => v.trim().isEmpty ? dash : v.trim();
    final canEdit = hasPermission(ref, 'project', PermVerb.update);
    final priColor = StatusMeta$.projectPriority[p.pri] ?? AppColors.textMuted;
    final rows = <(String, Widget)>[
      ('Customer', _val(p.internal ? 'Internal project' : orDash(p.company ?? ''), muted: p.internal)),
      ('Project type', _val(orDash(p.type))),
      ('Priority', p.pri.trim().isEmpty ? _val(dash) : Align(alignment: Alignment.centerRight, child: StatusPill(label: p.pri, color: priColor))),
      ('Visibility', _val(orDash(p.visibility))),
      ('Progress method', _val(orDash(p.method))),
      ('Expected start', _val(orDash(absoluteDate(parseApiDate(p.startISO)).ifEmpty(p.start)))),
      ('Expected end', _val(
          '${orDash(p.end)}${overdue ? ' · Overdue' : ''}',
          color: overdue ? AppColors.error : null)),
      ('Estimated cost', _val(p.costNum > 0 ? orDash(p.cost) : dash, muted: p.costNum <= 0)),
      // Only when linked — opens the quote (webapp button with its number).
      if (p.quotationId.isNotEmpty)
        ('Linked quote', GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.push('${Routes.quoteDetail}?id=${p.quotationId}'),
          child: _val(ref.watch(linkedQuoteNumberProvider(p.quotationId)).valueOrNull ?? 'Open quote',
              color: AppColors.navy),
        )),
      ('Project ID', _val(p.code.isNotEmpty ? p.code : p.id)),
      ('Assigned team', _val(p.team.isEmpty ? dash : p.team)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (p.desc.trim().isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(2.w, 12.h, 2.w, 4.h),
            child: Text(p.desc, style: AppText.custom(size: 14, weight: FontWeight.w500, color: AppColors.textLabelAlt, height: 1.6)),
          ),
        if (!locked)
          // Webapp `PermissionGate`: without `project` update the button stays
          // visible but disabled, and says why.
          Opacity(
            opacity: canEdit ? 1 : 0.5,
            child: GestureDetector(
            onTap: () {
              if (!ensurePermission(ref, 'project', PermVerb.update)) return;
              context.push('${Routes.editProject}?id=${p.id}');
            },
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
          ),
        if (!canEdit && !locked)
          Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: Text(permissionCopy(PermVerb.update),
                style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
          ),
        for (final r in rows)
          Container(
            padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 2.w),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(r.$1, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                SizedBox(width: 14.w),
                Expanded(child: r.$2),
              ],
            ),
          ),
        // Webapp "Assignees": a chip per person, or "No assignees yet".
        Padding(
          padding: EdgeInsets.fromLTRB(2.w, 12.h, 2.w, 10.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Assignees', style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
              SizedBox(height: 8.h),
              if (p.assignees.isEmpty)
                Text('No assignees yet', style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textPlaceholder))
              else
                Wrap(spacing: 8.w, runSpacing: 8.h, children: [
                  for (final id in p.assignees)
                    Container(
                      padding: EdgeInsets.fromLTRB(4.w, 4.h, 10.w, 4.h),
                      decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(999)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 24.w,
                          height: 24.w,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
                          child: Text(MockUsers.of(id).initials, style: AppText.custom(size: 8.5, weight: FontWeight.w700, color: AppColors.white)),
                        ),
                        SizedBox(width: 6.w),
                        Text(MockUsers.of(id).firstName, style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textPrimary)),
                      ]),
                    ),
                ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _val(String v, {Color? color, bool muted = false}) => Text(v,
      textAlign: TextAlign.right,
      style: AppText.custom(
          size: 14,
          weight: FontWeight.w700,
          color: color ?? (muted ? AppColors.textPlaceholder : AppColors.textPrimary)));

  /// Webapp project Tasks tab: "Tasks done/total", View all tasks, New group,
  /// the project's real lanes (`/projects/task-groups/?project=`) — an empty
  /// lane shows "No tasks in this group" — then "No group" when it has any.
  Widget _tasksTab(Project p, List<OpsTask> projTasks) {
    final lanes = ref.watch(taskGroupsProvider(p.id)).valueOrNull ?? const <CatalogOption>[];
    final canCreate = hasPermission(ref, 'project_task', PermVerb.create);
    final total = p.taskCount ?? projTasks.length;
    final done = p.doneCount ?? projTasks.where(_isTaskDone).length;
    final header = Padding(
      padding: EdgeInsets.only(top: 12.h, bottom: 4.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('TASKS', style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.5)),
            SizedBox(width: 8.w),
            Text('$done/$total done', style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textMuted)),
          ]),
          SizedBox(height: 10.h),
          Row(children: [
            Expanded(child: _ghostButton(PhosphorIconsRegular.arrowUpRight, 'View all tasks', () {
              // Ops › Tasks filtered to this project, everyone's tasks.
              context.go('${Routes.opsTasks}?project=${p.id}');
            })),
            SizedBox(width: 8.w),
            Expanded(child: Opacity(
              opacity: canCreate ? 1 : 0.5,
              child: _ghostButton(PhosphorIconsRegular.folderPlus, 'New group', () {
                if (!ensurePermission(ref, 'project_task', PermVerb.create)) return;
                _groupDialog(p, lanes);
              }),
            )),
          ]),
        ],
      ),
    );
    if (projTasks.isEmpty && lanes.isEmpty) {
      return Column(children: [
        header,
        _tabEmpty(
          PhosphorIconsRegular.checkSquare,
          'No tasks yet — add the first one',
          'Tasks created for this project will appear here, grouped by stage.',
          action: _addTaskButton(p),
        ),
      ]);
    }
    final laneIds = {for (final g in lanes) g.id};
    final ungrouped = [for (final t in projTasks) if (!laneIds.contains(t.groupId)) t];
    return Padding(
      padding: EdgeInsets.only(top: 2.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          for (final g in lanes) ..._lane(p, g.id, g.name, [for (final t in projTasks) if (t.groupId == g.id) t], lanes),
          if (ungrouped.isNotEmpty) ..._lane(p, '', 'No group', ungrouped, lanes),
          SizedBox(height: 8.h),
          _addTaskButton(p),
          SizedBox(height: 4.h),
        ],
      ),
    );
  }

  List<Widget> _lane(Project p, String id, String name, List<OpsTask> arr, List<CatalogOption> lanes) {
    final key = id.isEmpty ? '__nogroup__' : id;
    return [
      _groupHeader(p, key, id, name, arr, lanes),
      if (!_closedGroups.contains(key))
        if (arr.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(23.w, 12.h, 2.w, 12.h),
            child: Text('No tasks in this group', style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
          )
        else
          for (final t in arr) _groupTaskRow(t),
    ];
  }

  Widget _ghostButton(IconData icon, String label, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 38.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10.r), border: Border.all(color: AppColors.borderInput)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14.sp, color: AppColors.navy),
            SizedBox(width: 6.w),
            Text(label, style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textBody)),
          ]),
        ),
      );

  /// A task is "done" when its status is closed and not cancelled (webapp).
  bool _isTaskDone(OpsTask t) {
    final name = t.statusName.trim().toLowerCase();
    final hit = ref.read(opsTaskStatusOptionsProvider).where((s) => s.name.trim().toLowerCase() == name).firstOrNull;
    return hit != null ? (hit.isClosed && !hit.isCancelled) : t.status == 'completed';
  }

  Widget _groupHeader(Project p, String key, String id, String name, List<OpsTask> arr, List<CatalogOption> lanes) {
    final open = !_closedGroups.contains(key);
    final done = arr.where(_isTaskDone).length;
    final canUpdate = hasPermission(ref, 'project_task', PermVerb.update);
    final canDelete = hasPermission(ref, 'project_task', PermVerb.delete);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        if (open) {
          _closedGroups.add(key);
        } else {
          _closedGroups.remove(key);
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
            // Rename / Delete group — a real lane, and only when either is allowed.
            if (id.isNotEmpty && (canUpdate || canDelete))
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showActionMenu(context, title: name, actions: [
                  if (canUpdate)
                    MenuAction(icon: PhosphorIconsRegular.pencilSimple, label: 'Rename', onTap: () => _groupDialog(p, lanes, renameId: id, renameOf: name)),
                  if (canDelete)
                    MenuAction(icon: PhosphorIconsRegular.trash, label: 'Delete group', destructive: true, onTap: () => _deleteGroup(p, id, name)),
                ]),
                child: Padding(
                  padding: EdgeInsets.only(left: 10.w),
                  child: Icon(PhosphorIconsBold.dotsThree, size: 18.sp, color: AppColors.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Webapp `NewGroupModal`: "New task group" / "Rename group", field "Group
  /// name"; blank → "Group name is required", a clash → "That group already
  /// exists".
  Future<void> _groupDialog(Project p, List<CatalogOption> lanes, {String? renameId, String? renameOf}) async {
    final ctrl = TextEditingController(text: renameOf ?? '');
    String? err;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          void submit() {
            final t = ctrl.text.trim();
            if (t.isEmpty) {
              setD(() => err = 'Group name is required');
              return;
            }
            final clash = lanes.any((g) =>
                g.name.toLowerCase() == t.toLowerCase() && g.name.toLowerCase() != (renameOf ?? '').toLowerCase());
            if (clash) {
              setD(() => err = 'That group already exists');
              return;
            }
            Navigator.of(ctx).pop(t);
          }

          return AlertDialog(
            title: Text(renameId == null ? 'New task group' : 'Rename group'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(labelText: 'Group name *', hintText: 'e.g. Site Work', errorText: err),
              onChanged: (_) => setD(() => err = null),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
              TextButton(onPressed: submit, child: Text(renameId == null ? 'Add group' : 'Save changes')),
            ],
          );
        },
      ),
    );
    if (name == null || !mounted) return;
    if (renameId != null && name == renameOf) return;
    final toast = ref.read(toastProvider.notifier);
    final error = renameId == null
        ? await createTaskGroup(ref, p.id, name)
        : await renameTaskGroup(ref, p.id, renameId, name);
    if (!mounted) return;
    if (error != null) {
      toast.showError(error);
    } else {
      toast.show(renameId == null ? 'Group "$name" added' : 'Group renamed to "$name"');
    }
  }

  Future<void> _deleteGroup(Project p, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete group "$name"?'),
        content: const Text('Tasks in this group move to No group — tasks are never deleted with the group.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete group', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final error = await deleteTaskGroup(ref, p.id, id);
    if (!mounted) return;
    final toast = ref.read(toastProvider.notifier);
    error == null ? toast.show('Tasks moved to No group') : toast.showError(error);
  }

  /// Webapp task row: done checkbox, subject (struck when done), milestone
  /// flag (tap to set / clear), "Waiting on N", "<due> · <assignee>", the
  /// status pill ("Overdue" in red when overdue) and Delete.
  Widget _groupTaskRow(OpsTask t) {
    final meta = opsTaskStatusMeta(
      key: t.status,
      statusName: t.statusName,
      statuses: ref.watch(opsTaskStatusOptionsProvider),
    );
    final completed = _isTaskDone(t);
    final canUpdate = hasPermission(ref, 'project_task', PermVerb.update) && t.canUpdate != false;
    final canDelete = hasPermission(ref, 'project_task', PermVerb.delete) && t.canDelete != false;
    final overdue = (t.isOverdue ?? false) && !completed;
    final due = [
      if (t.end.trim().isNotEmpty) _shortDue(t),
      if (t.assignees.isNotEmpty) MockUsers.of(t.assignees.first).name,
    ].join(' · ');
    return Container(
      padding: EdgeInsets.fromLTRB(2.w, 10.h, 2.w, 10.h),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF7F8F9)))),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toggleDone(t, completed),
            child: Opacity(
              opacity: canUpdate ? 1 : 0.4,
              child: Container(
                width: 20.w,
                height: 20.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: completed ? AppColors.success : AppColors.white,
                  borderRadius: BorderRadius.circular(5.r),
                  border: Border.all(color: completed ? AppColors.success : const Color(0xFFAEAEAE), width: 2),
                ),
                child: completed ? Icon(PhosphorIconsBold.check, size: 12.sp, color: AppColors.white) : null,
              ),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.push('${Routes.opsTaskDetail}?id=${t.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(t.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(
                              size: 13.5,
                              weight: FontWeight.w600,
                              color: completed ? AppColors.textPlaceholder : AppColors.textBody,
                              decoration: completed ? TextDecoration.lineThrough : null)),
                    ),
                    SizedBox(width: 6.w),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _toggleMilestone(t),
                      child: Opacity(
                        opacity: t.milestone ? 1 : 0.3,
                        child: Icon(PhosphorIconsFill.flag, size: 14.sp, color: AppColors.warningDeep),
                      ),
                    ),
                    if (t.pendingDeps > 0) ...[
                      SizedBox(width: 6.w),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                        decoration: BoxDecoration(color: AppColors.tintAmber, borderRadius: BorderRadius.circular(6.r)),
                        child: Text('Waiting on ${t.pendingDeps}',
                            style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: const Color(0xFFB45C00))),
                      ),
                    ],
                  ]),
                  if (due.isNotEmpty) ...[
                    SizedBox(height: 2.h),
                    Text(due, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(width: 8.w),
          overdue ? StatusPill(label: 'Overdue', color: AppColors.error) : StatusPill.meta(meta),
          if (canDelete)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _deleteTask(t),
              child: Padding(
                padding: EdgeInsets.only(left: 8.w),
                child: Icon(PhosphorIconsRegular.trash, size: 15.sp, color: AppColors.textPlaceholder),
              ),
            ),
        ],
      ),
    );
  }

  /// "28 Jun, 17:00" — the webapp's task due label (date + time when set).
  String _shortDue(OpsTask t) {
    final d = DateTime.tryParse(t.endISO);
    if (d == null) return t.end;
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final base = '${d.day} ${m[d.month - 1]}';
    final time = t.endTime.trim();
    if (time.isEmpty) return base;
    final hm = RegExp(r'^(\d{1,2}):(\d{2})\s*([AaPp][Mm])?$').firstMatch(time);
    if (hm == null) return '$base, $time';
    var h = int.parse(hm[1]!);
    final ap = hm[3]?.toUpperCase();
    if (ap == 'PM' && h < 12) h += 12;
    if (ap == 'AM' && h == 12) h = 0;
    return '$base, ${h.toString().padLeft(2, '0')}:${hm[2]}';
  }

  /// Webapp tick: done → the first open status; not done → the first closed,
  /// non-cancelled one. A refusal (open subtasks, dependencies) is a toast.
  Future<void> _toggleDone(OpsTask t, bool done) async {
    if (!ensurePermission(ref, 'project_task', PermVerb.update)) return;
    final target = done ? ref.read(opsTaskOpenStatusProvider) : ref.read(opsTaskDoneStatusProvider);
    final toast = ref.read(toastProvider.notifier);
    if (target == null) {
      toast.showError('No matching status configured');
      return;
    }
    await _taskWrite(() => ref.read(opsTasksRepositoryProvider).updateOpsTask(t.id, {'status': target.id}));
  }

  Future<void> _toggleMilestone(OpsTask t) async {
    if (!ensurePermission(ref, 'project_task', PermVerb.update)) return;
    await _taskWrite(() => ref.read(opsTasksRepositoryProvider).updateOpsTask(t.id, {'is_milestone': !t.milestone}));
  }

  Future<void> _deleteTask(OpsTask t) async {
    if (!ensurePermission(ref, 'project_task', PermVerb.delete)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('"${t.subject}" will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('Delete', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (await _taskWrite(() => ref.read(opsTasksRepositoryProvider).deleteOpsTask(t.id))) {
      ref.read(toastProvider.notifier).show('Task deleted');
    }
  }

  /// Runs a task write; the server's refusal becomes one toast. The tab, the
  /// group counts and the project's progress refetch off the write tick.
  Future<bool> _taskWrite(Future<void> Function() call) async {
    try {
      await call();
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      if (mounted) ref.read(toastProvider.notifier).showError(e.bareMessage);
      return false;
    }
    if (!mounted) return false;
    // The header's done count and progress move with the task.
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    ref.invalidate(projectDetailProvider(id));
    return true;
  }

  bool _canSetProgress(Project p) =>
      p.method == 'Manual' && hasPermission(ref, 'project', PermVerb.update) && p.canManage != false;

  /// Webapp `ProgressMetric` on a Manual project: PATCH `percent_complete`,
  /// "Progress set to N%"; outside 0–100 → "Enter a number between 0 and 100.".
  Future<void> _editProgress(Project p) async {
    final ctrl = TextEditingController(text: '${p.progress}');
    String? err;
    var saving = false;
    final saved = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        Future<void> commit() async {
          final n = num.tryParse(ctrl.text.trim());
          if (n == null || n < 0 || n > 100) {
            setD(() => err = 'Enter a number between 0 and 100.');
            return;
          }
          final rounded = n.round();
          if (rounded == p.progress) {
            Navigator.of(ctx).pop();
            return;
          }
          setD(() => saving = true);
          try {
            await ref.read(projectsRepositoryProvider).updateProject(p.id, {'percent_complete': rounded});
            if (ctx.mounted) Navigator.of(ctx).pop(rounded);
          } on AppError catch (e) {
            ref.read(apiServiceProvider).handled(e);
            setD(() {
              saving = false;
              err = e.bareMessage;
            });
          }
        }

        return AlertDialog(
          title: const Text('Project progress'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(suffixText: '%', errorText: err),
            onChanged: (_) => setD(() => err = null),
            onSubmitted: (_) => commit(),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            TextButton(onPressed: saving ? null : commit, child: const Text('Save')),
          ],
        );
      }),
    );
    if (saved == null || !mounted) return;
    ref.invalidate(projectDetailProvider(p.id));
    ref.invalidate(projectsScopedProvider);
    ref.read(toastProvider.notifier).show('Progress set to $saved%');
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
      onTap: () {
        if (!ensurePermission(ref, 'project_task', PermVerb.create)) return;
        context.push('${Routes.createTask}?project=${p.id}');
      },
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
      onTap: _uploading
          ? null
          : () {
              if (!ensurePermission(ref, 'project', PermVerb.update)) return;
              _pickAndUpload(p);
            },
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

  /// The Tasks tab when this project's task fetch failed: the reason and a
  /// retry, never another list standing in for it.
  Widget _tasksError(Project p, Object error) {
    final e = error is AppError ? error : null;
    final offline = e?.type == AppErrorType.network || e?.type == AppErrorType.timeout;
    return _tabEmpty(
      offline ? PhosphorIconsRegular.wifiSlash : PhosphorIconsRegular.warningCircle,
      offline ? "Can't reach Clozr" : "Couldn't load tasks",
      e?.message ?? 'Something went wrong. Please try again.',
      action: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.invalidate(projectTasksProvider(p.id)),
        child: Container(
          height: 44.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11.r),
            border: Border.all(color: AppColors.borderInput),
          ),
          child: Text('Retry',
              style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textBody)),
        ),
      ),
    );
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
    final notes = ref.read(crmNotesProvider(seed).notifier);
    return NotesThread(
      key: _notesKey,
      author: ref.watch(noteAuthorProvider),
      notes: ref.watch(crmNotesProvider(seed)),
      onAddNote: (body, atts) => notes.addNote(body, atts, ref.read(noteAuthorProvider)),
      onAddReply: (noteId, body) => notes.addReply(noteId, body, ref.read(noteAuthorProvider)),
      // Webapp NotesPanel (related_to=project): Tag · Insert (no @mention
      // source for projects), author-only pin / edit / delete.
      webappToolbar: true,
      noteTypes: ref.watch(noteTypesProvider).valueOrNull ?? const [],
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

  /// The project's audit trail — webapp `GET /projects/projects/{id}/activity/`:
  /// the change (or summary), then "user · time ago". Empty → "No activity
  /// recorded yet."; the derived rows survive only for mock mode.
  Widget _auditLog(Project p, StatusMeta meta, String mgrName) {
    if (!ApiConfig.apiEnabled) return OpsAuditLog(entries: _audit(p, meta, mgrName));
    final async = ref.watch(projectFeedProvider(p.id));
    final entries = async.valueOrNull ?? const <crm_audit.AuditEntry>[];
    return OpsAuditLog(
      entries: [for (final e in entries) _auditRow(e)],
      emptyText: async.isLoading && entries.isEmpty ? 'Loading audit log…' : 'No activity recorded yet.',
    );
  }

  /// One audit row as a timeline entry, iconed by what kind of event it was.
  AuditEntry _auditRow(crm_audit.AuditEntry e) {
    final (icon, tone, bg) = switch (e.kind) {
      AuditEventKind.created => (PhosphorIconsRegular.plusCircle, AppColors.pending, AppColors.tintPurple),
      AuditEventKind.statusChanged => (PhosphorIconsRegular.arrowsClockwise, AppColors.blueBright, AppColors.blueSubtle),
      AuditEventKind.noteAdded => (PhosphorIconsRegular.note, AppColors.pending, AppColors.tintPurple),
      AuditEventKind.childAdded => (PhosphorIconsRegular.listChecks, AppColors.success, AppColors.tintGreen),
      AuditEventKind.deleted => (PhosphorIconsRegular.trash, AppColors.error, AppColors.tintRed),
      _ => (PhosphorIconsRegular.pencilSimple, AppColors.blueBright, AppColors.blueSubtle),
    };
    final sub = [e.actor, _timeAgo(e.at)].where((s) => s.isNotEmpty).join(' · ');
    return AuditEntry(icon: icon, tone: tone, bg: bg, title: e.title, sub: sub);
  }

  /// Webapp `timeAgo`: "Just now", "5m ago", "3h ago", "2d ago", then a date.
  static String _timeAgo(DateTime? at) {
    if (at == null) return '';
    final secs = DateTime.now().difference(at).inSeconds.clamp(0, 1 << 31);
    if (secs < 60) return 'Just now';
    final mins = (secs / 60).round();
    if (mins < 60) return '${mins}m ago';
    final hrs = (mins / 60).round();
    if (hrs < 24) return '${hrs}h ago';
    final days = (hrs / 24).round();
    if (days < 30) return '${days}d ago';
    return absoluteDate(at.toLocal());
  }

  /// The derived rows — mock mode only.
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
    final locked = _isClosed(project, status);
    // Webapp: Edit needs `project` update; status and archive are governed
    // fields, so they also need the record's `can_manage`.
    final canUpdate = hasPermission(ref, 'project', PermVerb.update);
    final canManage = canUpdate && project.canManage != false;
    final manageReason = canUpdate ? _governedCopy : permissionCopy(PermVerb.update);

    await showActionMenu(
      context,
      title: project.name,
      actions: [
        MenuAction(
          icon: PhosphorIconsRegular.pencilSimple,
          label: 'Edit project',
          enabled: !locked && canUpdate,
          sublabel: locked
              ? 'Locked while $status'
              : canUpdate
                  ? null
                  : permissionCopy(PermVerb.update),
          onTap: () => context.push('${Routes.editProject}?id=${project.id}'),
        ),
        MenuAction(
          icon: PhosphorIconsRegular.arrowsClockwise,
          label: 'Change status',
          enabled: canManage,
          sublabel: canManage ? null : manageReason,
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
          enabled: canManage,
          sublabel: !canManage
              ? manageReason
              : project.isArchived
                  ? 'Currently archived'
                  : null,
          destructive: !project.isArchived,
          onTap: () => _archive(project),
        ),
      ],
    );
  }

  /// Webapp governance note for a field only the owner, manager or an admin
  /// may change.
  static const _governedCopy =
      'Only the project owner, manager or an admin can change this.';

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
    if (!ensurePermission(ref, 'project', PermVerb.update)) return;
    if (project.canManage == false) {
      ref.read(toastProvider.notifier).showError(_governedCopy);
      return;
    }

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
    final repo = ref.read(projectsRepositoryProvider);
    var done = 'Status updated';
    try {
      await repo.updateProject(project.id, {'status': chosen});
    } on Object catch (e) {
      if (!mounted) return;
      // Closing with open tasks is a question, not an error (webapp D24):
      // confirm, then resend the same write with `open_tasks_action: cancel`.
      final conflict = openTasksConflict(e);
      var closed = false;
      if (conflict != null) {
        if (e is AppError) ref.read(apiServiceProvider).handled(e);
        if (await confirmCloseWithOpenTasks(context, conflict.count)) {
          try {
            await repo.updateProject(
                project.id, {'status': chosen, ...openTasksActionCancel});
            closed = true;
            done = closedWithOpenTasksMessage(conflict.count);
          } on Object catch (e2) {
            if (mounted) {
              toast.showError(e2 is AppError ? e2.bareMessage : 'Could not update the status.');
            }
          }
        }
      } else {
        toast.showError(e is AppError ? e.bareMessage : 'Could not update the status.');
      }
      if (!closed) {
        if (mounted) setState(() => _status = previous);
        return;
      }
    }
    if (!mounted) return;
    // The record, every list query and the tab counts all moved.
    ref.invalidate(projectDetailProvider(project.id));
    ref.invalidate(projectsScopedProvider);
    ref.invalidate(projectStatusCountsProvider);
    toast.show(done);

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
