import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/notes_thread.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/api/user_directory.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../crm/domain/entities/audit_entry.dart';
import '../../../../data/api/status_keys.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/ticket_notes_providers.dart';
import '../../application/providers/tickets_providers.dart';
import '../../domain/entities/ticket.dart';
import '../../domain/entities/ticket_task.dart';
import '../util/ticket_sla.dart';

/// Ticket detail — summary + status/assignee, SLA banner (paused when Pending),
/// details, linked tasks, an Internal-note / Reply composer and the audit log.
class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({super.key});

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  String? _status; // local status override
  List<String>? _assignees; // local assignee override

  @override
  Widget build(BuildContext context) {
    final uri = GoRouterState.of(context).uri;
    final id = uri.queryParameters['id'] ?? '';
    final fromBoard = uri.queryParameters['from'] == 'board';
    final ticketsAsync = ref.watch(ticketsProvider);
    // The ticket's own row wins over the list's copy: it is one call, so an edit
    // shows here as soon as the write returns instead of after the whole list
    // has been walked again. Null in mock mode and on failure — then the list
    // row stands, exactly as before.
    final base =
        ref.watch(ticketDetailProvider(id)).valueOrNull ?? ref.watch(ticketByIdProvider(id));
    final headerTicket = base?.copyWith(status: _status, assignees: _assignees);

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          _header(subject: headerTicket?.subject ?? '', fromBoard: fromBoard, ticket: headerTicket),
          Expanded(
            child: AsyncStateView<List<Ticket>>(
              value: ticketsAsync,
              onRetry: () => refreshTickets(ref),
              onRefresh: () => _refresh(id),
              loading: () => const DetailSkeleton(),
              data: (_) {
                if (base == null) {
                  return const EmptyState(
                    icon: PhosphorIconsRegular.ticket,
                    title: 'Ticket not found',
                    body: 'This ticket may have been removed, or you may not have access to it.',
                  );
                }
                final t = base.copyWith(status: _status, assignees: _assignees);
                final meta = StatusMeta$.ticket[t.status] ?? StatusMeta$.ticket['new']!;
                return ListView(
                  padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 40.h),
                  children: [
                    _summaryCard(t, meta),
                    _slaBanner(t),
                    if (t.isLocked) _lockCard(),
                    SizedBox(height: 14.h),
                    _detailsCard(t),
                    SizedBox(height: 14.h),
                    _linkedTasksCard(t),
                    _notesCard(t),
                    SizedBox(height: 14.h),
                    _auditCard(t),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ──
  Widget _header({required String subject, required bool fromBoard, required Ticket? ticket}) {
    return Container(
      color: AppColors.white,
      padding: EdgeInsets.fromLTRB(16.w, 54.h, 16.w, 12.h),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.canPop() ? context.pop() : context.go(Routes.helpHome),
            child: Padding(
              padding: EdgeInsets.only(right: fromBoard ? 4.w : 12.w),
              child: Icon(PhosphorIconsBold.caretLeft, size: 22.sp, color: AppColors.textPrimary),
            ),
          ),
          if (fromBoard)
            Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: Text('Back to Support Overview',
                  style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textLabelAlt)),
            ),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'Ticket ',
                style: AppText.custom(size: 21, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3),
                children: [
                  TextSpan(
                    text: '/ $subject',
                    style: AppText.custom(size: 16, weight: FontWeight.w600, color: AppColors.textPlaceholder),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: ticket == null ? null : () => _openTicketMenu(ticket),
            child: SizedBox(
              width: 34.w,
              height: 34.w,
              child: Icon(PhosphorIconsBold.dotsThreeVertical, size: 21.sp, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary ──
  Widget _summaryCard(Ticket t, StatusMeta meta) {
    return ClozrCard(
      radius: 18,
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
                    Text(t.subject,
                        style: AppText.custom(size: 18, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3, height: 1.3)),
                    SizedBox(height: 5.h),
                    Row(
                      children: [
                        // The org's ticket number ("TKT-0025"), not the
                        // `issue_id` uuid the row is keyed by.
                        Text(t.displayRef,
                            style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textMuted)),
                        if (t.status == 'resolved') ...[
                          SizedBox(width: 8.w),
                          Flexible(
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                              decoration: BoxDecoration(color: AppColors.tintPurple, borderRadius: BorderRadius.circular(7.r)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(PhosphorIconsRegular.hourglassMedium, size: 11.sp, color: AppColors.pending),
                                  SizedBox(width: 4.w),
                                  Flexible(
                                    child: Text('Auto-closes after confirmation period',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.pending)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: 10.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () => _openStatusSheet(t),
                    child: StatusPill.meta(meta),
                  ),
                  SizedBox(height: 5.h),
                  StatusPill(label: t.pri, color: ticketPriPillColor(t.pri)),
                ],
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 14)),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => t.isLocked ? ref.read(toastProvider.notifier).show('This ticket is closed — reopen to edit') : _openAssigneeSheet(t),
            child: Row(
              children: [
                _avatarStack(t.assignees, 28),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text('Assignees',
                      style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                ),
                if (!t.isLocked)
                  Row(
                    children: [
                      Icon(PhosphorIconsRegular.pencilSimple, size: 13.sp, color: AppColors.blueBright),
                      SizedBox(width: 4.w),
                      Text('Edit', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.blueBright)),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Overlapping assignee avatars.
  ///
  /// Laid out with a [Stack] rather than a negative margin: `Container`
  /// asserts on one (`margin.isNonNegative`), so the old version threw the
  /// moment a ticket had a **second** assignee — the first sat at margin 0 and
  /// never tripped it, which is why it only showed up on reassignment.
  /// Pull-to-refresh: the ticket itself and the two panels that fetch on their
  /// own — the audit trail and the notes thread.
  Future<void> _refresh(String id) async {
    refreshTickets(ref);
    ref.invalidate(ticketDetailProvider(id));
    ref.invalidate(ticketActivityProvider(id));
    ref.invalidate(ticketLinkedTasksProvider(id));
    await settle([
      ref.read(ticketsProvider.future),
      ref.read(ticketDetailProvider(id).future),
      ref.read(ticketActivityProvider(id).future),
      ref.read(ticketLinkedTasksProvider(id).future),
      // The notes thread is a StateNotifier, not a provider that invalidation
      // reaches — without this a pull-to-refresh left the notes (and their
      // attachments) exactly as they were.
      ref.read(ticketNotesProvider(id).notifier).reload(),
    ]);
  }

  Widget _avatarStack(List<String> ids, double size) {
    final shown = ids.take(2).toList();
    final more = ids.length - shown.length;
    // Each avatar after the first sits 7px into the one before it.
    final step = size.w - 7.w;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (shown.isNotEmpty)
          SizedBox(
            width: step * (shown.length - 1) + size.w,
            height: size.w,
            child: Stack(
              children: [
                for (int i = 0; i < shown.length; i++)
                  Positioned(
                    left: step * i,
                    child: Container(
                      width: size.w,
                      height: size.w,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: MockUsers.of(shown[i]).color,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.white, width: 2),
                      ),
                      child: Text(MockUsers.of(shown[i]).initials,
                          style: AppText.custom(
                              size: size * 0.36,
                              weight: FontWeight.w700,
                              color: AppColors.white)),
                    ),
                  ),
              ],
            ),
          ),
        if (more > 0) ...[
          SizedBox(width: 5.w),
          Text('+$more', style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textMuted2)),
        ],
      ],
    );
  }

  // ── SLA banner ──
  Widget _slaBanner(Ticket t) {
    final now = kNowList.millisecondsSinceEpoch;
    final paused = t.isPaused;
    final respMs = t.respByISO != null ? DateTime.parse(t.respByISO!).millisecondsSinceEpoch - now : null;
    final resMs = t.resolveByISO != null ? DateTime.parse(t.resolveByISO!).millisecondsSinceEpoch - now : null;
    final resBreached = t.resolved == null && resMs != null && resMs < 0;

    final respLabel = t.responded != null
        ? 'met ${t.responded!.contains(', ') ? t.responded!.split(', ')[1] : t.responded}'
        : (paused ? 'paused' : (respMs != null && respMs < 0 ? 'breached' : 'due ${t.respByLabel ?? ''}'));
    final respTone = t.responded != null
        ? AppColors.success
        : (respMs != null && respMs < 0 && !paused ? AppColors.error : AppColors.textMuted2);
    final respIcon = t.responded != null
        ? PhosphorIconsFill.checkCircle
        : (paused ? PhosphorIconsFill.pause : PhosphorIconsRegular.clock);

    final resLabel = t.resolved != null
        ? 'met ${t.resolved}'
        : (paused
            ? 'frozen — waiting on customer'
            : '${t.resolveByLabel ?? '—'}${resMs != null ? (resMs < 0 ? ' — breached ${fmtLeft(resMs)} ago' : ' — ${fmtLeft(resMs)} left') : ''}');
    final resTone = t.resolved != null
        ? AppColors.success
        : (resBreached && !paused ? AppColors.error : AppColors.textMuted2);
    final resIcon = t.resolved != null
        ? PhosphorIconsFill.checkCircle
        : (paused ? PhosphorIconsFill.pause : (resBreached ? PhosphorIconsFill.warningCircle : PhosphorIconsRegular.clock));

    final bg = paused ? AppColors.bgChipGrey : (resBreached ? AppColors.tintRed : AppColors.bgScreen);

    return Container(
      margin: EdgeInsets.only(top: 14.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 13.h),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14.r)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (paused) ...[
            Row(
              children: [
                Icon(PhosphorIconsFill.pauseCircle, size: 17.sp, color: AppColors.textMuted2),
                SizedBox(width: 8.w),
                Text('SLA paused — waiting on customer',
                    style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textLabelAlt)),
              ],
            ),
            SizedBox(height: 8.h),
          ],
          _slaLine('First response', respLabel, respIcon, respTone),
          SizedBox(height: 8.h),
          _slaLine('Resolution due', resLabel, resIcon, resTone),
        ],
      ),
    );
  }

  Widget _slaLine(String title, String value, IconData icon, Color tone) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15.sp, color: tone),
        SizedBox(width: 9.w),
        Expanded(
          child: Text.rich(
            TextSpan(
              text: title,
              style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.textPrimary),
              children: [
                TextSpan(
                  text: ' · $value',
                  style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: tone),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _lockCard() {
    return Container(
      margin: EdgeInsets.only(top: 14.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(14.r)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsFill.lockSimple, size: 18.sp, color: AppColors.textMuted2),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This ticket is closed — fields are locked. Reopen to edit.',
                    style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textLabelAlt)),
                SizedBox(height: 2.h),
                Text('Status and notes stay editable.',
                    style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Details ──
  Widget _detailsCard(Ticket t) {
    final dir = ref.watch(ticketDirectoryProvider);
    final cust = dir.customer(t.custId);
    final proj = dir.project(t.projId);
    final rows = <(String, String)>[
      ('Requester', cust?.display ?? '—'),
      ('Contact person', t.contact),
      ('Channel', t.channel),
      ('Category', t.cat),
      ('Product / service', t.product ?? '—'),
      // `project_name` as the row carries it wins: resolving the uuid against
      // the projects list only works once that list has loaded, and printing a
      // raw uuid is worse than printing nothing.
      ('Related project', t.projName ?? proj?.name ?? '—'),
      ('Created', t.created),
      ('First responded', t.responded ?? 'Awaiting'),
      ('Resolved', t.resolved ?? '—'),
    ];
    final vColor = t.isLocked ? AppColors.textPlaceholder : AppColors.textPrimary;
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Details', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 4.h),
          for (final r in rows)
            Container(
              padding: EdgeInsets.symmetric(vertical: 10.h),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.bgLight))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.$1, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                  SizedBox(width: 14.w),
                  Expanded(
                    child: Text(r.$2,
                        textAlign: TextAlign.right,
                        style: AppText.custom(size: 14, weight: FontWeight.w700, color: vColor)),
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.only(top: 10.h),
            child: Text(t.desc,
                style: AppText.body(color: t.isLocked ? AppColors.textPlaceholder : AppColors.textLabelAlt).copyWith(height: 1.6)),
          ),
          if (!t.isLocked) ...[
            SizedBox(height: 14.h),
            GestureDetector(
              onTap: () => context.push('${Routes.editTicket}?id=${t.id}'),
              child: Container(
                height: 44.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: AppColors.borderCard, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsRegular.pencilSimple, size: 15.sp, color: AppColors.textSecondary),
                    SizedBox(width: 7.w),
                    Text('Edit ticket', style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Linked tasks ──
  Widget _linkedTasksCard(Ticket t) {
    // The ticket's own linked-task feed (`helpdesk.md` §10). Empty in mock mode
    // and on failure, where the card falls back to the row's `taskId` — which
    // is all the list payload carries.
    final live = ref.watch(ticketLinkedTasksProvider(t.id)).valueOrNull ?? const [];
    final tasks = live.isNotEmpty
        ? live
        : [if (t.taskId != null) TicketTask(id: t.taskId!, subject: '')];
    final dir = ref.watch(ticketDirectoryProvider);
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.linkSimple, size: 16.sp, color: AppColors.textLabelAlt),
              SizedBox(width: 7.w),
              Text('Linked tasks', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          if (tasks.isNotEmpty) ...[
            SizedBox(height: 12.h),
            for (final task in tasks)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                // A linked task *is* a projects task, so the caret opens the
                // Operations detail screen.
                onTap: task.id.isEmpty
                    ? null
                    : () => context.push('${Routes.opsTaskDetail}?id=${task.id}'),
                child: Container(
                  margin: EdgeInsets.only(bottom: 8.h),
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 11.h),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: AppColors.borderCardSoft),
                  ),
                  child: Row(
                    children: [
                      Icon(PhosphorIconsRegular.listChecks, size: 17.sp, color: AppColors.navy),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: Text(task.display,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textBody)),
                      ),
                      if (_taskChip(dir, task, t) case final chip?) ...[
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                          decoration: BoxDecoration(color: AppColors.tintNavy, borderRadius: BorderRadius.circular(7.r)),
                          child: Text(chip, style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.navy)),
                        ),
                        SizedBox(width: 8.w),
                      ],
                      Icon(PhosphorIconsBold.caretRight, size: 12.sp, color: AppColors.textPlaceholder),
                    ],
                  ),
                ),
              ),
          ],
          if (!t.isLocked)
            GestureDetector(
              onTap: () => _openCreateTaskSheet(t),
              child: Container(
                margin: EdgeInsets.only(top: 12.h),
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
                    Text('Create task from ticket', style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textBody)),
                  ],
                ),
              ),
            )
          else
            Container(
              margin: EdgeInsets.only(top: 12.h),
              height: 44.h,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(11.r)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsFill.lockSimple, size: 14.sp, color: AppColors.textPlaceholder),
                  SizedBox(width: 8.w),
                  Text('Locked — reopen the ticket to create tasks',
                      style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The project badge on a linked-task row: the task's own project when it has
  /// one, else the ticket's. Null when it would only print a uuid, which says
  /// nothing to a user.
  String? _taskChip(TicketLookups dir, TicketTask task, Ticket t) {
    final pid = task.projectId ?? t.projId;
    if (pid == null || pid.isEmpty) return null;
    final name = task.projectId == null ? t.projName : null;
    if (name != null && name.isNotEmpty) return name;
    final resolved = dir.project(pid)?.name;
    if (resolved != null && resolved.isNotEmpty) return resolved;
    return UserDirectory.isUuid(pid) ? null : pid;
  }

  /// Raises an Operations task against this ticket
  /// (`POST /issues/{id}/tasks/`). `subject` is the only field the backend
  /// requires, so the sheet asks for exactly that.
  void _openCreateTaskSheet(Ticket t) {
    final ctrl = TextEditingController();
    var saving = false;
    showClozrSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 24.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SheetHeader(title: 'Create task from ticket'),
              AppTextField(
                label: 'Task',
                required: true,
                controller: ctrl,
                hint: 'What needs doing?',
              ),
              SizedBox(height: 16.h),
              PrimaryButton(
                label: saving ? 'Creating…' : 'Create task',
                onTap: saving
                    ? null
                    : () async {
                        final subject = ctrl.text.trim();
                        if (subject.isEmpty) return;
                        setSheet(() => saving = true);
                        final ok = await _createTask(t, subject);
                        if (!ok) {
                          setSheet(() => saving = false);
                          return;
                        }
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _createTask(Ticket t, String subject) async {
    try {
      await ref
          .read(ticketsRepositoryProvider)
          .createLinkedTask(t.id, subject: subject, priority: t.pri);
      if (!mounted) return true;
      ref.read(toastProvider.notifier).show('Task created');
      ref.invalidate(ticketLinkedTasksProvider(t.id));
      await _refresh(t.id);
      return true;
    } on AppError catch (e) {
      if (!mounted) return false;
      ref.read(toastProvider.notifier).showError(e.message);
      return false;
    }
  }

  // ── Notes ──
  //
  // Migrated to the shared [NotesThread] (#13). The thread's main composer posts
  // an internal note (prepends a NoteEntry); each note's inline reply affordance
  // posts a reply (appends a NoteReply). Both stay usable on Closed tickets.
  Widget _notesCard(Ticket t) {
    final notes = ref.watch(ticketNotesProvider(t.id));
    final ctrl = ref.read(ticketNotesProvider(t.id).notifier);
    return NotesThread(
      author: ref.watch(noteAuthorProvider),
      notes: notes,
      onAddNote: (body, atts) {
        ctrl.addNote(body, atts);
        ref.read(toastProvider.notifier).show('Internal note added');
      },
      onAddReply: (noteId, body) {
        ctrl.addReply(noteId, body);
        ref.read(toastProvider.notifier).show('Reply sent');
      },
    );
  }

  // ── Audit log ──
  Widget _auditCard(Ticket t) {
    // The server's own trail in API mode — SLA breaches, status moves, edits,
    // with the real actor. The derived list below it is the prototype's and
    // names a user who did nothing, so it is mock-mode only.
    final logged = ref.watch(ticketActivityProvider(t.id)).valueOrNull ?? const [];
    final entries = ApiConfig.apiEnabled ? _fromLog(logged) : _buildAudit(t);
    if (ApiConfig.apiEnabled && entries.isEmpty) return const SizedBox.shrink();
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 6.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.clockCounterClockwise, size: 16.sp, color: AppColors.textLabelAlt),
              SizedBox(width: 7.w),
              Text('Audit log', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          SizedBox(height: 12.h),
          for (int i = 0; i < entries.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 34.w,
                        height: 34.w,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: entries[i].bg, shape: BoxShape.circle),
                        child: Icon(entries[i].icon, size: 16.sp, color: entries[i].tone),
                      ),
                      if (i < entries.length - 1)
                        Expanded(child: Container(width: 1.5.w, color: AppColors.borderCardSoft, constraints: BoxConstraints(minHeight: 12.h))),
                    ],
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 6.h, bottom: 16.h),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entries[i].title, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                          SizedBox(height: 2.h),
                          Text(entries[i].sub, style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted2)),
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

  /// The shared audit entries → this card's rows. Icon and tone come from the
  /// event kind, so a breach still reads red and a create still reads navy.
  List<_Audit> _fromLog(List<AuditEntry> entries) => [
        for (final e in entries)
          _Audit(
            _logIcon(e),
            _logTone(e).$1,
            _logTone(e).$2,
            e.title,
            [
              if (e.subtitle.isNotEmpty) e.subtitle,
              if (e.at != null) relativeTime(e.at),
            ].where((s) => s.isNotEmpty).join(' · '),
          ),
      ];

  IconData _logIcon(AuditEntry e) {
    switch (e.kind) {
      case AuditEventKind.created:
        return PhosphorIconsRegular.plusCircle;
      case AuditEventKind.statusChanged:
        return PhosphorIconsRegular.arrowsClockwise;
      case AuditEventKind.noteAdded:
        return PhosphorIconsRegular.chatCircleText;
      case AuditEventKind.childAdded:
        return PhosphorIconsRegular.paperclip;
      case AuditEventKind.deleted:
        return PhosphorIconsRegular.trash;
      case AuditEventKind.fieldChanged:
        return PhosphorIconsRegular.pencilSimple;
      case AuditEventKind.other:
        return PhosphorIconsRegular.warningCircle;
    }
  }

  (Color, Color) _logTone(AuditEntry e) {
    switch (e.kind) {
      case AuditEventKind.created:
        return (AppColors.navy, AppColors.tintNavy);
      case AuditEventKind.statusChanged:
        return (AppColors.blueBright, AppColors.tintBlue);
      case AuditEventKind.noteAdded:
        return (AppColors.success, AppColors.tintGreen);
      case AuditEventKind.deleted:
      case AuditEventKind.other:
        return (AppColors.error, AppColors.tintRed);
      case AuditEventKind.childAdded:
      case AuditEventKind.fieldChanged:
        return (AppColors.pending, AppColors.tintPurple);
    }
  }

  /// The prototype's derived trail — **mock mode only**. Every entry is
  /// inferred from the ticket's own fields, and two of them name a fixed user.
  List<_Audit> _buildAudit(Ticket t) {
    final now = kNowList.millisecondsSinceEpoch;
    final resMs = t.resolveByISO != null ? DateTime.parse(t.resolveByISO!).millisecondsSinceEpoch - now : null;
    final resBreached = t.resolved == null && resMs != null && resMs < 0;
    final firstName = t.assignees.isNotEmpty ? MockUsers.of(t.assignees.first).name : '—';
    final out = <_Audit>[];
    if (t.status == 'closed') {
      out.add(_Audit(PhosphorIconsRegular.lockSimple, AppColors.textMuted2, AppColors.bgChipGrey, 'Ticket closed', 'Manoj Varma · ${t.resolved ?? '—'}'));
    }
    if (t.status == 'resolved' || t.status == 'closed') {
      out.add(_Audit(PhosphorIconsRegular.checkCircle, AppColors.success, AppColors.tintGreen, 'Marked resolved', '$firstName · ${t.resolved ?? '—'}'));
    }
    if (resBreached) {
      out.add(_Audit(PhosphorIconsRegular.warningCircle, AppColors.error, AppColors.tintRed, 'SLA resolution breached', 'System · due ${t.resolveByLabel ?? '—'}'));
    }
    if (t.status == 'pending') {
      out.add(_Audit(PhosphorIconsRegular.pauseCircle, AppColors.warning, AppColors.tintAmber, 'Status changed — Open → Pending', '$firstName · waiting on customer'));
    }
    if (t.responded != null) {
      out.add(_Audit(PhosphorIconsRegular.check, AppColors.success, AppColors.tintGreen, 'SLA response target met', 'First reply ${t.responded}'));
    }
    out.add(_Audit(PhosphorIconsRegular.userPlus, AppColors.pending, AppColors.tintPurple, 'Assignee changed', '$firstName assigned · Manoj Varma'));
    out.add(_Audit(PhosphorIconsRegular.arrowsClockwise, AppColors.blueBright, AppColors.tintBlue, 'Status changed — New → Open', 'Manoj Varma · ${t.created}'));
    out.add(_Audit(PhosphorIconsRegular.plusCircle, AppColors.navy, AppColors.tintNavy, 'Ticket created', '${t.channel} · ${t.created}'));
    return out;
  }

  // ── 3-dot overflow menu (#7) ──
  void _openTicketMenu(Ticket t) {
    final locked = t.isLocked;
    showActionMenu(
      context,
      title: 'Ticket actions',
      actions: [
        MenuAction(
          icon: PhosphorIconsRegular.pencilSimple,
          label: 'Edit ticket',
          enabled: !locked,
          sublabel: locked ? 'Closed — reopen to edit' : null,
          onTap: () => context.push('${Routes.editTicket}?id=${t.id}'),
        ),
        MenuAction(
          icon: PhosphorIconsRegular.arrowsClockwise,
          label: 'Change status',
          onTap: () => _openStatusSheet(t),
        ),
        MenuAction(
          icon: PhosphorIconsRegular.listChecks,
          label: 'Create task from ticket',
          enabled: !locked,
          sublabel: locked ? 'Closed — reopen to create tasks' : null,
          onTap: () => _openCreateTaskSheet(t),
        ),
        if (locked)
          MenuAction(
            icon: PhosphorIconsRegular.archive,
            label: 'Archive ticket',
            destructive: true,
            onTap: () => ref.read(toastProvider.notifier).show('Archive — coming soon'),
          )
        else
          MenuAction(
            icon: PhosphorIconsRegular.xCircle,
            label: 'Close ticket',
            destructive: true,
            onTap: () => _changeStatus(t, 'closed', 'Ticket → Closed'),
          ),
      ],
    );
  }

  /// Applies a status change with optimistic UI. In mock mode the local override
  /// updates and a success toast shows immediately (unchanged). In API mode the
  /// write is awaited: success toast only on success; on an [AppError] the local
  /// override rolls back and the error message is shown (audit — no more
  /// fire-and-forget "success" that never reached the backend).
  Future<void> _changeStatus(Ticket t, String key, String successMsg,
      {String? statusId}) async {
    final prevOverride = _status;
    setState(() => _status = key);
    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show(successMsg);
      return;
    }
    try {
      final repo = ref.read(ticketsRepositoryProvider);
      // By id when the sheet knows it — folding to a built-in key first would
      // lose any status the vocabulary has no name for.
      if (statusId != null && statusId.isNotEmpty) {
        await repo.updateTicket(t.id, {'status': statusId});
      } else {
        await repo.setTicketStatusByKey(t.id, key);
      }
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(successMsg);
      // Re-read rather than trust the optimistic value. A ticket already in a
      // read-only status (Closed, Resolved) takes the PATCH with a `200` and
      // silently keeps its old status — without this the screen would go on
      // showing a change the server never made.
      refreshTickets(ref);
      ref.invalidate(ticketDetailProvider(t.id));
      await ref.read(ticketDetailProvider(t.id).future);
      if (!mounted) return;
      setState(() => _status = null);
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _status = prevOverride);
      ref.read(toastProvider.notifier).showError(e.message);
    }
  }

  // ── Status sheet ──
  /// The org's own statuses from `/crm/issue-statuses/`.
  ///
  /// This listed a hardcoded new/open/pending/resolved/closed. Two of those
  /// ("new", "pending") are not statuses this backend has, and four that it
  /// does — In Progress, On Hold, Duplicate, Overdue — could not be picked at
  /// all. The built-ins remain the fallback for mock mode.
  Future<void> _openStatusSheet(Ticket t) async {
    await ref.read(ticketStatusCatalogProvider.future);
    if (!mounted) return;
    final catalog = ref.read(ticketStatusOptionsProvider);

    await showClozrSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: 24.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title: 'Update status'),
            if (catalog.isEmpty)
              for (final key in const ['new', 'open', 'pending', 'resolved', 'closed'])
                _statusOption(ctx, t, key: key, label: StatusMeta$.ticket[key]!.label)
            else
              for (final s in catalog)
                _statusOption(ctx, t, key: ticketStatusKey(s.name), label: s.name, id: s.id),
          ],
        ),
      ),
    );
  }

  /// [id] is the org's `issue_status_id` — sent as-is when present, so a status
  /// with no built-in equivalent still writes correctly. [key] only picks the
  /// pill colour and marks the current row.
  Widget _statusOption(BuildContext ctx, Ticket t,
      {required String key, required String label, String? id}) {
    final meta = StatusMeta$.ticket[key] ?? StatusMeta$.ticket['open']!;
    // Matched on the org's own name where we have it: two statuses can fold to
    // the same built-in key, and then both rows would read as active.
    final active = id != null && t.statusName.isNotEmpty
        ? t.statusName.trim().toLowerCase() == label.trim().toLowerCase()
        : t.status == key;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(ctx).pop();
        _changeStatus(t, key, 'Status → $label', statusId: id);
      },
      child: Container(
        margin: EdgeInsets.fromLTRB(18.w, 0, 18.w, 8.h),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 13.h),
        decoration: BoxDecoration(
          color: active ? AppColors.blueSubtle : AppColors.white,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: active ? const Color(0xFFA6D1FF) : AppColors.borderCardSoft, width: active ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Container(width: 10.w, height: 10.w, decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle)),
            SizedBox(width: 11.w),
            Expanded(child: Text(label, style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary))),
            if (active) Icon(PhosphorIconsBold.check, size: 16.sp, color: AppColors.blueBright),
          ],
        ),
      ),
    );
  }

  /// Assigns the ticket, with the same optimistic-then-verify contract as
  /// [_changeStatus]: the avatar updates immediately, and in API mode a
  /// rejected write rolls it back rather than leaving the UI claiming an
  /// assignment the server never took.
  ///
  /// The backend stores **one** `assigned_to` per ticket, so [mappedId] null
  /// means unassign.
  Future<void> _changeAssignee(Ticket t, String? mappedId) async {
    final prevOverride = _assignees;
    final next = mappedId == null ? <String>[] : <String>[mappedId];
    setState(() => _assignees = next);
    final name = mappedId == null ? 'Unassigned' : MockUsers.of(mappedId).name;
    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show('Assignee → $name');
      return;
    }
    // Pickers deal in the mapped id ('me'); the server needs its own uuid.
    final userId = mappedId == null ? null : UserDirectory.realUserId(mappedId);
    if (mappedId != null && userId == null) {
      setState(() => _assignees = prevOverride);
      ref.read(toastProvider.notifier).showError('That user is not on the server');
      return;
    }
    try {
      await ref.read(ticketsRepositoryProvider).setAssignee(t.id, userId);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Assignee → $name');
      await _refresh(t.id);
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _assignees = prevOverride);
      ref.read(toastProvider.notifier).showError(e.message);
    }
  }

  // ── Assignee sheet ──
  //
  // Single-choice: an issue carries one `assigned_to` (`helpdesk.md` §8), so
  // tapping a person assigns them and tapping the current assignee clears the
  // ticket. The rows keep their checkbox — only one is ever ticked.
  void _openAssigneeSheet(Ticket t) {
    final selected = List<String>.from(t.assignees);
    final roster = ref.read(rosterProvider);
    showClozrSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: 24.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetHeader(title: 'Assignee'),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.symmetric(horizontal: 18.w),
                  children: [
                    for (final r in roster)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          // Closing first keeps one source of truth: the write
                          // is optimistic on the screen and rolls back there if
                          // the server refuses it, so a sheet left open would
                          // be the only thing still showing the failed choice.
                          final clearing = selected.contains(r.id);
                          Navigator.of(ctx).pop();
                          _changeAssignee(t, clearing ? null : r.id);
                        },
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.h),
                          child: Row(
                            children: [
                              Container(
                                width: 36.w,
                                height: 36.w,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: r.color, shape: BoxShape.circle),
                                child: Text(r.initials, style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.white)),
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r.name, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                                    SizedBox(height: 1.h),
                                    Text(r.role, style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                                  ],
                                ),
                              ),
                              _checkbox(selected.contains(r.id)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _checkbox(bool on) {
    return Container(
      width: 22.w,
      height: 22.w,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? AppColors.navy : AppColors.white,
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: on ? AppColors.navy : AppColors.borderInput, width: 1.5),
      ),
      child: on ? Icon(PhosphorIconsBold.check, size: 13.sp, color: AppColors.white) : null,
    );
  }
}

class _Audit {
  final IconData icon;
  final Color tone;
  final Color bg;
  final String title;
  final String sub;
  const _Audit(this.icon, this.tone, this.bg, this.title, this.sub);
}
