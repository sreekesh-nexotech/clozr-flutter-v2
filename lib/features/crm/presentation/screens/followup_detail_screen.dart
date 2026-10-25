import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers/record_presence_providers.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/utils/attachment_link.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../../data/api/roster.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../data/api/status_keys.dart';
import '../../../../core/models/note.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/keyboard_visibility.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/notes_thread.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/attachments_providers.dart';
import '../../application/providers/audit_log_providers.dart';
import '../../application/providers/crm_catalog_providers.dart';
import '../../application/providers/crm_notes_providers.dart';
import '../../application/providers/crm_tasks_providers.dart';
import '../../application/providers/followups_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../../application/followup_detail_rules.dart';
import '../../application/record_rows.dart';
import '../../domain/entities/audit_entry.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/followup.dart';
import '../../domain/entities/lead_file.dart';
import '../../domain/entities/view_schema.dart';
import '../../infrastructure/data_sources/remote/crm_catalog_remote_ds.dart' show hexColor;
import '../components/crm_async.dart';
import '../components/crm_detail_parts.dart';
import '../components/due_date_change.dart';
import '../components/inline_edit_row.dart';
import '../components/option_picker_sheet.dart';
import '../components/sla_clocks_section.dart';
import '../sheets/add_sheet_kit.dart';
import '../sheets/reschedule_sheet.dart';
import 'crm_status_sheet.dart';
import '../../../auth/presentation/components/permission_guard.dart';

export '../../application/followup_detail_rules.dart' show followupDeleteMessage;

/// Follow-up kind → Phosphor glyph (mirrors the prototype's FUKIND map).
const _fuKindIcons = <String, IconData>{
  'Call': PhosphorIconsRegular.phone,
  'Meeting': PhosphorIconsRegular.usersThree,
  'Site visit': PhosphorIconsRegular.mapPin,
  'Site Visit': PhosphorIconsRegular.mapPin,
  'Email': PhosphorIconsRegular.envelopeSimple,
  'WhatsApp': PhosphorIconsRegular.whatsappLogo,
  'Callback': PhosphorIconsRegular.phoneIncoming,
  'Payment': PhosphorIconsRegular.currencyInr,
};

/// `GET /crm/followup-settings/` — follow-ups keep their own reopen rule;
/// null on failure.
final _followupSettingsProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  try {
    final body = await ref.read(apiServiceProvider).get('/crm/followup-settings/', quiet: true);
    return body is Map ? Map<String, dynamic>.from(body) : null;
  } on Object {
    return null;
  }
});

class FollowupDetailScreen extends ConsumerStatefulWidget {
  const FollowupDetailScreen({super.key});

  @override
  ConsumerState<FollowupDetailScreen> createState() => _FollowupDetailScreenState();
}

class _FollowupDetailScreenState extends ConsumerState<FollowupDetailScreen> {
  final _notesKey = GlobalKey<NotesThreadState>();

  /// Webapp sub-tabs of the right-hand card: 0 = Description, 1 = Files.
  int _tab = 0;

  /// True while an upload is in flight, so the button reports progress and
  /// refuses a second batch on top of the first.
  bool _uploading = false;

  /// Drives [_focusNotes] — the page list has to be scrollable from code for
  /// the notes card to be reachable before it has been built.
  final ScrollController _notesScrollCtrl = ScrollController();

  @override
  void dispose() {
    _notesScrollCtrl.dispose();
    super.dispose();
  }

  /// The record write path — a follow-up is only found under the flag.
  static String _path(String id) => '${ApiEndpoints.crmTask(id)}?is_followup=true';

  /// Webapp: inline editing on this page follows the **task** permission
  /// (`useModulePermissions(MODULE_KEYS.task)`); completing, deleting, files
  /// and people are gated by the server alone.
  bool get _canEdit => hasPermission(ref, 'task', PermVerb.update);

  static const reopenOffHint = followupReopenOffHint;

  bool _reopenBlocked(bool done) {
    if (!done) return false;
    final settings = ref.watch(_followupSettingsProvider).valueOrNull;
    return settings != null && settings['reopen_completed_tasks'] != true;
  }

  /// Scrolls the notes card into view and focuses its composer (#13).
  ///
  /// The page is a lazy [ListView], so when the notes card is below the fold it
  /// has not been built and its key has no context — `ensureVisible` then does
  /// nothing at all, which is what made this action look dead. Nudging the list
  /// towards the end first forces the card to build, and the second pass lands
  /// on it precisely. Matches the lead and task detail screens.
  Future<void> _focusNotes() async {
    if (_notesKey.currentContext == null && _notesScrollCtrl.hasClients) {
      await _notesScrollCtrl.animateTo(
        _notesScrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    final ctx = _notesKey.currentContext;
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 240), alignment: 0.05, curve: Curves.easeOut);
    }
    if (!mounted) return;
    _notesKey.currentState?.focusComposer();
  }

  /// Moves the follow-up to [lane] — `PATCH status_id` — with an optimistic
  /// override, rolled back on failure with the server's own words (webapp: a
  /// missing note reads "A task must have at least one note before it can be
  /// completed.").
  Future<void> _setLane(Followup fu, CatalogOption lane, String success) async {
    final key = crmTaskStatusKey(name: lane.name, type: lane.statusType) == 'done'
        ? 'done'
        // Completing does not change the due date, so a reopened follow-up
        // returns to whichever side of today it was already on.
        : (fu.status == 'overdue' ? 'overdue' : 'due');
    final prev = ref.read(followupStatusOverrideProvider);
    ref.read(followupStatusOverrideProvider.notifier).state = {
      ...prev,
      fu.id: FollowupStatusOverride(key: key, name: lane.name),
    };
    try {
      await ref.read(crmTasksRepositoryProvider).updateTask(fu.id, {'status_id': lane.id}, isFollowup: true);
    } on AppError catch (e) {
      final rolled = {...ref.read(followupStatusOverrideProvider)};
      if (prev.containsKey(fu.id)) {
        rolled[fu.id] = prev[fu.id]!;
      } else {
        rolled.remove(fu.id);
      }
      ref.read(followupStatusOverrideProvider.notifier).state = rolled;
      ref.read(apiServiceProvider).handled(e);
      if (mounted) ref.read(toastProvider.notifier).showError(e.bareMessage);
      return;
    }
    if (!mounted) return;
    _refreshAfterWrite(fu);
    ref.read(toastProvider.notifier).show(success);
  }

  /// The org's lanes, awaited when the synchronous view is still empty.
  Future<List<CatalogOption>> _lanes() async {
    var lanes = ref.read(taskStatusOptionsProvider);
    if (lanes.isEmpty && ApiConfig.apiEnabled) {
      try {
        lanes = await ref.read(taskStatusCatalogProvider.future);
      } on Object {
        lanes = const [];
      }
    }
    return lanes;
  }

  /// Webapp `toggleComplete`: Mark complete → the first completed lane; Mark
  /// as not done → the first open lane (or the default).
  Future<void> _toggleComplete(Followup fu, bool done) async {
    if (_reopenBlocked(done)) {
      ref.read(toastProvider.notifier).show(reopenOffHint);
      return;
    }
    if (!ApiConfig.apiEnabled) {
      final prev = ref.read(followupStatusOverrideProvider);
      ref.read(followupStatusOverrideProvider.notifier).state = {
        ...prev,
        fu.id: FollowupStatusOverride(key: done ? 'due' : 'done'),
      };
      ref.read(toastProvider.notifier).show('Status updated');
      return;
    }
    final lanes = await _lanes();
    if (!mounted) return;
    String keyOf(CatalogOption l) => crmTaskStatusKey(name: l.name, type: l.statusType);
    final target = done
        ? (lanes.where((l) => l.statusType == 'open').firstOrNull ?? lanes.where((l) => keyOf(l) != 'done').firstOrNull)
        : lanes.where((l) => keyOf(l) == 'done').firstOrNull;
    if (target == null) return;
    await _setLane(fu, target, 'Status updated');
  }

  void _openFollowupMenu(Followup fu, bool done) {
    final noUpdate = _canEdit ? null : permissionCopy(PermVerb.update);
    showActionMenu(
      context,
      actions: [
        MenuAction(
          icon: PhosphorIconsRegular.pencilSimple,
          label: 'Edit follow-up',
          enabled: _canEdit,
          sublabel: noUpdate,
          onTap: () => context.push('${Routes.editFollowup}?id=${fu.id}'),
        ),
        MenuAction(
          icon: PhosphorIconsRegular.calendarPlus,
          label: 'Reschedule',
          enabled: _canEdit,
          sublabel: noUpdate,
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

  /// PATCH one or more fields; due-date moves go through the reason flow and
  /// may be sent for approval (202). Webapp toast: "Follow-up updated".
  Future<void> _patch(Followup fu, Map<String, dynamic> fields,
      {String success = 'Follow-up updated', String dateKey = 'due_date', String fieldLabel = 'Due date'}) async {
    final row = ref.read(followupRowProvider(fu.id)).valueOrNull;
    final hadDate = '${row?[dateKey] ?? ''}'.isNotEmpty;
    try {
      final r = await writeWithDueDateFlow(context, ref,
          path: _path(fu.id), fields: fields, hadDate: hadDate, dateKey: dateKey, fieldLabel: fieldLabel);
      if (r == DueDateWrite.cancelled || !mounted) return;
      if (r == DueDateWrite.saved) ref.read(toastProvider.notifier).show(success);
    } on AppError catch (e) {
      if (!mounted) return;
      ref.read(apiServiceProvider).handled(e);
      ref.read(toastProvider.notifier).showError(e.statusCode == 403 && e.code == 'committed_due_date_locked'
          ? 'The committed date is locked. Only admins and Executive Leadership can change it.'
          : e.bareMessage);
      return;
    }
    _refreshAfterWrite(fu);
  }

  /// Moves the due date/time — through the same reason / approval flow as an
  /// inline due-date edit.
  Future<void> _reschedule(Followup fu) async {
    final picked = await showRescheduleSheet(
      context: context,
      ref: ref,
      due: fu.due,
      time: fu.time,
    );
    if (picked == null || !mounted) return;
    await _patch(fu, picked);
  }

  /// Deletes the follow-up, behind the webapp's confirmation.
  Future<void> _delete(Followup fu) async {
    final notesSeed = CrmNotesSeed('FU-${fu.id}', () => <NoteEntry>[], apiModel: 'task');
    final notes = ref.read(crmNotesProvider(notesSeed)).length;
    final files = ref.read(taskFilesProvider(fu.id)).valueOrNull?.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete follow-up?'),
        content: Text(followupDeleteMessage(notes, files)),
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

    try {
      await ref.read(crmTasksRepositoryProvider).deleteTask(fu.id, isFollowup: true);
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      if (mounted) ref.read(toastProvider.notifier).showError(e.bareMessage);
      return;
    }
    if (!mounted) return;
    // Leave **first**: the record this screen is showing no longer exists, and
    // staying on it means the activity log — which refetches off the write
    // tick — immediately asks the API for the audit trail of a deleted task.
    context.pop();
    refreshFollowups(ref);
    ref.invalidate(leadFollowupsProvider);
    ref.read(toastProvider.notifier).show('Follow-up deleted');
  }

  /// The org's lanes; a completed follow-up offers only completed lanes while
  /// reopening is off (webapp: the others are disabled with the reason).
  Future<void> _pickStatus(Followup fu) async {
    final lanes = await _lanes();
    if (!mounted) return;
    if (lanes.isEmpty) {
      showCrmStatusSheet(
        context: context,
        ref: ref,
        title: 'Update follow-up status',
        options: const ['overdue', 'due', 'done'],
        meta: StatusMeta$.followup,
        current: fu.status,
        onSelect: (k) => _toggleComplete(fu, fu.status == 'done'),
      );
      return;
    }
    final current = fu.statusName.trim().toLowerCase();
    showCrmStatusSheet(
      context: context,
      ref: ref,
      title: 'Update follow-up status',
      options: [for (final s in lanes) s.name],
      meta: {for (final s in lanes) s.name: StatusMeta(s.name, crmTaskStatusColor(s))},
      current: lanes.where((s) => s.name.trim().toLowerCase() == current).map((s) => s.name).firstOrNull ?? '',
      onSelect: (name) {
        final lane = lanes.firstWhere((s) => s.name == name);
        final key = crmTaskStatusKey(name: lane.name, type: lane.statusType);
        if (_reopenBlocked(fu.status == 'done') && key != 'done') {
          ref.read(toastProvider.notifier).show(reopenOffHint);
          return;
        }
        if (lane.name.trim().toLowerCase() == current) return;
        _setLane(fu, lane, 'Status updated');
      },
    );
  }

  /// Drops every copy of this follow-up, and re-reads the audit log a few
  /// times — the row lands a moment after the write (webapp: ~0.8, 1.8, 3.2 s).
  void _refreshAfterWrite(Followup fu) {
    refreshFollowups(ref);
    ref.invalidate(followupRowProvider(fu.id));
    ref.invalidate(leadFollowupsProvider);
    for (final ms in const [800, 1800, 3200]) {
      Future<void>.delayed(Duration(milliseconds: ms), () {
        if (mounted) ref.invalidate(followupActivityLogProvider(fu.id));
      });
    }
  }

  /// Pull-to-refresh: the follow-up, its record, attachments, notes, audit
  /// trail and the org's lanes and layout.
  ///
  /// The status override goes too — it only bridges an optimistic change to the
  /// refetch, and keeping it would let a local guess override the server.
  Future<void> _refresh(String id) async {
    ref.read(followupStatusOverrideProvider.notifier).update((s) => {...s}..remove(id));
    refreshFollowups(ref);
    ref.invalidate(followupRowProvider(id));
    ref.invalidate(taskFilesProvider(id));
    ref.invalidate(followupActivityLogProvider(id));
    ref.invalidate(taskStatusCatalogProvider);
    ref.invalidate(followupDetailSchemaFutureProvider);
    ref.invalidate(_followupSettingsProvider);
    ref.invalidate(crmNotesProvider);
    await settle([
      ref.read(followupsProvider.future),
      ref.read(followupRowProvider(id).future),
      ref.read(taskFilesProvider(id).future),
      ref.read(taskStatusCatalogProvider.future),
    ]);
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

  /// "Follow-up not found" with a way back to the list, which is refreshed so the stale
  /// row disappears too.
  Widget _notFound(BuildContext context) => EmptyState(
        icon: PhosphorIconsRegular.clock,
        title: 'Follow-up not found',
        body: 'It may have been deleted or moved.',
        ctaLabel: 'Go to follow-ups',
        onCta: () {
          refreshFollowups(ref);
          context.pop();
        },
      );

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final async = ref.watch(followupsProvider);
    return async.when(
      loading: () => _stateScaffold(const DetailSkeleton()),
      error: (e, _) => _stateScaffold(
        ErrorState.forError(crmAppError(e), onRetry: () => refreshFollowups(ref)),
      ),
      data: (_) => _buildFollowup(context, id),
    );
  }

  Widget _buildFollowup(BuildContext context, String id) {
    final fu = ref.watch(followupByIdProvider(id));
    if (fu == null) return _stateScaffold(_notFound(context));
    // The row above comes from the loaded list, which can outlive the record:
    // ask the record endpoint, and show the webapp's not-found state on a 404.
    final gone = ref.watch(recordGoneProvider(RecordProbe(ApiEndpoints.crmTask(fu.id), const {'is_followup': 'true'}))).valueOrNull ?? false;
    if (gone) return _stateScaffold(_notFound(context));

    // Watched so the lanes and the reopen rule are loaded before the first tap.
    ref.watch(taskStatusCatalogProvider);
    ref.watch(_followupSettingsProvider);

    // The org's own status name, so the detail page reads "In Progress" rather
    // than folding it into the built-in Upcoming bucket.
    final meta = followupStatusMeta(fu, ref.watch(taskStatusOptionsProvider));
    final done = fu.status == 'done';
    final row = ref.watch(followupRowProvider(fu.id)).valueOrNull;
    // The task's own title, not its description — see [FollowupCard].
    final title = fu.title.isNotEmpty ? fu.title : '${fu.kind} — ${fu.company}';

    // Notes thread (#13) — follow-ups start with an empty thread; the shared
    // composer stays usable regardless of the follow-up's status.
    final notesSeed = CrmNotesSeed('FU-${fu.id}', () => <NoteEntry>[], apiModel: 'task');
    final notes = ref.watch(crmNotesProvider(notesSeed));

    // The notes composer lives inside the list below. With the keyboard up the
    // sticky Mark-done bar would sit between it and the keys, so it stands
    // down until the field is dismissed.
    final keyboardOpen = KeyboardVisibility.of(context);
    final pending = row?['pending_due_date_change'];

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
              onTap: () => _openFollowupMenu(fu, done),
            ),
          ),
          Expanded(
            child: AppRefresh(
              onRefresh: () => _refresh(fu.id),
              child: ListView(
              controller: _notesScrollCtrl,
              // Dragging the page puts the keyboard away — the only other exit
              // from the notes composer was submitting or leaving the screen.
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
              children: [
                _headCard(fu, meta, row, title, done),
                SizedBox(height: 14.h),
                // Webapp: SLA clocks (hidden when the server sends none) then
                // the pending due-date banner, under the header (a follow-up's
                // clocks are the task module's).
                LeadSlaClocks(leadId: fu.id, module: 'task'),
                PendingDueDateBanner(pending: pending is Map ? Map<String, dynamic>.from(pending) : null),
                // Webapp actions band: the linked record (Mark complete and
                // Delete sit in the bottom bar, the mobile home for actions).
                _relatedBand(row),
                SizedBox(height: 14.h),
                _infoCard(fu, row),
                SizedBox(height: 14.h),
                _descFilesCard(fu, row),
                SizedBox(height: 14.h),
                NotesThread(
                  author: ref.watch(noteAuthorProvider),
                  key: _notesKey,
                  notes: notes,
                  onAddNote: (body, atts) =>
                      ref.read(crmNotesProvider(notesSeed).notifier).addNote(body, atts, ref.read(noteAuthorProvider)),
                  onAddReply: (noteId, body) =>
                      ref.read(crmNotesProvider(notesSeed).notifier).addReply(noteId, body, ref.read(noteAuthorProvider)),
                  // Webapp NotesPanel (`task`): Tag, @mention from the org's
                  // user directory, and Insert.
                  webappToolbar: true,
                  noteTypes: ref.watch(noteTypesProvider).valueOrNull ?? const [],
                  mentionables: ref.watch(taskMentionUsersProvider).valueOrNull ?? const [],
                  onAddTypedNote: (body, atts, typeId, typeName, mentions) => ref
                      .read(crmNotesProvider(notesSeed).notifier)
                      .addNote(body, atts, ref.read(noteAuthorProvider),
                          noteTypeId: typeId, noteTypeName: typeName, mentionedUserIds: mentions),
                ),
                SizedBox(height: 14.h),
                _auditCard(fu),
              ],
              ),
            ),
          ),
          if (!keyboardOpen) _bottomBar(fu, done),
        ],
      ),
    );
  }

  /// The type as the record has it (the list card's payload may omit it).
  String _type(Followup fu, Map<String, dynamic>? row) {
    final rec = '${row?['task_type'] ?? ''}'.trim();
    return rec.isNotEmpty && rec != 'null' ? rec : fu.kind;
  }

  /// The record's `related_to` (`{model, id, label, reference}`), or null.
  Map<String, dynamic>? _related(Map<String, dynamic>? row) {
    final r = row?['related_to'];
    return r is Map && r['id'] != null ? Map<String, dynamic>.from(r) : null;
  }

  /// Small uppercase section label (webapp `eyebrow`).
  static Widget _eyebrow(String text) => Text(text.toUpperCase(),
      style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.5));

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final a = parts.first[0];
    final b = parts.length > 1 ? parts.last[0] : '';
    return (a + b).toUpperCase();
  }

  /// Webapp header: title, "<type> · <related label>", "Due 18 Jun 2026 · In
  /// 3d", then Priority and the Status dropdown.
  Widget _headCard(Followup fu, StatusMeta meta, Map<String, dynamic>? row, String title, bool done) {
    final type = _type(fu, row);
    final subtitle = followupSubtitle(type, _related(row));
    final dueLabel = followupDueLabel(row?['due_date'], fallback: row == null ? fu.due : '');
    final tone = followupDueTone(fu.dueNote);
    final toneColor = switch (tone) {
      FollowupDueTone.danger => AppColors.error,
      FollowupDueTone.warn => AppColors.warningDeep,
      FollowupDueTone.none => AppColors.textLabelAlt,
    };
    // The org's own priority name and colour (webapp), not a folded bucket.
    final p = row?['priority'];
    final priorityName = p is Map ? '${p['name'] ?? ''}'.trim() : fu.priority;
    final priorityColor = (p is Map ? hexColor(p['color']) : null) ?? AppColors.textPrimary;
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
                child: Icon(_fuKindIcons[type] ?? PhosphorIconsRegular.checkSquare, size: 19.sp, color: AppColors.navy),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.custom(size: 19, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                    SizedBox(height: 3.h),
                    Text(subtitle, style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    if (dueLabel.isNotEmpty) ...[
                      SizedBox(height: 5.h),
                      Row(
                        children: [
                          Icon(PhosphorIconsRegular.calendarDots, size: 13.sp, color: toneColor),
                          SizedBox(width: 6.w),
                          Flexible(
                            child: Text(
                              fu.dueNote.isEmpty ? 'Due $dueLabel' : 'Due $dueLabel · ${fu.dueNote}',
                              style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: toneColor),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 14)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (priorityName.isNotEmpty) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _eyebrow('Priority'),
                    SizedBox(height: 6.h),
                    Text(priorityName, style: AppText.custom(size: 17, weight: FontWeight.w800, color: priorityColor)),
                  ],
                ),
                SizedBox(width: 24.w),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _eyebrow('Status'),
                    SizedBox(height: 6.h),
                    GestureDetector(
                      onTap: () => _pickStatus(fu),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(9.r),
                          border: Border.all(color: AppColors.borderInput),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 8.w, height: 8.w, decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle)),
                            SizedBox(width: 8.w),
                            Text(meta.label, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                            SizedBox(width: 8.w),
                            Icon(PhosphorIconsBold.caretDown, size: 11.sp, color: AppColors.textMuted2),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Webapp actions band, left half: "Related" and the linked record's card
  /// ("Lead · LD-0304", opens the record), or the internal-follow-up note.
  Widget _relatedBand(Map<String, dynamic>? row) {
    // Until the record arrives, say nothing rather than "not linked".
    if (row == null) return const SizedBox.shrink();
    final r = _related(row);
    final label = '${r?['label'] ?? ''}'.trim();
    if (r == null || label.isEmpty || label == 'null') {
      return ClozrCard(
        radius: 18,
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 15.h),
        child: Row(children: [
          Icon(PhosphorIconsRegular.circleDashed, size: 17.sp, color: AppColors.textPlaceholder),
          SizedBox(width: 10.w),
          Expanded(child: Text(followupUnlinkedText, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted))),
        ]),
      );
    }
    final model = '${r['model'] ?? ''}'.toLowerCase();
    final route = followupRelatedRoute(r,
        lead: Routes.leadDetail, customer: Routes.customerDetail, product: Routes.productDetail, quote: Routes.quoteDetail);
    final icon = switch (model) {
      'lead' => PhosphorIconsRegular.user,
      'customer' => PhosphorIconsRegular.buildings,
      'product' => PhosphorIconsRegular.package,
      'quotation' => PhosphorIconsRegular.fileText,
      _ => PhosphorIconsRegular.link,
    };
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 15.h),
      onTap: route == null ? null : () => context.push(route),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow('Related'),
          SizedBox(height: 10.h),
          Row(
            children: [
              Container(
                width: 38.w,
                height: 38.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(9.r),
                  border: Border.all(color: AppColors.borderCardSoft),
                ),
                child: Icon(icon, size: 18.sp, color: AppColors.navy),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 1.h),
                    Text(followupRelatedCaption(r), style: AppText.caption()),
                  ],
                ),
              ),
              if (route != null) Icon(PhosphorIconsRegular.arrowUpRight, size: 16.sp, color: AppColors.textPlaceholder),
            ],
          ),
        ],
      ),
    );
  }

  /// The built-in rows, used when the org's detail layout has not loaded (and
  /// in mock mode).
  List<(String, String)> _fallbackRows(Followup fu, StatusMeta meta) => [
        ('Type', fu.kind),
        ('Status', meta.label),
        ('Due', [fu.due, if (fu.time.isNotEmpty) fu.time].join(' · ')),
        ('Priority', fu.priority.isEmpty ? '—' : priorityKey(fu.priority)),
      ];

  /// Webapp row rules: Name first; description (the Agenda block), status and
  /// the people (their own card) left out; Committed due date after Due date.
  static const _skipRows = {'title', 'description', 'status', 'assigned_to', 'assignees', 'committed_due_date'};

  /// Rows edited through a picker (long-press) rather than a text box.
  static const _pickerRows = {'priority', 'assigned_team', 'task_type', 'due_date', 'committed_due_date', 'due_time'};

  /// Saves one edited field — trimmed title capped at 280, blank or unchanged
  /// ignored (webapp).
  Future<void> _saveField(Followup fu, String key, Object? value) async {
    if (key == 'title') {
      var t = '${value ?? ''}'.trim();
      if (t.length > 280) t = t.substring(0, 280);
      if (t.isEmpty || t == fu.title) return;
      value = t;
    }
    await _patch(fu, {key: value});
  }

  Future<void> _pickRow(Followup fu, String name, String label, Map<String, dynamic>? row) async {
    if (!ensurePermission(ref, 'task', PermVerb.update)) return;
    switch (name) {
      case 'priority':
        final opts = [const CatalogOption(id: '__none__', name: 'No priority'), ...ref.read(taskPriorityOptionsProvider)];
        final p = await showOptionPicker(context: context, title: label, options: opts, selected: const {});
        if (p == null || p.isEmpty) return;
        await _patch(fu, {'priority': p.first == '__none__' ? null : p.first});
      case 'assigned_team':
        final teams = await ref.read(assignableTeamsForModuleProvider('followup').future);
        if (!mounted) return;
        final p = await showOptionPicker(
            context: context,
            title: label,
            options: [const CatalogOption(id: '__none__', name: 'No team'), ...teams],
            selected: const {});
        if (p == null || p.isEmpty) return;
        await _patch(fu, {'assigned_team': p.first == '__none__' ? null : p.first});
      case 'task_type':
        // The org's follow-up types (the webapp offers the fixed task types
        // here — a known web quirk; the follow-up's own list is what it stores).
        final types = [for (final t in ref.read(followupTypeOptionsProvider)) CatalogOption(id: t.name, name: t.name)];
        final current = _type(fu, row);
        final p = await showOptionPicker(context: context, title: label, options: types, selected: {current});
        if (p == null || p.isEmpty || p.first == current) return;
        await _patch(fu, {'task_type': p.first});
      case 'due_time':
        // Webapp: a time only rides with a due date.
        if ('${row?['due_date'] ?? ''}'.isEmpty) {
          ref.read(toastProvider.notifier).show('Set a due date first');
          return;
        }
        final t = await pickSheetTime(context, '${row?['due_time'] ?? ''}');
        if (t == null || !mounted) return;
        await _patch(fu, {'due_time': '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'});
      case 'due_date':
      case 'committed_due_date':
        final committed = name == 'committed_due_date';
        if (committed && row?['can_change_committed_date'] != true) {
          ref.read(toastProvider.notifier).show('Locked once set; admins and Executive Leadership can change it');
          return;
        }
        final d = await pickSheetDate(context, '${row?[name] ?? ''}');
        if (d == null || !mounted) return;
        await _patch(fu, {name: sheetIsoDate(d)}, dateKey: name, fieldLabel: committed ? 'Committed due date' : 'Due date');
    }
  }

  /// Webapp custom-field rules (`TaskCustomFieldInput`): the message for a bad
  /// value, or null.
  static String? customFieldProblem(ViewColumn c, String text) {
    final t = text.trim();
    if (t.isEmpty) return c.isRequired ? 'This field is required.' : null;
    switch (c.customType) {
      case 'number':
      case 'decimal':
        return num.tryParse(t) == null ? 'Must be a numeric value.' : null;
      case 'date':
        return DateTime.tryParse(t) == null ? 'Must be a date (YYYY-MM-DD).' : null;
      case 'email':
        return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'Must be a valid email address.';
      case 'url':
        return RegExp(r'^https?://\S+$').hasMatch(t) ? null : 'Must be a valid URL (http:// or https://).';
      case 'text':
        return t.length > ViewColumn.customTextMax ? 'Must be at most ${ViewColumn.customTextMax} characters.' : null;
    }
    return null;
  }

  /// Edits one custom field — `PATCH {custom_fields: {<key>: value}}`, as the
  /// webapp does — with an input fitting its type.
  Future<void> _editCustom(Followup fu, ViewColumn c, Map<String, dynamic>? row) async {
    if (!ensurePermission(ref, 'task', PermVerb.update)) return;
    final custom = row?['custom_fields'] is Map ? row!['custom_fields'] as Map : const {};
    final current = custom[c.customKey];
    Object? value;
    switch (c.customType) {
      case 'date':
        final d = await pickSheetDate(context, '${current ?? ''}');
        if (d == null || !mounted) return;
        value = sheetIsoDate(d);
      case 'boolean':
        final p = await showOptionPicker(
            context: context,
            title: c.label,
            options: const [CatalogOption(id: 'true', name: 'Yes'), CatalogOption(id: 'false', name: 'No')],
            selected: {if (current != null) '$current'});
        if (p == null || p.isEmpty) return;
        value = p.first == 'true';
      default:
        if (c.hasChoices) {
          final p = await showOptionPicker(
              context: context,
              title: c.label,
              options: [for (final (v, l) in c.choices) CatalogOption(id: v, name: l)],
              selected: {if (current != null) '$current'});
          if (p == null || p.isEmpty) return;
          value = p.first;
          break;
        }
        final text = await showDialog<String>(
          context: context,
          builder: (_) => _CustomFieldDialog(column: c, initial: current == null ? '' : '$current'),
        );
        if (text == null || !mounted) return;
        if (text == '${current ?? ''}') return;
        value = text.isEmpty
            ? null
            : const {'number', 'decimal'}.contains(c.customType)
                ? num.parse(text)
                : text;
    }
    await _patch(fu, {'custom_fields': {c.customKey: value}});
  }

  /// Webapp "Follow-up information": Name first, then the org's detail layout
  /// over the record (only the fields it carries), Committed due date after
  /// Due date — and the "Owner & assignees" block at the foot of the card.
  Widget _infoCard(Followup fu, Map<String, dynamic>? row) {
    // The org's own Follow-up detail layout over the follow-up's record
    // (`?view_type=detail&is_followup=true`).
    final schema = ref.watch(followupDetailSchemaProvider);
    final meta = followupStatusMeta(fu, ref.watch(taskStatusOptionsProvider));
    final rows = <(String, String, dynamic, String)>[];
    if (schema.isEmpty || row == null) {
      for (final r in _fallbackRows(fu, meta)) {
        rows.add((r.$1, r.$2, null, ''));
      }
    } else {
      rows.add(('Name', fu.title.isEmpty ? '—' : fu.title, schema.column('title'), 'title'));
      var committedAdded = false;
      void addCommitted() {
        if (committedAdded) return;
        committedAdded = true;
        final v = '${row['committed_due_date'] ?? ''}';
        final moved = rescheduleLabel(row);
        final text = v.isEmpty ? 'Not committed yet' : dueDateLabel(v);
        rows.add(('Committed due date', moved == null ? text : '$text\n$moved', null, 'committed_due_date'));
      }
      for (final r in recordRows(row, schema, skip: _skipRows)) {
        // Webapp: a field the record does not carry has no row.
        if (!followupRecordHasColumn(row, r.column)) continue;
        var value = r.value;
        if (r.name == 'duration' && value != '—') value = '$value min';
        // The org's own priority name, as the webapp shows it.
        if (r.name == 'priority' && row['priority'] is Map) {
          final n = '${(row['priority'] as Map)['name'] ?? ''}'.trim();
          value = n.isEmpty ? '—' : n;
        }
        if (r.name == 'related_to') value = followupRelatedRowValue(row['related_to']);
        // The record sends the team as an id; its name rides beside it.
        if (r.name == 'assigned_team' && row['assigned_team'] != null) {
          final name = '${row['assigned_team_name'] ?? ''}'.trim();
          final team = row['assigned_team'];
          value = name.isNotEmpty ? name : (team is Map ? '${team['name'] ?? value}' : 'Team assigned');
        }
        rows.add((r.label, value, r.column, r.name));
        if (r.name == 'due_date') addCommitted();
      }
      addCommitted();
    }
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.all(18.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Follow-up information', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 6.h),
          // Long-press a row to edit it in place; a row that cannot be edited
          // says why rather than ignoring the press.
          for (int i = 0; i < rows.length; i++)
            Builder(builder: (_) {
              final line = DetailInfoRow(label: rows[i].$1, value: rows[i].$2, last: i == rows.length - 1);
              final col = rows[i].$3;
              if (col is ViewColumn && col.isCustom) {
                // Webapp: a custom field saves as `custom_fields.<key>`.
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: () => _editCustom(fu, col, row),
                  child: line,
                );
              }
              if (_pickerRows.contains(rows[i].$4)) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: () => _pickRow(fu, rows[i].$4, rows[i].$1, row),
                  child: line,
                );
              }
              return InlineEditRow(
                label: rows[i].$1,
                display: rows[i].$2,
                column: _canEdit ? rows[i].$3 : null,
                rawValue: rows[i].$4 == 'title' ? fu.title : row?[rows[i].$3?.name],
                editForm: 'Edit follow-up',
                onSave: (key, value) => _saveField(fu, key, value),
                onBlocked: (msg) => ref.read(toastProvider.notifier).show(_canEdit ? msg : permissionCopy(PermVerb.update)),
                child: line,
              );
            }),
          if (row != null) ...[
            const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 14)),
            _peopleBlock(fu, row),
          ],
        ],
      ),
    );
  }

  // ── Owner & assignees (webapp TaskDetailScreen, inside the info card) ──

  Widget _peopleBlock(Followup fu, Map<String, dynamic> row) {
    final owner = row['assigned_to'] is Map ? row['assigned_to'] as Map : null;
    final ownerId = '${owner?['user_id'] ?? ''}';
    String nameOf(Map u) {
      final n = '${u['full_name'] ?? ''}'.trim();
      return n.isNotEmpty ? n : '${u['username'] ?? 'User'}'.trim();
    }

    final ownerName = owner == null ? '' : nameOf(owner);
    final assignees = [
      for (final a in (row['assignees'] is List ? row['assignees'] as List : const []))
        if (a is Map && a['user_id'] != null) a,
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _eyebrow('Owner & assignees'),
      SizedBox(height: 12.h),
      Row(children: [
        Container(
          width: 38.w,
          height: 38.w,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ownerName.isEmpty ? AppColors.bgChipGrey : AppColors.navy,
            shape: BoxShape.circle,
          ),
          child: ownerName.isEmpty
              ? Icon(PhosphorIconsRegular.user, size: 17.sp, color: AppColors.textMuted)
              : Text(_initials(ownerName), style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.white)),
        ),
        SizedBox(width: 11.w),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ownerName.isEmpty ? 'Unassigned' : ownerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodyStrong(color: ownerName.isEmpty ? AppColors.textPlaceholder : AppColors.textPrimary)),
            Text('Follow-up owner', style: AppText.caption()),
          ]),
        ),
        TextButton.icon(
          onPressed: () => _reassign(fu, ownerId),
          icon: Icon(ownerName.isEmpty ? PhosphorIconsRegular.userPlus : PhosphorIconsRegular.repeat, size: 15.sp),
          label: Text(ownerName.isEmpty ? 'Assign owner' : 'Reassign owner'),
        ),
      ]),
      const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 12)),
      Text('Assignees', style: AppText.caption()),
      SizedBox(height: 8.h),
      if (assignees.isEmpty)
        Text('No assignees yet', style: AppText.caption(color: AppColors.textPlaceholder))
      else
        Wrap(spacing: 8.w, runSpacing: 8.h, children: [
          for (final a in assignees)
            Chip(
              avatar: CircleAvatar(
                backgroundColor: AppColors.navy,
                child: Text(_initials(nameOf(a)), style: AppText.custom(size: 9, weight: FontWeight.w700, color: AppColors.white)),
              ),
              label: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(nameOf(a)),
                // The owner chip carries a dot and no ×: the owner is always
                // an assignee (reassign the owner instead).
                if ('${a['user_id']}' == ownerId) ...[
                  SizedBox(width: 6.w),
                  Tooltip(
                    message: 'Owner',
                    child: Container(width: 7.w, height: 7.w, decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle)),
                  ),
                ],
              ]),
              onDeleted: '${a['user_id']}' != ownerId
                  ? () => _patch(fu, {'assignees': [for (final x in assignees) if (x != a) '${x['user_id']}']}, success: 'Assignee removed')
                  : null,
            ),
        ]),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _addAssignee(fu, [for (final a in assignees) '${a['user_id']}']),
          icon: Icon(PhosphorIconsRegular.userPlus, size: 15.sp),
          label: const Text('Add assignee'),
        ),
      ),
    ]);
  }

  // ── Description / Files (webapp right-hand card) ──

  Widget _descFilesCard(Followup fu, Map<String, dynamic>? row) {
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailUnderlineTabs(labels: const ['Description', 'Files'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
          if (_tab == 0) _descriptionTab(fu, row) else _filesTab(fu),
        ],
      ),
    );
  }

  Widget _descriptionTab(Followup fu, Map<String, dynamic>? row) {
    final written = row != null ? '${row['description'] ?? ''}'.trim() : fu.description.trim();
    final desc = written == 'null' ? '' : written;
    return Padding(
      padding: EdgeInsets.only(top: 14.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: _eyebrow('Description')),
            if (_canEdit)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _editDescription(fu, desc),
                child: Padding(
                  padding: EdgeInsets.all(4.r),
                  child: Icon(PhosphorIconsRegular.pencilSimple, size: 15.sp, color: AppColors.textPlaceholder),
                ),
              ),
          ]),
          SizedBox(height: 8.h),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () => _editDescription(fu, desc),
            child: SizedBox(
              width: double.infinity,
              child: Text(desc.isEmpty ? 'No description.' : desc,
                  style: AppText.custom(
                          size: 14, weight: FontWeight.w500, color: desc.isEmpty ? AppColors.textPlaceholder : AppColors.textSecondary)
                      .copyWith(height: 1.6)),
            ),
          ),
        ],
      ),
    );
  }

  /// Webapp `DescriptionTab`: edit in a box, Cancel / Save — "Description updated".
  Future<void> _editDescription(Followup fu, String current) async {
    if (!ensurePermission(ref, 'task', PermVerb.update)) return;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _DescriptionDialog(initial: current),
    );
    if (text == null || !mounted || text == current) return;
    await _patch(fu, {'description': text}, success: 'Description updated');
  }

  /// The follow-up's attachments, from the shared polymorphic table. A
  /// follow-up is a Task, so the link is `related_to=task`.
  Widget _filesTab(Followup fu) {
    final async = ref.watch(taskFilesProvider(fu.id));
    final files = async.valueOrNull ?? const <LeadFile>[];
    return Padding(
      padding: EdgeInsets.only(top: 14.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _eyebrow('Files')),
              GestureDetector(
                onTap: _uploading ? null : () => _uploadFiles(fu),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 8.h),
                  decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(9.r)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsRegular.uploadSimple, size: 14.sp, color: AppColors.white),
                      SizedBox(width: 7.w),
                      Text(_uploading ? 'Uploading…' : 'Upload file',
                          style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.white)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          if (async.isLoading && files.isEmpty)
            Text('Loading files…', style: AppText.caption())
          else if (async.hasError && files.isEmpty)
            Text(crmAppError(async.error!).message, style: AppText.caption(color: AppColors.error))
          else if (files.isEmpty)
            Text('No files yet.', style: AppText.caption())
          else
            for (int i = 0; i < files.length; i++) _fileRow(fu, files[i], first: i == 0),
        ],
      ),
    );
  }

  /// One attachment: tap opens the stored file, the bin removes it (webapp).
  Widget _fileRow(Followup fu, LeadFile f, {required bool first}) {
    return Container(
      decoration: BoxDecoration(
        border: first ? null : const Border(top: BorderSide(color: Color(0xFFF3F4F5))),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _openFile(f),
              borderRadius: BorderRadius.circular(9.r),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10.h),
                child: Row(
                  children: [
                    Container(
                      width: 34.w,
                      height: 34.w,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(8.r)),
                      child: Icon(attachmentIcon(f.ext), size: 17.sp, color: AppColors.navy),
                    ),
                    SizedBox(width: 11.w),
                    Expanded(
                      child: Text(f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.navy)
                              .copyWith(decoration: TextDecoration.underline)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: () => _removeFile(fu, f),
            icon: Icon(PhosphorIconsRegular.trash, size: 16.sp, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  /// Webapp: removes one attachment (`DELETE /crm/attachments/{id}/`) —
  /// "File removed".
  Future<void> _removeFile(Followup fu, LeadFile f) async {
    final toast = ref.read(toastProvider.notifier);
    if (!ApiConfig.apiEnabled) {
      toast.show('Files are removed once the app is connected to the API.');
      return;
    }
    try {
      await ref.read(apiServiceProvider).delete(ApiEndpoints.attachment(f.id));
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      if (mounted) toast.showError(e.bareMessage);
      return;
    }
    if (!mounted) return;
    ref.invalidate(taskFilesProvider(fu.id));
    _refreshAfterWrite(fu);
    toast.show('File removed');
  }

  Future<List<CatalogOption>> _users() => ref.read(assignableUsersForModuleProvider('followup').future);

  Future<void> _reassign(Followup fu, String currentOwner) async {
    final users = await _users();
    if (!mounted) return;
    final picked = await showOptionPicker(
      context: context,
      title: 'Reassign follow-up owner',
      options: users,
      selected: {if (currentOwner.isNotEmpty) currentOwner},
    );
    if (picked == null || picked.isEmpty || picked.first == currentOwner) return;
    await _patch(fu, {'assigned_to': picked.first}, success: 'Owner updated');
  }

  Future<void> _addAssignee(Followup fu, List<String> current) async {
    final users = [for (final u in await _users()) if (!current.contains(u.id)) u];
    if (!mounted) return;
    final picked = await showOptionPicker(
      context: context,
      title: 'Add assignee',
      options: users,
      selected: const {},
      emptyNote: 'No more users',
    );
    if (picked == null || picked.isEmpty) return;
    await _patch(fu, {'assignees': [...current, picked.first]}, success: 'Assignee added');
  }

  /// Hands one attachment to the OS viewer, reporting why if it cannot be.
  Future<void> _openFile(LeadFile f) async {
    final failure = await openAttachment(f.url);
    if (failure != null && mounted) ref.read(toastProvider.notifier).show(failure);
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

  /// Webapp "Audit log": the follow-up's real trail — "Created follow-up" /
  /// "Updated follow-up" with the diff. It refetches off the API write tick
  /// and again shortly after each write from this page.
  Widget _auditCard(Followup fu) {
    final async = ref.watch(followupActivityLogProvider(fu.id));
    final entries = async.valueOrNull ?? const [];
    final items = [for (final e in entries) _activityRow(e)];
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 6.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.clockCounterClockwise, size: 16.sp, color: AppColors.navy),
              SizedBox(width: 7.w),
              Text('Audit log', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          SizedBox(height: 12.h),
          if (items.isEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: 10.h),
              child: async.hasError
                  ? Text(crmAppError(async.error!).message, style: AppText.caption(color: AppColors.error))
                  : Text(async.isLoading ? 'Loading…' : 'No activity yet.', style: AppText.caption()),
            )
          else
            ActivityTimeline(items: items),
        ],
      ),
    );
  }

  /// Webapp actions band, right half — Delete and Mark complete / Mark as not
  /// done — kept in the mobile bottom bar.
  Widget _bottomBar(Followup fu, bool done) {
    final blocked = _reopenBlocked(done);
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 22.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: 'Delete follow-up',
            child: Semantics(
              button: true,
              label: 'Delete follow-up',
              child: GestureDetector(
                onTap: () => _delete(fu),
                child: Container(
                  width: 48.w,
                  height: 48.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: AppColors.white, borderRadius: BorderRadius.circular(12.r), border: Border.all(color: AppColors.borderInput)),
                  child: Icon(PhosphorIconsRegular.trash, size: 21.sp, color: AppColors.error),
                ),
              ),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: GestureDetector(
              onTap: () => _toggleComplete(fu, done),
              // Webapp: disabled while reopening is off, with the reason.
              child: Opacity(
                opacity: blocked ? 0.5 : 1,
                child: Container(
                  height: 48.h,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: done ? AppColors.white : AppColors.success,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: done ? AppColors.borderInput : AppColors.success),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsBold.check, size: 17.sp, color: done ? AppColors.textSecondary : AppColors.white),
                      SizedBox(width: 8.w),
                      Text(followupCompleteLabel(done),
                          style: AppText.custom(size: 15, weight: FontWeight.w700, color: done ? AppColors.textSecondary : AppColors.white)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Webapp `DescriptionTab` editor: a multi-line box with Cancel / Save. Owns
/// its controller, so it is only disposed once the dialog has finished closing.
class _DescriptionDialog extends StatefulWidget {
  const _DescriptionDialog({required this.initial});

  final String initial;

  @override
  State<_DescriptionDialog> createState() => _DescriptionDialogState();
}

class _DescriptionDialogState extends State<_DescriptionDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Description'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        minLines: 4,
        maxLines: 8,
        keyboardType: TextInputType.multiline,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()), child: const Text('Save')),
      ],
    );
  }
}

/// The text editor for one custom field. Owns its controller, so it is only
/// disposed once the dialog has finished closing.
class _CustomFieldDialog extends StatefulWidget {
  const _CustomFieldDialog({required this.column, required this.initial});

  final ViewColumn column;
  final String initial;

  @override
  State<_CustomFieldDialog> createState() => _CustomFieldDialogState();
}

class _CustomFieldDialogState extends State<_CustomFieldDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.column;
    return AlertDialog(
      title: Text(c.label),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: const {'number', 'decimal'}.contains(c.customType)
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(errorText: _error),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final problem = _FollowupDetailScreenState.customFieldProblem(c, _ctrl.text);
            if (problem != null) {
              setState(() => _error = problem);
              return;
            }
            Navigator.of(context).pop(_ctrl.text.trim());
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
