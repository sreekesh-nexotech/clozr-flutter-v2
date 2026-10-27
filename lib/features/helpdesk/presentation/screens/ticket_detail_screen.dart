import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/models/note.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/attachment_link.dart';
import '../../../../core/utils/inr_format.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/notes_thread.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/api/user_directory.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../accounting/application/providers/accounting_invalidation.dart';
import '../../../accounting/application/providers/accounting_providers.dart';
import '../../../accounting/presentation/sheets/acc_sheet_scaffold.dart';
import '../../../auth/application/providers/module_perm_providers.dart';
import '../../../auth/presentation/components/permission_guard.dart';
import '../../../crm/application/providers/crm_notes_providers.dart';
import '../../../crm/domain/entities/audit_entry.dart';
import '../../../crm/presentation/components/sla_clocks_section.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/ticket_form_providers.dart';
import '../../application/providers/tickets_providers.dart';
import '../../application/ticket_detail_rules.dart';
import '../../domain/entities/ticket.dart';
import '../../domain/entities/ticket_task.dart';
import '../util/ticket_errors.dart';
import '../util/ticket_sla.dart';

/// Ticket detail — the webapp's `TicketDetailScreen`, top to bottom: header
/// (reference, subject, "<Category> · <Customer>", "via <channel> · <ago>",
/// Priority and the Status picker), the Related strip with Edit, the
/// child-of banner, the resolved lock banner, the SLA clocks, Ticket
/// information (inline Category / Customer, SLA rows, Assignee), Additional
/// info, the Description / Child tickets / Linked tasks / Files tabs, the
/// shared notes panel, Customer reply and the Audit log.
class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({super.key});

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

enum _Tab { desc, children, tasks, files }

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  _Tab _tab = _Tab.desc;

  /// A ticket write is in flight — the header / info controls wait for it
  /// (webapp `updateIssue.isPending`).
  bool _saving = false;
  bool _uploading = false;
  bool _logging = false;
  bool _sending = false;
  bool _billing = false;
  final _reply = TextEditingController();

  /// The ticket this state last showed. A link to another ticket can reuse
  /// this screen, and the reply draft and open tab belong to the old one.
  String? _shownId;

  @override
  void initState() {
    super.initState();
    // Notes load fresh on open — the shared thread provider outlives a
    // sign-out. After the first frame: a provider cannot change mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(crmNotesProvider);
    });
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  bool get _canUpdate => ref.read(helpdeskEditableProvider);

  @override
  Widget build(BuildContext context) {
    final uri = GoRouterState.of(context).uri;
    final id = uri.queryParameters['id'] ?? '';
    final fromBoard = uri.queryParameters['from'] == 'board';
    if (_shownId != id) {
      if (_shownId != null) {
        _reply.clear();
        _tab = _Tab.desc;
      }
      _shownId = id;
    }
    // The ticket's own read wins over the list's copy; a failed read is shown
    // as such (webapp: the error notice for "this ticket"), never the cached
    // record as if it were still current.
    final detailAsync = ref.watch(ticketDetailProvider(id));
    final base = detailAsync.valueOrNull ?? ref.watch(ticketByIdProvider(id));
    final AsyncValue<Object?> pageAsync = !ApiConfig.apiEnabled
        ? ref.watch(ticketsProvider)
        : (detailAsync.hasError || base == null ? detailAsync : AsyncData<Object?>(base));
    ref.watch(helpdeskEditableProvider);

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          _topBar(subject: base?.subject ?? '', fromBoard: fromBoard, ticket: base),
          Expanded(
            child: AsyncStateView<Object?>(
              value: pageAsync,
              onRetry: () => _refresh(id),
              onRefresh: () => _refresh(id),
              error: (e, retry) => AppRefresh(
                onRefresh: () => _refresh(id),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [ErrorState.forSubject(e, 'this ticket', onRetry: retry)],
                ),
              ),
              loading: () => const DetailSkeleton(),
              data: (_) {
                if (base == null) {
                  return const EmptyState(
                    icon: PhosphorIconsRegular.ticket,
                    title: 'Ticket not found',
                    body: 'This ticket may have been removed, or you may not have access to it.',
                  );
                }
                final t = base;
                final locked = t.isLocked;
                final gap = SizedBox(height: 14.h);
                return ListView(
                  padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 40.h),
                  children: [
                    _headerCard(t),
                    if (_relatedTiles(t).isNotEmpty || !locked) ...[gap, _relatedCard(t, locked)],
                    if (t.facts?.isChild ?? false) ...[gap, _parentBanner(t, locked)],
                    if (locked) ...[gap, _lockBanner()],
                    gap,
                    LeadSlaClocks(leadId: t.id, module: 'helpdesk'),
                    _infoCard(t, locked),
                    if (t.facts?.customFields.isNotEmpty ?? false) ...[gap, _additionalInfoCard(t)],
                    gap,
                    _tabsCard(t, locked),
                    gap,
                    _notes(t, locked),
                    gap,
                    _replyCard(t, locked),
                    gap,
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

  /// Pull-to-refresh: the ticket and every panel that fetches on its own.
  Future<void> _refresh(String id) async {
    refreshTickets(ref);
    ref.invalidate(ticketDetailProvider(id));
    ref.invalidate(ticketActivityProvider(id));
    ref.invalidate(ticketLinkedTasksProvider(id));
    ref.invalidate(ticketChildrenProvider(id));
    ref.invalidate(leadSlaClocksProvider(('helpdesk', id)));
    ref.invalidate(crmNotesProvider(_notesSeed(id)));
    await settle([
      ref.read(ticketDetailProvider(id).future),
      ref.read(ticketActivityProvider(id).future),
      ref.read(ticketLinkedTasksProvider(id).future),
      ref.read(ticketChildrenProvider(id).future),
    ]);
  }

  // ── Top bar ──
  Widget _topBar({required String subject, required bool fromBoard, required Ticket? ticket}) {
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

  // ── Header ──
  Widget _headerCard(Ticket t) {
    final channel = t.facts?.channelCode;
    final statusColor = _statusColor(t);
    return ClozrCard(
      radius: 18,
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
                decoration: const BoxDecoration(color: AppColors.tintNavy, shape: BoxShape.circle),
                child: Icon(PhosphorIconsRegular.lifebuoy, size: 22.sp, color: AppColors.navy),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.reference.isNotEmpty ? t.reference : '—',
                        style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.textPlaceholder)),
                    SizedBox(height: 2.h),
                    Text(t.subject,
                        style: AppText.custom(
                            size: 18, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3, height: 1.3)),
                    SizedBox(height: 5.h),
                    Text(ticketHeaderSubline(t),
                        style: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textLabelAlt)),
                    SizedBox(height: 4.h),
                    Row(children: [
                      Icon(_channelIcon(channel), size: 13.sp, color: AppColors.textMuted),
                      SizedBox(width: 6.w),
                      Flexible(
                        child: Text(ticketViaLine(t),
                            style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textMuted)),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 14)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _eyebrow('Priority'),
                  SizedBox(height: 5.h),
                  _priorityPill(t),
                ],
              ),
              SizedBox(width: 24.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _eyebrow('Status'),
                    SizedBox(height: 5.h),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // Kept usable on a resolved ticket: it is the way to reopen it.
                      onTap: _saving
                          ? null
                          : () {
                              if (ensurePermission(ref, 'issue', PermVerb.update)) _openStatusSheet(t);
                            },
                      child: Container(
                        height: 38.h,
                        padding: EdgeInsets.symmetric(horizontal: 12.w),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(10.r),
                          border: Border.all(color: AppColors.borderInput),
                        ),
                        child: Row(children: [
                          Container(
                              width: 9.w, height: 9.w, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Text(t.statusName.isNotEmpty ? t.statusName : 'Status',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.custom(
                                    size: 14,
                                    weight: FontWeight.w700,
                                    color: _canUpdate ? AppColors.textPrimary : AppColors.textPlaceholder)),
                          ),
                          Icon(PhosphorIconsBold.caretDown, size: 13.sp, color: AppColors.textMuted),
                        ]),
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

  Color _statusColor(Ticket t) => ticketStatusColor(t.facts?.statusColor) ?? AppColors.textMuted;

  Widget _priorityPill(Ticket t) {
    final name = t.priorityName.isNotEmpty ? t.priorityName : t.pri;
    return StatusPill(label: name, color: ticketPriorityColor(name));
  }

  Widget _eyebrow(String text) => Text(text.toUpperCase(),
      style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.6));

  IconData _channelIcon(String? code) => switch (code) {
        'email' => PhosphorIconsRegular.envelopeSimple,
        'whatsapp' => PhosphorIconsRegular.whatsappLogo,
        'phone' => PhosphorIconsRegular.phone,
        'api' => PhosphorIconsRegular.plugsConnected,
        _ => PhosphorIconsRegular.question,
      };

  // ── Related strip ──
  List<({IconData icon, String label, String kind, String route})> _relatedTiles(Ticket t) => [
        if (t.custId.isNotEmpty)
          (
            icon: PhosphorIconsRegular.buildings,
            label: t.facts?.customerName ?? 'Customer',
            kind: 'Customer',
            route: '${Routes.customerDetail}?id=${t.custId}',
          ),
        if ((t.projId ?? '').isNotEmpty)
          (
            icon: PhosphorIconsRegular.kanban,
            label: t.projName ?? 'Project',
            kind: 'Project',
            route: '${Routes.projectDetail}?id=${t.projId}',
          ),
        if ((t.productId ?? '').isNotEmpty)
          (
            icon: PhosphorIconsRegular.package,
            label: t.product ?? 'Product',
            kind: 'Product / Service',
            route: '${Routes.productDetail}?id=${t.productId}',
          ),
      ];

  Widget _relatedCard(Ticket t, bool locked) {
    final tiles = _relatedTiles(t);
    final canEdit = _canUpdate;
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tiles.isNotEmpty) ...[
            _eyebrow('Related'),
            SizedBox(height: 10.h),
            for (final r in tiles)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.push(r.route),
                child: Container(
                  margin: EdgeInsets.only(bottom: 8.h),
                  padding: EdgeInsets.fromLTRB(7.w, 7.h, 12.w, 7.h),
                  decoration: BoxDecoration(
                    color: AppColors.bgScreen,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: AppColors.borderCardSoft),
                  ),
                  child: Row(children: [
                    Container(
                      width: 34.w,
                      height: 34.w,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(8.r),
                        border: Border.all(color: AppColors.borderCardSoft),
                      ),
                      child: Icon(r.icon, size: 17.sp, color: AppColors.navy),
                    ),
                    SizedBox(width: 11.w),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                        Text(r.kind, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                      ]),
                    ),
                    Icon(PhosphorIconsRegular.arrowUpRight, size: 16.sp, color: AppColors.textMuted),
                  ]),
                ),
              ),
          ],
          if (!locked)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (ensurePermission(ref, 'issue', PermVerb.update)) context.push('${Routes.editTicket}?id=${t.id}');
              },
              child: Container(
                margin: EdgeInsets.only(top: tiles.isEmpty ? 0 : 4.h),
                height: 42.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(11.r),
                  border: Border.all(color: AppColors.borderInput),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(PhosphorIconsRegular.pencilSimple,
                      size: 15.sp, color: canEdit ? AppColors.textSecondary : AppColors.textPlaceholder),
                  SizedBox(width: 7.w),
                  Text('Edit',
                      style: AppText.custom(
                          size: 13.5, weight: FontWeight.w700, color: canEdit ? AppColors.textSecondary : AppColors.textPlaceholder)),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  // ── Child-of banner ──
  Widget _parentBanner(Ticket t, bool locked) {
    final f = t.facts!;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(14.r)),
      child: Row(children: [
        Icon(PhosphorIconsRegular.gitBranch, size: 15.sp, color: AppColors.textMuted),
        SizedBox(width: 9.w),
        Expanded(
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Child of ', style: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textBody)),
            GestureDetector(
              onTap: f.parentIssueId == null ? null : () => context.push('${Routes.ticketDetail}?id=${f.parentIssueId}'),
              child: Text(f.parentReference.isNotEmpty ? f.parentReference : 'parent ticket',
                  style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.navy)),
            ),
            if (f.parentSubject.isNotEmpty)
              Text(' · ${f.parentSubject}',
                  style: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textMuted)),
          ]),
        ),
        if (!locked && _canUpdate) ...[
          SizedBox(width: 8.w),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _saving ? null : () => _detach(t.id, t.displayRef, ownId: t.id),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: AppColors.borderInput),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(PhosphorIconsRegular.linkBreak, size: 14.sp, color: AppColors.textBody),
                SizedBox(width: 5.w),
                Text('Detach', style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textBody)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _lockBanner() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(14.r)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(PhosphorIconsFill.lockSimple, size: 15.sp, color: AppColors.textMuted),
        SizedBox(width: 9.w),
        Expanded(
          child: Text(
              'This ticket is resolved. The UI treats it as locked for editing — the backend does not yet enforce this itself.',
              style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textBody, height: 1.4)),
        ),
      ]),
    );
  }

  // ── Ticket information ──
  Widget _infoCard(Ticket t, bool locked) {
    final f = t.facts;
    final editable = !locked && _canUpdate;
    final customerName = f?.customerName;
    final contactName = f?.contactName;
    final resp = firstResponseSeg(t);
    final billing = billingRowValue(t, (v) => formatInr(v));
    final assigneeName = f?.assignedToName ?? (t.assignees.isEmpty ? null : MockUsers.of(t.assignees.first).name);
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 12.h),
            child: Text('Ticket information',
                style: AppText.custom(size: 15.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
          const Divider(height: 1, color: AppColors.bgLight),
          Padding(
            padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 4.h),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _eyebrow('Requester'),
              SizedBox(height: 9.h),
              Row(children: [
                Container(
                  width: 38.w,
                  height: 38.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.tintNavy, borderRadius: BorderRadius.circular(10.r)),
                  child: Text(_initials(customerName ?? '?'),
                      style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.navy)),
                ),
                SizedBox(width: 11.w),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(customerName ?? 'No customer linked',
                        style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    Text(
                        (contactName ?? '').isNotEmpty
                            ? contactName!
                            : (customerName != null ? '—' : 'Link one in Customer below'),
                        style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ]),
                ),
              ]),
            ]),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 4.h),
            child: Column(children: [
              _infoRow('Channel',
                  value: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_channelIcon(f?.channelCode), size: 14.sp, color: AppColors.textMuted),
                    SizedBox(width: 6.w),
                    Text(ticketChannelLabel(f?.channelCode), style: _rowValueStyle()),
                  ])),
              _infoRow('Category',
                  text: f != null ? (f.typeName ?? '—') : t.cat,
                  onEdit: editable && ref.watch(ticketTypeOptionsProvider).isNotEmpty ? () => _pickCategory(t) : null),
              _infoRow('Customer', text: customerName ?? '—', onEdit: editable ? () => _pickCustomer(t) : null),
              _infoRow('Status', value: StatusPill(label: t.statusName.isNotEmpty ? t.statusName : '—', color: _statusColor(t))),
              _infoRow('Priority', value: _priorityPill(t)),
              _infoRow('Created', text: ticketDateTime(t.createdISO)),
              if (resp != null) _infoRow('First response', value: _segValue(resp)),
              _infoRow('Resolution', value: _segValue(resolutionSeg(t))),
              _infoRow('SLA', text: formatSlaTarget(f?.slaValue, f?.slaUnit)),
              if (billing != null) _infoRow('Billing', text: billing),
              _infoRow('Ticket ID', text: t.displayRef, last: true),
            ]),
          ),
          const Divider(height: 1, color: AppColors.bgLight),
          Padding(
            padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 16.h),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _eyebrow('Assignee'),
              SizedBox(height: 9.h),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _saving
                    ? null
                    : () {
                        if (locked) return;
                        if (ensurePermission(ref, 'issue', PermVerb.update)) _pickAssignee(t);
                      },
                child: Container(
                  height: 44.h,
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  decoration: BoxDecoration(
                    color: editable ? AppColors.white : AppColors.bgScreen,
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: AppColors.borderInput),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Text(assigneeName ?? 'Unassigned',
                          style: AppText.custom(
                              size: 14,
                              weight: FontWeight.w600,
                              color: assigneeName == null || !editable ? AppColors.textPlaceholder : AppColors.textPrimary)),
                    ),
                    Icon(PhosphorIconsBold.caretDown, size: 13.sp, color: AppColors.textMuted),
                  ]),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  TextStyle _rowValueStyle([Color? color]) =>
      AppText.custom(size: 13.5, weight: FontWeight.w600, color: color ?? AppColors.textPrimary);

  Widget _infoRow(String label, {String? text, Widget? value, VoidCallback? onEdit, bool last = false}) {
    final content = value ?? Text(text ?? '—', textAlign: TextAlign.right, style: _rowValueStyle());
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onEdit,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10.h),
        decoration: last ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.bgLight))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text(label, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
          SizedBox(width: 14.w),
          Expanded(child: Align(alignment: Alignment.centerRight, child: content)),
          if (onEdit != null) ...[
            SizedBox(width: 6.w),
            Icon(PhosphorIconsRegular.pencilSimple, size: 13.sp, color: AppColors.blueBright),
          ],
        ]),
      ),
    );
  }

  Widget _segValue(SlaSeg seg) {
    final color = switch (seg.tone) {
      SlaTone.met => AppColors.success,
      SlaTone.muted => AppColors.textMuted,
      SlaTone.atRisk => AppColors.warningDeep,
      SlaTone.breached => AppColors.error,
      SlaTone.normal => AppColors.textPrimary,
    };
    final icon = switch (seg.icon) {
      SlaIcon.check => PhosphorIconsRegular.checkCircle,
      SlaIcon.pause => PhosphorIconsRegular.pause,
      SlaIcon.clock => PhosphorIconsRegular.clock,
      SlaIcon.alert => PhosphorIconsRegular.warning,
      SlaIcon.off => PhosphorIconsRegular.timer,
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13.sp, color: color),
      SizedBox(width: 5.w),
      Flexible(child: Text(seg.label, textAlign: TextAlign.right, style: _rowValueStyle(color))),
    ]);
  }

  /// A server `user_id` → the person's name, empty when not known.
  String _userName(String? userId) {
    if (userId == null || userId.isEmpty) return '';
    final mapped = UserDirectory.mapUserId(userId);
    final name = mapped.isEmpty ? '' : MockUsers.of(mapped).name;
    return name == mapped || name == 'Unknown' ? '' : name;
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  Widget _additionalInfoCard(Ticket t) {
    final entries = t.facts!.customFields.entries.toList();
    return ClozrCard(
      radius: 18,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Additional info', style: AppText.custom(size: 15.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
        SizedBox(height: 4.h),
        for (int i = 0; i < entries.length; i++)
          _infoRow(customFieldLabel(entries[i].key),
              text: entries[i].value.isEmpty ? '—' : entries[i].value, last: i == entries.length - 1),
      ]),
    );
  }

  // ── Tabs ──
  Widget _tabsCard(Ticket t, bool locked) {
    final isChild = t.facts?.isChild ?? false;
    final children = ref.watch(ticketChildrenProvider(t.id));
    final childCount = children.valueOrNull?.length ?? t.facts?.childCount ?? 0;
    final linked = ref.watch(ticketLinkedTasksProvider(t.id));
    final files = t.facts?.attachments ?? const <TicketAttachment>[];
    // A child can never itself be a parent (two-level cap), so the tab is only
    // offered on roots.
    final tab = isChild && _tab == _Tab.children ? _Tab.desc : _tab;
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          margin: EdgeInsets.all(12.w),
          padding: EdgeInsets.all(4.w),
          decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(11.r)),
          // Wraps rather than scrolls, so every tab stays in view on a phone.
          child: Wrap(spacing: 2.w, runSpacing: 2.h, children: [
            _tabBtn(_Tab.desc, tab, PhosphorIconsRegular.textAlignLeft, 'Description'),
            if (!isChild) _tabBtn(_Tab.children, tab, PhosphorIconsRegular.gitBranch, 'Child tickets', childCount),
            _tabBtn(_Tab.tasks, tab, PhosphorIconsRegular.listChecks, 'Linked tasks', linked.valueOrNull?.length ?? 0),
            _tabBtn(_Tab.files, tab, PhosphorIconsRegular.paperclip, 'Files', files.length),
          ]),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 16.h),
          child: switch (tab) {
            _Tab.desc => _descTab(t),
            _Tab.children => _childrenTab(t, locked, children, childCount),
            _Tab.tasks => _tasksTab(t, locked, linked),
            _Tab.files => _filesTab(t, locked, files),
          },
        ),
      ]),
    );
  }

  Widget _tabBtn(_Tab value, _Tab current, IconData icon, String label, [int count = 0]) {
    final active = value == current;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _tab = value),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 11.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: active ? AppColors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14.sp, color: active ? AppColors.textPrimary : AppColors.textMuted),
          SizedBox(width: 6.w),
          Text(label,
              style: AppText.custom(
                  size: 12.5, weight: FontWeight.w600, color: active ? AppColors.textPrimary : AppColors.textMuted)),
          if (count > 0) ...[
            SizedBox(width: 6.w),
            Container(
              constraints: BoxConstraints(minWidth: 18.w),
              height: 18.w,
              padding: EdgeInsets.symmetric(horizontal: 5.w),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(99)),
              child: Text('$count', style: AppText.custom(size: 10, weight: FontWeight.w700, color: AppColors.white)),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _descTab(Ticket t) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _eyebrow('Description'),
      SizedBox(height: 8.h),
      Text(
        t.desc.isNotEmpty ? t.desc : 'No description was captured for this ticket — use Edit to add context.',
        style: AppText.body(color: t.desc.isNotEmpty ? AppColors.textLabelAlt : AppColors.textPlaceholder)
            .copyWith(height: 1.6),
      ),
    ]);
  }

  Widget _tabHead(String title, {String? action, IconData? icon, VoidCallback? onAction, bool enabled = true}) {
    return Row(children: [
      Expanded(child: Text(title, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary))),
      if (action != null)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onAction,
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: Container(
              height: 34.h,
              padding: EdgeInsets.symmetric(horizontal: 12.w),
              decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(9.r)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon ?? PhosphorIconsBold.plus, size: 14.sp, color: AppColors.white),
                SizedBox(width: 6.w),
                Text(action, style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.white)),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _emptyTab(IconData icon, String title, [String? body]) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 22.h),
      child: Center(
        child: Column(children: [
          Icon(icon, size: 28.sp, color: AppColors.textPlaceholder),
          SizedBox(height: 8.h),
          Text(title, style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
          if (body != null) ...[
            SizedBox(height: 4.h),
            Text(body,
                textAlign: TextAlign.center,
                style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
          ],
        ]),
      ),
    );
  }

  Widget _rowIcon(IconData icon) => Container(
        width: 36.w,
        height: 36.w,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(8.r)),
        child: Icon(icon, size: 17.sp, color: AppColors.navy),
      );

  Widget _childrenTab(Ticket t, bool locked, AsyncValue<List<Ticket>> async, int childCount) {
    final kids = async.valueOrNull ?? const <Ticket>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _tabHead('Child tickets',
          action: locked ? null : 'Attach ticket',
          enabled: _canUpdate,
          onAction: () {
            if (ensurePermission(ref, 'issue', PermVerb.update)) _openAttachSheet(t);
          }),
      if (childCount > 0) ...[
        SizedBox(height: 10.h),
        Text("This ticket can't be resolved or deleted while a child is still attached.",
            style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
      ],
      if (async.isLoading && kids.isEmpty)
        Padding(padding: EdgeInsets.symmetric(vertical: 16.h), child: const Center(child: CircularProgressIndicator()))
      else if (kids.isEmpty)
        _emptyTab(PhosphorIconsRegular.gitBranch, 'No child tickets',
            'Attach an existing ticket to group related reports under this one.')
      else
        for (int i = 0; i < kids.length; i++)
          Container(
            padding: EdgeInsets.symmetric(vertical: 12.h),
            decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.bgLight))),
            child: Row(children: [
              _rowIcon(PhosphorIconsRegular.gitBranch),
              SizedBox(width: 11.w),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.push('${Routes.ticketDetail}?id=${kids[i].id}'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(kids[i].subject.isNotEmpty ? kids[i].subject : 'Untitled ticket',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textBody)),
                    Text('${kids[i].displayRef} · ${kids[i].statusName}',
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ]),
                ),
              ),
              if (!locked && _canUpdate)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _saving ? null : () => _detach(kids[i].id, kids[i].displayRef, ownId: t.id),
                  child: Container(
                    width: 34.w,
                    height: 34.w,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9.r),
                      border: Border.all(color: AppColors.borderInput),
                    ),
                    child: Icon(PhosphorIconsRegular.linkBreak, size: 15.sp, color: AppColors.textSecondary),
                  ),
                ),
            ]),
          ),
    ]);
  }

  Widget _tasksTab(Ticket t, bool locked, AsyncValue<List<TicketTask>> async) {
    final tasks = async.valueOrNull ?? const <TicketTask>[];
    final canTask = hasPermission(ref, 'project_task', PermVerb.create);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _tabHead('Linked Operations tasks',
          action: locked ? null : 'Create task from ticket',
          enabled: canTask,
          onAction: () {
            if (ensurePermission(ref, 'project_task', PermVerb.create)) _createTask(t);
          }),
      if (async.isLoading && tasks.isEmpty)
        Padding(padding: EdgeInsets.symmetric(vertical: 16.h), child: const Center(child: CircularProgressIndicator()))
      else if (tasks.isEmpty)
        _emptyTab(PhosphorIconsRegular.listChecks, 'No linked tasks yet')
      else
        for (int i = 0; i < tasks.length; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: tasks[i].id.isEmpty ? null : () => context.push('${Routes.opsTaskDetail}?id=${tasks[i].id}'),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 12.h),
              decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.bgLight))),
              child: Row(children: [
                _rowIcon(PhosphorIconsRegular.listChecks),
                SizedBox(width: 11.w),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tasks[i].subject.isNotEmpty ? tasks[i].subject : 'Untitled task',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textBody)),
                    Text(
                        '${tasks[i].projectName.isNotEmpty ? tasks[i].projectName : 'No project'}'
                        '${tasks[i].priority.isNotEmpty ? ' · ${tasks[i].priority}' : ''}',
                        style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ]),
                ),
                if (tasks[i].isOverdue) ...[
                  Text('Overdue', style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.error)),
                  SizedBox(width: 8.w),
                ],
                Text(tasks[i].status.isNotEmpty ? tasks[i].status : '—',
                    style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                SizedBox(width: 4.w),
                Icon(PhosphorIconsBold.caretRight, size: 12.sp, color: AppColors.textPlaceholder),
              ]),
            ),
          ),
    ]);
  }

  Widget _filesTab(Ticket t, bool locked, List<TicketAttachment> files) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _tabHead('Attachments',
          action: locked ? null : (_uploading ? 'Uploading…' : 'Upload file'),
          icon: PhosphorIconsRegular.uploadSimple,
          enabled: _canUpdate,
          onAction: _uploading
              ? null
              : () {
                  if (ensurePermission(ref, 'issue', PermVerb.update)) _upload(t);
                }),
      if (files.isEmpty)
        _emptyTab(PhosphorIconsRegular.paperclip, 'No files yet')
      else
        for (int i = 0; i < files.length; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              final failure = await openAttachment(files[i].url);
              if (failure != null && mounted) ref.read(toastProvider.notifier).showError(failure);
            },
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 12.h),
              decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.bgLight))),
              child: Row(children: [
                _rowIcon(PhosphorIconsRegular.fileText),
                SizedBox(width: 11.w),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(files[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textBody)),
                    Text(attachmentAddedLine(files[i], uploader: _userName(files[i].uploadedById)),
                        style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ]),
                ),
                Icon(PhosphorIconsRegular.downloadSimple, size: 16.sp, color: AppColors.textMuted),
              ]),
            ),
          ),
    ]);
  }

  // ── Notes ──
  CrmNotesSeed _notesSeed(String id) => CrmNotesSeed(id, () => const <NoteEntry>[], apiModel: 'issue');

  /// The shared notes panel (`related_to=issue`): Tag · Insert, reply,
  /// author-only pin / edit / delete. Read-only once the ticket is resolved.
  /// No @mention list — the webapp has no mention source for tickets.
  Widget _notes(Ticket t, bool locked) {
    final seed = _notesSeed(t.id);
    final notes = ref.read(crmNotesProvider(seed).notifier);
    return NotesThread(
      author: ref.watch(noteAuthorProvider),
      notes: ref.watch(crmNotesProvider(seed)),
      readOnly: locked,
      onAddNote: (body, atts) => notes.addNote(body, atts, ref.read(noteAuthorProvider)),
      onAddReply: (noteId, body) => notes.addReply(noteId, body, ref.read(noteAuthorProvider)),
      webappToolbar: true,
      noteTypes: ref.watch(noteTypesProvider).valueOrNull ?? const [],
      currentUserId: UserDirectory.currentUserId,
      onAddTypedNote: (body, atts, typeId, typeName, mentions) => notes.addNote(body, atts, ref.read(noteAuthorProvider),
          noteTypeId: typeId, noteTypeName: typeName, mentionedUserIds: mentions, authorId: UserDirectory.currentUserId),
      onTogglePin: (id) => notes.togglePin(id),
      onEditNote: (id, body) => notes.editNote(id, body),
      onDeleteNote: (id) => notes.deleteNote(id),
    );
  }

  // ── Customer reply ──
  Widget _replyCard(Ticket t, bool locked) {
    final code = t.facts?.channelCode;
    final canReply = isReplyDispatchable(code);
    final canUpdate = _canUpdate;
    final replies = t.facts?.replies ?? const <TicketReply>[];
    final who = (t.facts?.contactName ?? '').isNotEmpty
        ? t.facts!.contactName!
        : (t.facts?.customerName ?? 'the customer');
    final enabled = canReply && canUpdate;
    final hasText = _reply.text.trim().isNotEmpty;
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 12.h),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Customer reply', style: AppText.custom(size: 15.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
            SizedBox(height: 4.h),
            Row(children: [
              Icon(_channelIcon(code), size: 13.sp, color: AppColors.textMuted),
              SizedBox(width: 5.w),
              Expanded(
                child: Text(canReply ? 'Sends via ${ticketChannelLabel(code)}' : 'This channel cannot receive a reply',
                    style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              ),
            ]),
          ]),
        ),
        const Divider(height: 1, color: AppColors.bgLight),
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 14.h),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: AppColors.borderInput),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              Container(
                color: AppColors.bgScreen,
                child: TextField(
                  controller: _reply,
                  enabled: enabled,
                  minLines: 2,
                  maxLines: 6,
                  onChanged: (_) => setState(() {}),
                  style: AppText.custom(size: 14, weight: FontWeight.w500, color: AppColors.textBody),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                    hintText: canReply
                        ? 'Reply to $who via $code…'
                        : 'This ticket was raised by phone — add an internal note above instead.',
                    hintStyle: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textPlaceholder),
                  ),
                ),
              ),
              Container(
                color: AppColors.white,
                padding: EdgeInsets.all(8.w),
                child: Row(
                  children: [
                    if (canLogFirstResponse(t))
                      _outlineBtn(
                        icon: PhosphorIconsRegular.phoneOutgoing,
                        label: _logging ? 'Logging…' : 'Log first response',
                        enabled: canUpdate,
                        onTap: _logging
                            ? null
                            : () {
                                if (ensurePermission(ref, 'issue', PermVerb.update)) _logFirstResponse(t);
                              },
                      ),
                    if ((t.respondedISO ?? '').isNotEmpty)
                      Flexible(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(PhosphorIconsRegular.checkCircle, size: 13.sp, color: AppColors.success),
                          SizedBox(width: 5.w),
                          Flexible(
                            child: Text(firstResponseAgo(t),
                                style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                          ),
                        ]),
                      ),
                    const Spacer(),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _sending || !canReply || !hasText
                          ? null
                          : () {
                              if (ensurePermission(ref, 'issue', PermVerb.update)) _sendReply(t);
                            },
                      child: Opacity(
                        opacity: _sending || !canReply || !hasText || !canUpdate ? 0.5 : 1,
                        child: Container(
                          height: 34.h,
                          padding: EdgeInsets.symmetric(horizontal: 14.w),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(9.r)),
                          child: Text(_sending ? 'Sending…' : 'Send reply',
                              style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.white)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
        if (replies.isNotEmpty) ...[
          const Divider(height: 1, color: AppColors.bgLight),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 12.h),
            child: Column(children: [
              for (int i = 0; i < replies.length; i++)
                Container(
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.bgLight))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 28.w,
                      height: 28.w,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
                      child: Text(_initials(replies[i].author.isEmpty ? '?' : replies[i].author),
                          style: AppText.custom(size: 10, weight: FontWeight.w700, color: AppColors.white)),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                        decoration: BoxDecoration(color: AppColors.bgScreen, borderRadius: BorderRadius.circular(10.r)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Wrap(spacing: 6.w, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            Text(replies[i].author.isEmpty ? 'You' : replies[i].author,
                                style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textBody)),
                            Icon(PhosphorIconsRegular.arrowBendUpLeft, size: 12.sp, color: AppColors.navy),
                            Text('REPLY TO CUSTOMER',
                                style: AppText.custom(size: 10, weight: FontWeight.w700, color: AppColors.navy, letterSpacing: 0.4)),
                            Text(relativeTime(replies[i].at),
                                style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                          ]),
                          SizedBox(height: 4.h),
                          Text(replies[i].body,
                              style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textLabelAlt, height: 1.5)),
                        ]),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _outlineBtn({required IconData icon, required String label, required bool enabled, VoidCallback? onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Container(
          height: 34.h,
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(9.r),
            border: Border.all(color: AppColors.borderInput),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14.sp, color: AppColors.textBody),
            SizedBox(width: 6.w),
            Text(label, style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textBody)),
          ]),
        ),
      ),
    );
  }

  // ── Audit log ──
  Widget _auditCard(Ticket t) {
    final async = ref.watch(ticketActivityProvider(t.id));
    final entries = async.valueOrNull ?? const <AuditEntry>[];
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 6.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(PhosphorIconsRegular.clockCounterClockwise, size: 16.sp, color: AppColors.navy),
            SizedBox(width: 7.w),
            Text('Audit log', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          ]),
          SizedBox(height: 12.h),
          if (entries.isEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: Text(async.isLoading ? 'Loading…' : 'No events yet.',
                  style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
            ),
          for (int i = 0; i < entries.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(children: [
                    Container(
                      width: 32.w,
                      height: 32.w,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: AppColors.bgChipGrey, shape: BoxShape.circle),
                      child: Icon(PhosphorIconsRegular.pulse, size: 15.sp, color: AppColors.textSecondary),
                    ),
                    if (i < entries.length - 1)
                      Expanded(
                          child: Container(
                              width: 1.5.w, color: AppColors.borderCardSoft, constraints: BoxConstraints(minHeight: 12.h))),
                  ]),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 5.h, bottom: 16.h),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(entries[i].title,
                            style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textPrimary)),
                        SizedBox(height: 2.h),
                        Text(
                          [
                            if (entries[i].subtitle.isNotEmpty) entries[i].subtitle,
                            if (entries[i].at != null) absoluteDateTime(entries[i].at),
                          ].join(' · '),
                          style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── ⋮ menu ──
  void _openTicketMenu(Ticket t) {
    final locked = t.isLocked;
    final canEdit = _canUpdate;
    final canTask = hasPermission(ref, 'project_task', PermVerb.create);
    showActionMenu(
      context,
      title: 'Ticket actions',
      actions: [
        if (!locked)
          MenuAction(
            icon: PhosphorIconsRegular.pencilSimple,
            label: 'Edit ticket',
            enabled: canEdit,
            sublabel: canEdit ? null : PermissionCopy.update,
            onTap: () => context.push('${Routes.editTicket}?id=${t.id}'),
          ),
        if (!locked)
          MenuAction(
            icon: PhosphorIconsRegular.listChecks,
            label: 'Create task from ticket',
            enabled: canTask,
            sublabel: canTask ? null : PermissionCopy.create,
            onTap: () => _createTask(t),
          ),
        // "Bill this ticket" — offered only for a billable, unbilled ticket
        // while accounting is active (the server does not check either).
        if (ref.read(accountingActiveProvider) && ref.read(accPermProvider('acc_document')).create && t.billable && !t.isBilled)
          MenuAction(
            icon: PhosphorIconsRegular.receipt,
            label: 'Bill this ticket',
            sublabel: 'Create a draft invoice for this work',
            onTap: () => _billTicket(t),
          ),
      ],
    );
  }

  // ── Writes ──

  /// One ticket PATCH with the webapp's toast; refreshes on success and
  /// reports a refusal in plain words.
  Future<void> _patch(Ticket t, Map<String, dynamic> fields, String successMsg) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(ticketsRepositoryProvider).updateTicket(t.id, fields);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(successMsg);
      await _refresh(t.id);
    } on AppError catch (e) {
      if (mounted) showTicketError(ref, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openStatusSheet(Ticket t) async {
    await ref.read(ticketStatusCatalogProvider.future);
    if (!mounted) return;
    final catalog = ref.read(ticketStatusOptionsProvider);
    final picked = await showClozrSheet<String>(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: 24.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title: 'Update status'),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final s in catalog)
                  _optionRow(ctx, value: s.id, label: s.name, dot: s.color ?? AppColors.textMuted, active: s.id == t.statusId),
              ]),
            ),
          ],
        ),
      ),
    );
    // Picking the current status sends nothing.
    if (picked == null || picked == t.statusId || !mounted) return;
    await _patch(t, {'status_id': picked}, 'Status updated');
  }

  Widget _optionRow(BuildContext ctx, {required String value, required String label, Color? dot, required bool active}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(ctx).pop(value),
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
            if (dot != null) ...[
              Container(width: 10.w, height: 10.w, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              SizedBox(width: 11.w),
            ],
            Expanded(child: Text(label, style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary))),
            if (active) Icon(PhosphorIconsBold.check, size: 16.sp, color: AppColors.blueBright),
          ],
        ),
      ),
    );
  }

  /// Inline Category (triage): "Uncategorised" clears it.
  Future<void> _pickCategory(Ticket t) async {
    final types = ref.read(ticketTypeOptionsProvider);
    final current = t.typeId;
    final picked = await showClozrSheet<String>(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: 24.h),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SheetHeader(title: 'Category'),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              _optionRow(ctx, value: '', label: 'Uncategorised', active: current.isEmpty),
              for (final ty in types) _optionRow(ctx, value: ty.id, label: ty.name, active: ty.id == current),
            ]),
          ),
        ]),
      ),
    );
    if (picked == null || picked == current || !mounted) return;
    await _patch(t, {'issue_type': picked.isEmpty ? null : picked},
        picked.isEmpty ? 'Category cleared' : 'Category updated');
  }

  /// Inline Customer (triage): a server-side search, "No customer" unlinks.
  Future<void> _pickCustomer(Ticket t) async {
    final current = t.custId;
    final picked = await showClozrSheet<String>(
      context: context,
      builder: (ctx) => _CustomerPickerSheet(current: current, onPick: (v) => Navigator.of(ctx).pop(v)),
    );
    if (picked == null || picked == current || !mounted) return;
    await _patch(t, {'customer_id': picked.isEmpty ? null : picked},
        picked.isEmpty ? 'Customer unlinked' : 'Customer linked');
  }

  /// The single Assignee select: "Unassigned" sends null; the options are
  /// the users who can be assigned Helpdesk tickets (current one kept).
  Future<void> _pickAssignee(Ticket t) async {
    final eligible = await ref.read(ticketAssignableUsersProvider.future).catchError((_) => <({String id, String name})>[]);
    if (!mounted) return;
    final currentId = t.facts?.assignedToId ?? UserDirectory.realUserId(t.assignees.firstOrNull ?? '');
    final options = assigneeChoices(
      [for (final u in eligible) (id: UserDirectory.realUserId(u.id) ?? u.id, name: u.name)],
      currentId: currentId,
      currentName: t.facts?.assignedToName,
    );
    final picked = await showClozrSheet<String>(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: 24.h),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SheetHeader(title: 'Assignee'),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              _optionRow(ctx, value: '', label: 'Unassigned', active: (currentId ?? '').isEmpty),
              for (final u in options) _optionRow(ctx, value: u.id, label: u.name, active: u.id == currentId),
            ]),
          ),
        ]),
      ),
    );
    if (picked == null || picked == (currentId ?? '') || !mounted) return;
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(ticketsRepositoryProvider).setAssignee(t.id, picked.isEmpty ? null : picked);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Assignee updated');
      await _refresh(t.id);
    } on AppError catch (e) {
      if (mounted) showTicketError(ref, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Detaches [childId] from its parent — the only way to unblock a parent's
  /// delete. [ownId] is the ticket on screen, refreshed afterwards.
  Future<void> _detach(String childId, String reference, {required String ownId}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(ticketsRepositoryProvider).setParent(childId, null);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('$reference detached');
      await _refresh(ownId);
    } on AppError catch (e) {
      if (mounted) showTicketError(ref, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openAttachSheet(Ticket t) async {
    final attached = await showClozrSheet<bool>(
      context: context,
      builder: (ctx) => _AttachChildSheet(parent: t),
    );
    if (attached == true && mounted) {
      ref.read(toastProvider.notifier).show('Child ticket attached');
      await _refresh(t.id);
    }
  }

  /// Opens the Operations New Task form linked to this ticket, Subject
  /// prefilled from the ticket (webapp `AddProjectTaskModal`).
  Future<void> _createTask(Ticket t) async {
    final q = Uri(queryParameters: {'ticket': t.id, 'ticketRef': t.displayRef, 'subject': t.subject}).query;
    await context.push('${Routes.createTask}?$q');
    if (!mounted) return;
    ref.invalidate(ticketLinkedTasksProvider(t.id));
    ref.invalidate(ticketDetailProvider(t.id));
  }

  Future<void> _upload(Ticket t) async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(withData: false);
    } on Object catch (e) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).showError('Could not open the file picker: $e');
      return;
    }
    final file = picked?.files.singleOrNull;
    final path = file?.path;
    if (file == null || path == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await ref.read(ticketsRepositoryProvider).uploadAttachment(t.id, path: path, name: file.name);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('File uploaded');
      await _refresh(t.id);
    } on AppError catch (e) {
      if (mounted) showTicketError(ref, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _logFirstResponse(Ticket t) async {
    setState(() => _logging = true);
    try {
      await ref.read(ticketsRepositoryProvider).logFirstResponse(t.id);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('First response logged');
      await _refresh(t.id);
    } on AppError catch (e) {
      if (mounted) showTicketError(ref, e);
    } finally {
      if (mounted) setState(() => _logging = false);
    }
  }

  /// Sends the reply through the ticket's channel. A dispatch failure (window
  /// closed, no sender, no recipient) shows the server's message and keeps
  /// the draft.
  Future<void> _sendReply(Ticket t) async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(ticketsRepositoryProvider).sendReply(t.id, text);
      if (!mounted) return;
      _reply.clear();
      ref.read(toastProvider.notifier).show('Reply sent');
      await _refresh(t.id);
    } on AppError catch (e) {
      if (mounted) {
        ref.read(apiServiceProvider).handled(e);
        ref.read(toastProvider.notifier).showError(e.bareMessage);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Creates the one-line draft invoice for a billable ticket and opens it.
  Future<void> _billTicket(Ticket t) async {
    if (_billing) return;
    final ok = await confirmAcc(
      context,
      title: 'Bill this ticket?',
      body: 'A draft invoice is created for this work. You can preview the tax and issue it from the draft.',
      confirmLabel: 'Create draft',
    );
    if (!ok || !mounted) return;
    setState(() => _billing = true);
    try {
      final doc = await ref.read(accountingRepositoryProvider).invoiceFromTicket(t.id, documentDate: isoDay(DateTime.now()));
      invalidateAccountingReads(ref.invalidate);
      refreshTickets(ref);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Draft invoice created');
      if (doc != null) context.push('${Routes.accDocumentDetail}?id=${doc.id}');
    } on AppError catch (e) {
      if (mounted) ref.read(toastProvider.notifier).showError(e.message);
    } finally {
      if (mounted) setState(() => _billing = false);
    }
  }
}

/// The triage Customer picker: "No customer" plus a server-side search.
class _CustomerPickerSheet extends ConsumerStatefulWidget {
  const _CustomerPickerSheet({required this.current, required this.onPick});

  final String current;
  final ValueChanged<String> onPick;

  @override
  ConsumerState<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends ConsumerState<_CustomerPickerSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ticketCustomerSearchProvider(_search.trim()));
    final rows = async.valueOrNull?.$1 ?? const <({String id, String name})>[];
    return Padding(
      padding: EdgeInsets.only(bottom: 16.h + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SheetHeader(title: 'Customer'),
        Padding(
          padding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 10.h),
          child: _SearchField(hint: 'Search customers…', onChanged: (v) => setState(() => _search = v)),
        ),
        Flexible(
          child: ListView(shrinkWrap: true, children: [
            _pickRow('', 'No customer', widget.current.isEmpty),
            if (async.isLoading && rows.isEmpty)
              Padding(padding: EdgeInsets.all(16.w), child: const Center(child: CircularProgressIndicator())),
            if (!async.isLoading && rows.isEmpty && _search.trim().isNotEmpty)
              Padding(
                padding: EdgeInsets.all(16.w),
                child: Text('No customers match “${_search.trim()}”',
                    style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
              ),
            for (final c in rows) _pickRow(c.id, c.name, c.id == widget.current),
          ]),
        ),
      ]),
    );
  }

  Widget _pickRow(String value, String label, bool active) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onPick(value),
        child: Container(
          margin: EdgeInsets.fromLTRB(18.w, 0, 18.w, 8.h),
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 13.h),
          decoration: BoxDecoration(
            color: active ? AppColors.blueSubtle : AppColors.white,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: active ? const Color(0xFFA6D1FF) : AppColors.borderCardSoft),
          ),
          child: Row(children: [
            Expanded(child: Text(label, style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary))),
            if (active) Icon(PhosphorIconsBold.check, size: 16.sp, color: AppColors.blueBright),
          ]),
        ),
      );
}

/// "Attach a child ticket": search tickets that have no parent (never the
/// ticket itself), pick one, Attach. A refusal is shown inline in the picker
/// — the user is mid-choice and needs to pick a different ticket.
class _AttachChildSheet extends ConsumerStatefulWidget {
  const _AttachChildSheet({required this.parent});

  final Ticket parent;

  @override
  ConsumerState<_AttachChildSheet> createState() => _AttachChildSheetState();
}

class _AttachChildSheetState extends ConsumerState<_AttachChildSheet> {
  String _search = '';
  String _picked = '';
  String? _error;
  bool _submitting = false;

  Future<void> _attach() async {
    if (_picked.isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(ticketsRepositoryProvider).setParent(_picked, widget.parent.id);
      if (mounted) Navigator.of(context).pop(true);
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = hierarchyErrorCopy(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ticketAttachCandidatesProvider(_search.trim()));
    final candidates = [
      for (final c in async.valueOrNull ?? const <Ticket>[])
        if (c.id != widget.parent.id) c,
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: 16.h + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        SheetHeader(title: 'Attach a child ticket'),
        Padding(
          padding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 10.h),
          child: _SearchField(
              hint: 'Search tickets by subject or reference…', onChanged: (v) => setState(() => _search = v)),
        ),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: 320.h),
            child: async.isLoading && candidates.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : candidates.isEmpty
                    ? Padding(
                        padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 12.h),
                        child: Text("No eligible tickets. Tickets that already have a parent can't be attached.",
                            style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                      )
                    : ListView(shrinkWrap: true, padding: EdgeInsets.symmetric(horizontal: 18.w), children: [
                        for (final c in candidates)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() {
                              _picked = c.id;
                              _error = null;
                            }),
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 11.h),
                              decoration: BoxDecoration(
                                color: _picked == c.id ? AppColors.bgChipGrey : Colors.transparent,
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Row(children: [
                                Icon(_picked == c.id ? PhosphorIconsBold.check : PhosphorIconsRegular.circle,
                                    size: 15.sp, color: _picked == c.id ? AppColors.navy : AppColors.textPlaceholder),
                                SizedBox(width: 10.w),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(c.subject.isNotEmpty ? c.subject : 'Untitled ticket',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textBody)),
                                    Text('${c.displayRef} · ${c.statusName}',
                                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                                  ]),
                                ),
                              ]),
                            ),
                          ),
                      ]),
          ),
        ),
        if (_error != null)
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 0),
            child: Text(_error!, style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.error)),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 0),
          child: Row(children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(false),
                child: Container(
                  height: 44.h,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11.r),
                    border: Border.all(color: AppColors.borderInput),
                  ),
                  child: Text('Cancel', style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textBody)),
                ),
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _picked.isEmpty || _submitting ? null : _attach,
                child: Opacity(
                  opacity: _picked.isEmpty || _submitting ? 0.5 : 1,
                  child: Container(
                    height: 44.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(11.r)),
                    child: Text(_submitting ? 'Attaching…' : 'Attach',
                        style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.white)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.hint, required this.onChanged});

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44.h,
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(11.r),
        border: Border.all(color: AppColors.borderInput),
      ),
      child: Row(children: [
        Icon(PhosphorIconsRegular.magnifyingGlass, size: 16.sp, color: AppColors.textMuted),
        SizedBox(width: 8.w),
        Expanded(
          child: TextField(
            onChanged: onChanged,
            style: AppText.custom(size: 14, weight: FontWeight.w500, color: AppColors.textBody),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: hint,
              hintStyle: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textPlaceholder),
            ),
          ),
        ),
      ]),
    );
  }
}
