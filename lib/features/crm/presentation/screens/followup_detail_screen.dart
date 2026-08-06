import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/relative_time.dart';
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
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/attachments_providers.dart';
import '../../application/providers/audit_log_providers.dart';
import '../../application/providers/crm_catalog_providers.dart';
import '../../application/providers/crm_notes_providers.dart';
import '../../application/providers/crm_tasks_providers.dart';
import '../../application/providers/customers_providers.dart';
import '../../application/providers/followups_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../../domain/entities/audit_entry.dart';
import '../../domain/entities/followup.dart';
import '../../domain/entities/lead_file.dart';
import '../components/crm_async.dart';
import '../components/crm_detail_parts.dart';
import '../components/option_picker_sheet.dart';
import '../sheets/reschedule_sheet.dart';
import 'crm_status_sheet.dart';

/// Follow-up kind → Phosphor glyph (mirrors the prototype's FUKIND map).
const _fuKindIcons = <String, IconData>{
  'Call': PhosphorIconsRegular.phone,
  'Meeting': PhosphorIconsRegular.usersThree,
  'Site visit': PhosphorIconsRegular.mapPin,
  'Email': PhosphorIconsRegular.envelopeSimple,
  'Callback': PhosphorIconsRegular.phoneIncoming,
  'Payment': PhosphorIconsRegular.currencyInr,
};

class FollowupDetailScreen extends ConsumerStatefulWidget {
  const FollowupDetailScreen({super.key});

  @override
  ConsumerState<FollowupDetailScreen> createState() => _FollowupDetailScreenState();
}

class _FollowupDetailScreenState extends ConsumerState<FollowupDetailScreen> {
  final _notesKey = GlobalKey<NotesThreadState>();

  /// True while an upload is in flight, so the button reports progress and
  /// refuses a second batch on top of the first.
  bool _uploading = false;

  /// Scrolls the notes card into view and focuses the composer (#13).
  void _focusNotes() {
    final ctx = _notesKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 300), alignment: 0.05, curve: Curves.easeOut);
    }
    _notesKey.currentState?.focusComposer();
  }

  /// Records a status change for an existing follow-up, applying an optimistic
  /// override so the detail + list reflect it immediately. In API mode the write
  /// is awaited: on failure the override is rolled back to its prior value and
  /// the error is surfaced; [successMessage] is toasted only after the write
  /// lands. Mock mode is unchanged (optimistic + success toast).
  Future<void> _setStatus(WidgetRef ref, String id, String status, String successMessage) async {
    final prev = ref.read(followupStatusOverrideProvider);
    ref.read(followupStatusOverrideProvider.notifier).state = {...prev, id: status};
    if (ApiConfig.apiEnabled) {
      try {
        await ref.read(followupsRepositoryProvider).setFollowupDone(id, status == 'done');
      } on AppError catch (e) {
        final rolled = {...ref.read(followupStatusOverrideProvider)};
        if (prev.containsKey(id)) {
          rolled[id] = prev[id]!;
        } else {
          rolled.remove(id);
        }
        ref.read(followupStatusOverrideProvider.notifier).state = rolled;
        ref.read(toastProvider.notifier).show(e.message);
        return;
      }
    }
    ref.read(toastProvider.notifier).show(successMessage);
  }

  void _openFollowupMenu(Followup fu) {
    showActionMenu(
      context,
      actions: [
        MenuAction(
          icon: PhosphorIconsRegular.pencilSimple,
          label: 'Edit follow-up',
          onTap: () => context.push('${Routes.editFollowup}?id=${fu.id}'),
        ),
        MenuAction(
          icon: PhosphorIconsRegular.calendarPlus,
          label: 'Reschedule',
          onTap: () => _reschedule(fu),
        ),
        MenuAction(icon: PhosphorIconsRegular.notePencil, label: 'Add note', onTap: _focusNotes),
        MenuAction(
          icon: PhosphorIconsRegular.trash,
          label: 'Delete follow-up',
          destructive: true,
          onTap: () => _delete(fu),
        ),
      ],
    );
  }

  /// Moves the due date/time — `PATCH /crm/tasks/{id}/`.
  ///
  /// Its own action rather than a trip through the whole edit form: changing
  /// when a follow-up happens is the single most common edit, and the form's
  /// field set is the org's, which may not even surface the due date.
  Future<void> _reschedule(Followup fu) async {
    final picked = await showRescheduleSheet(
      context: context,
      ref: ref,
      due: fu.due,
      time: fu.time,
    );
    if (picked == null || !mounted) return;

    try {
      // A follow-up is a Task, so the task write serves it.
      await ref.read(crmTasksRepositoryProvider).updateTask(fu.id, picked);
    } on AppError catch (e) {
      if (mounted) ref.read(toastProvider.notifier).show(e.message);
      return;
    }
    if (!mounted) return;
    _refreshAfterWrite(fu);
    ref.read(toastProvider.notifier).show('Follow-up rescheduled');
  }

  /// Deletes the follow-up, behind a confirmation — it cannot be undone.
  Future<void> _delete(Followup fu) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete follow-up?'),
        content: Text(
            '"${fu.agenda.isEmpty ? '${fu.kind} follow-up' : fu.agenda}" will be '
            'removed. This cannot be undone.'),
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

    try {
      await ref.read(crmTasksRepositoryProvider).deleteTask(fu.id);
    } on AppError catch (e) {
      if (mounted) ref.read(toastProvider.notifier).show(e.message);
      return;
    }
    if (!mounted) return;
    // Leave **first**: the record this screen is showing no longer exists, and
    // staying on it means the activity log — which refetches off the write
    // tick — immediately asks the API for the audit trail of a deleted task.
    context.pop();
    _refreshAfterWrite(fu);
    ref.read(toastProvider.notifier).show('Follow-up deleted');
  }

  /// Moves the follow-up to one of the org's own task lanes.
  ///
  /// Not the built-in overdue / due / done: those are **derived** display
  /// states — `overdue` and `due` are computed from the due date, so neither is
  /// something the server can be told. The real statuses are the org's task
  /// lanes (a follow-up is a Task), written as `status_id`.
  ///
  /// Falls back to the old done/not-done sheet while the catalog is empty, so
  /// mock mode and a failed catalog fetch still work.
  Future<void> _pickStatus(Followup fu) async {
    var lanes = ref.read(taskStatusOptionsProvider);
    if (lanes.isEmpty && ApiConfig.apiEnabled) {
      // The synchronous view is empty both while the fetch is in flight and
      // when it failed, and those need opposite answers. Awaiting the future
      // settles it: a tap that beats the catalog still gets the real lanes
      // rather than dropping to the built-in list.
      try {
        lanes = await ref.read(taskStatusCatalogProvider.future);
      } on Object {
        lanes = const [];
      }
      if (!mounted) return;
    }
    if (lanes.isEmpty) {
      showCrmStatusSheet(
        context: context,
        ref: ref,
        title: 'Update follow-up status',
        options: const ['overdue', 'due', 'done'],
        meta: StatusMeta$.followup,
        current: fu.status,
        onSelect: (k) => _setStatus(
            ref, fu.id, k, 'Status set to ${StatusMeta$.followup[k]!.label}'),
      );
      return;
    }

    final current = fu.statusName.trim().toLowerCase();
    final picked = await showOptionPicker(
      context: context,
      title: 'Update follow-up status',
      options: lanes,
      selected: {
        for (final l in lanes)
          if (l.name.trim().toLowerCase() == current) l.id,
      },
    );
    if (picked == null || picked.isEmpty || !mounted) return;

    try {
      await ref
          .read(crmTasksRepositoryProvider)
          .updateTask(fu.id, {'status_id': picked.first});
    } on AppError catch (e) {
      // An org can require a note before a follow-up may be completed; the
      // server says so, and the status stays put.
      if (mounted) ref.read(toastProvider.notifier).show(e.message);
      return;
    }
    if (!mounted) return;
    _refreshAfterWrite(fu);
    final name = lanes.firstWhere((l) => l.id == picked.first).name;
    ref.read(toastProvider.notifier).show('Status set to $name');
  }

  /// Drops every list holding a copy of this follow-up.
  ///
  /// The activity log is deliberately absent: it refetches off the API write
  /// tick, so it picks up this change — and any other the app makes — without
  /// being told about each one.
  void _refreshAfterWrite(Followup fu) {
    ref.invalidate(followupsProvider);
    ref.invalidate(taskRowProvider(fu.id));
    final leadId = fu.leadId;
    if (leadId != null) ref.invalidate(leadFollowupsProvider(leadId));
  }

  /// Wraps a loading / error / not-found state under the section app bar so the
  /// back control stays available in every state.
  Widget _stateScaffold(Widget child) => Container(
        color: AppColors.bgDetail,
        child: Column(
          children: [
            DetailAppBar(section: 'Follow-up', onBack: () => context.pop()),
            Expanded(child: child),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final async = ref.watch(followupsProvider);
    return async.when(
      loading: () => _stateScaffold(const DetailSkeleton()),
      error: (e, _) => _stateScaffold(
        ErrorState.forError(crmAppError(e), onRetry: () => ref.invalidate(followupsProvider)),
      ),
      data: (_) => _buildFollowup(context, id),
    );
  }

  Widget _buildFollowup(BuildContext context, String id) {
    final fu = ref.watch(followupByIdProvider(id));
    if (fu == null) {
      return _stateScaffold(const EmptyState(
        icon: PhosphorIconsRegular.clock,
        title: 'Follow-up not found',
        body: 'This follow-up may have been removed or you no longer have access to it.',
      ));
    }

    // Watched here so the org's task lanes are loading from the moment the
    // screen opens, rather than starting on the first tap of the status pill —
    // a tap that beat the fetch used to land on the built-in fallback list.
    ref.watch(taskStatusCatalogProvider);

    // The org's own status name, so the detail page reads "In Progress" rather
    // than folding it into the built-in Upcoming bucket.
    final meta = followupStatusMeta(fu, ref.watch(taskStatusOptionsProvider));
    final owner = MockUsers.of(fu.owner);
    final done = fu.status == 'done';
    final title = fu.agenda.isNotEmpty ? fu.agenda : '${fu.kind} — ${fu.company}';

    // Resolve the related record for the "Related" card.
    final customers = ref.watch(customersProvider).valueOrNull ?? const [];
    final leads = ref.watch(leadsProvider).valueOrNull ?? const [];
    String relatedName = fu.company;
    String relatedSub = '—';
    String? relatedRoute;
    String? relatedId;
    if (fu.custId != null) {
      final c = customers.where((c) => c.id == fu.custId).toList();
      if (c.isNotEmpty) {
        relatedName = c.first.company ?? c.first.name;
        relatedSub = 'Customer · #${c.first.id}';
        relatedRoute = Routes.customerDetail;
        relatedId = c.first.id;
      }
    } else if (fu.leadId != null) {
      final l = leads.where((l) => l.id == fu.leadId).toList();
      if (l.isNotEmpty) {
        relatedName = l.first.company ?? l.first.name;
        relatedSub = 'Lead · #${l.first.id}';
        relatedRoute = Routes.leadDetail;
        relatedId = l.first.id;
      }
    }

    // Notes thread (#13) — follow-ups start with an empty thread; the shared
    // composer stays usable regardless of the follow-up's status.
    final notesSeed = CrmNotesSeed('FU-${fu.id}', () => <NoteEntry>[], apiModel: 'task');
    final notes = ref.watch(crmNotesProvider(notesSeed));

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: 'Follow-up',
            name: title,
            onBack: () => context.pop(),
            trailing: DetailIconAction(
              icon: PhosphorIconsBold.dotsThreeVertical,
              onTap: () => _openFollowupMenu(fu),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
              children: [
                _headCard(context, ref, fu, meta),
                SizedBox(height: 14.h),
                _relatedCard(context, relatedName, relatedSub, relatedRoute, relatedId),
                SizedBox(height: 14.h),
                _detailsCard(fu, meta, owner),
                SizedBox(height: 14.h),
                _filesCard(fu),
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
                _activityCard(fu),
              ],
            ),
          ),
          _bottomBar(ref, fu, done),
        ],
      ),
    );
  }

  Widget _headCard(BuildContext context, WidgetRef ref, Followup fu, StatusMeta meta) {
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
                width: 40.w,
                height: 40.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(11.r)),
                child: Icon(_fuKindIcons[fu.kind] ?? PhosphorIconsRegular.phone, size: 19.sp, color: AppColors.navy),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fu.company, style: AppText.custom(size: 19, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                    SizedBox(height: 3.h),
                    Text('${fu.kind} follow-up · ${fu.contact}', style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    SizedBox(height: 5.h),
                    Text('Due ${fu.due} · ${fu.time}',
                        style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: fu.status == 'overdue' ? AppColors.error : AppColors.textLabelAlt)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 13.h),
          GestureDetector(
            onTap: () => _pickStatus(fu),
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
          ),
        ],
      ),
    );
  }

  Widget _relatedCard(BuildContext context, String name, String sub, String? route, String? id) {
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 15.h),
      onTap: route == null ? null : () => context.push('$route?id=$id'),
      child: Row(
        children: [
          Container(
            width: 42.w,
            height: 42.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(12.r)),
            child: Icon(PhosphorIconsRegular.buildings, size: 20.sp, color: AppColors.navy),
          ),
          SizedBox(width: 13.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RELATED', style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.5)),
                SizedBox(height: 2.h),
                Text(name, style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 1.h),
                Text(sub, style: AppText.caption()),
              ],
            ),
          ),
          Icon(PhosphorIconsBold.caretRight, size: 15.sp, color: AppColors.textPlaceholder),
        ],
      ),
    );
  }

  Widget _detailsCard(Followup fu, StatusMeta meta, dynamic owner) {
    final rows = <(String, String)>[
      ('Type', fu.kind),
      ('Status', meta.label),
      ('Due', '${fu.due} · ${fu.time}'),
      ('Contact', fu.contact),
      ('Follow-up ID', '#${fu.id}'),
      ('Owner', owner.name),
    ];
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.all(18.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Details', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 6.h),
          for (int i = 0; i < rows.length; i++)
            DetailInfoRow(label: rows[i].$1, value: rows[i].$2, last: i == rows.length - 1),
          SizedBox(height: 14.h),
          Text('AGENDA', style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.5)),
          SizedBox(height: 6.h),
          Text(fu.agenda.isEmpty ? '—' : fu.agenda,
              style: AppText.custom(size: 14, weight: FontWeight.w500, color: AppColors.textSecondary).copyWith(height: 1.55)),
        ],
      ),
    );
  }

  /// The follow-up's attachments, from the shared polymorphic table. A
  /// follow-up is a Task, so the link is `related_to=task`.
  Widget _filesCard(Followup fu) {
    final files = ref.watch(taskFilesProvider(fu.id)).valueOrNull ?? const <LeadFile>[];
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.paperclip, size: 16.sp, color: AppColors.textLabelAlt),
              SizedBox(width: 7.w),
              Text('Files', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
              const Spacer(),
              GestureDetector(
                onTap: _uploading ? null : () => _uploadFiles(fu),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(9.r), border: Border.all(color: const Color(0xFFE6E7EA))),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsRegular.uploadSimple, size: 13.sp, color: AppColors.textSecondary),
                      SizedBox(width: 6.w),
                      Text(_uploading ? 'Uploading…' : 'Upload', style: AppText.bodyStrong()),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          if (files.isEmpty)
            Text('No files attached yet.', style: AppText.caption(color: AppColors.textPlaceholder))
          else
            for (final f in files)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 6.h),
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
                    if (f.uploadedAt.isNotEmpty)
                      Text(f.uploadedAt, style: AppText.caption(color: AppColors.textPlaceholder)),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  /// Picks files off the device and uploads each against this follow-up.
  ///
  /// Uploads run one at a time and stop at the first rejection — pushing the
  /// rest after a failure usually just repeats it.
  Future<void> _uploadFiles(Followup fu) async {
    if (_uploading) return;
    final toast = ref.read(toastProvider.notifier);

    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false, // paths only — a large file should not sit in memory
      );
    } on Object catch (e) {
      // A native plugin added since the last full build is not registered on a
      // hot restart, and every call throws. Report it rather than look inert.
      if (mounted) toast.show('Could not open the file picker: $e');
      return;
    }
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
          relatedToId: fu.id,
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

    if (stored > 0) ref.invalidate(taskFilesProvider(fu.id));
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
        (PhosphorIconsRegular.calendarPlus, AppColors.success, AppColors.tintGreen),
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

  Widget _activityCard(Followup fu) {
    // The follow-up's real audit trail — it is a Task record, so the task log
    // serves it. It refetches off the API write tick, so an edit, a status
    // change, a reschedule, a note or an upload all land here without this card
    // being told about any of them.
    final entries = ref.watch(taskActivityLogProvider(fu.id)).valueOrNull ?? const [];
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

  Widget _bottomBar(WidgetRef ref, Followup fu, bool done) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 22.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: Row(
        children: [
          // The pencil beside Mark done opens the same edit screen as the
          // menu's "Edit follow-up" — it reads as an edit affordance either
          // way, and the task detail screen's bottom bar already behaves so.
          // "Add note" keeps its place in the overflow menu.
          GestureDetector(
            onTap: () => context.push('${Routes.editFollowup}?id=${fu.id}'),
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
              onTap: () => _setStatus(ref, fu.id, done ? 'due' : 'done', done ? 'Follow-up reopened' : 'Follow-up marked done'),
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
                    Text(done ? 'Done · reopen' : 'Mark done',
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
