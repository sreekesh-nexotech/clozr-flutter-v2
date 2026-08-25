import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/status_pill.dart';
// Prefixed: `finance_widgets` exports its own, lighter `NoteEntry` for the
// notes card, and both are needed here.
import '../../../../core/models/note.dart' as notes_model;
import '../../../../core/network/app_error.dart';
import '../../../../data/api/roster.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../../data/api/status_keys.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/audit_log_providers.dart';
import '../../application/providers/crm_catalog_providers.dart';
import '../../application/providers/crm_notes_providers.dart';
import '../../application/providers/crm_party_providers.dart';
import '../../application/providers/crm_module_schema_providers.dart';
import '../../application/providers/invoices_providers.dart';
import '../../application/providers/payments_providers.dart';
import '../../application/record_rows.dart';
import '../../application/providers/quotes_providers.dart';
import '../../domain/entities/audit_entry.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/quote.dart';
import '../../infrastructure/data_sources/local/crm_party_directory.dart';
import '../components/crm_async.dart';
import '../components/finance_widgets.dart';
import '../components/inline_edit_row.dart';
import '../components/status_sheet.dart';

/// Quote detail — header card with status/accept actions, related link, meta
/// rows, line items + totals, notes and activity.
class QuoteDetailScreen extends ConsumerWidget {
  const QuoteDetailScreen({super.key});

  /// Pull-to-refresh: the quote list this record is read out of, plus the
  /// party directory its Bill-to block resolves names through.
  Future<void> _refresh(WidgetRef ref, String uuid) async {
    ref.invalidate(quotesProvider);
    ref.invalidate(crmPartyLookupProvider);
    ref.invalidate(quoteDetailSchemaFutureProvider);
    // The status button and pill are the org's own statuses.
    ref.invalidate(quoteStatusCatalogProvider);
    // Whole family: the notes notifier loads in its constructor, so dropping it
    // is what re-reads the thread.
    ref.invalidate(crmNotesProvider);
    if (uuid.isNotEmpty) {
      ref.invalidate(quoteRowProvider(uuid));
      ref.invalidate(quoteActivityLogProvider(uuid));
    }
    await settle([
      ref.read(quotesProvider.future),
      ref.read(quoteDetailSchemaFutureProvider.future),
      ref.read(quoteStatusCatalogProvider.future),
      if (uuid.isNotEmpty) ref.read(quoteRowProvider(uuid).future),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final async = ref.watch(quotesProvider);

    Widget scaffold(Widget child) => Container(
          color: AppColors.bgDetail,
          child: Column(
            children: [
              DetailAppBar(section: 'Quote', onBack: () => context.pop()),
              Expanded(child: child),
            ],
          ),
        );

    return async.when(
      loading: () => scaffold(const DetailSkeleton()),
      error: (e, _) => scaffold(
        ErrorState.forError(crmAppError(e), onRetry: () => ref.invalidate(quotesProvider)),
      ),
      data: (_) => _buildQuote(context, ref, id, scaffold),
    );
  }

  Widget _buildQuote(
    BuildContext context,
    WidgetRef ref,
    String id,
    Widget Function(Widget) scaffold,
  ) {
    final quote = ref.watch(quoteByIdProvider(id));
    if (quote == null) {
      return scaffold(const EmptyState(
        icon: PhosphorIconsRegular.fileText,
        title: 'Quote not found',
        body: 'This quote may have been removed or you no longer have access to it.',
      ));
    }

    final lookup = ref.watch(crmPartyLookupProvider);
    // The org's own status name and colour, so the pill and the status button
    // read the same word the tab row and the list card do.
    final meta = quoteStatusMeta(quote, ref.watch(quoteStatusOptionsProvider));
    final owner = MockUsers.of(quote.owner);
    final party = lookup(custId: quote.custId, leadId: quote.leadId);
    final isCust = quote.custId != null && lookup(custId: quote.custId) != null;
    final canAccept = quote.status == 'sent' || quote.status == 'draft';

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: 'Quote',
            name: quoteHeadline(quote, lookup),
            onBack: () => context.pop(),
            trailing: DetailIconAction(
              icon: PhosphorIconsBold.dotsThreeVertical,
              onTap: () => ref.read(toastProvider.notifier).show('Quote actions'),
            ),
          ),
          Expanded(
            child: AppRefresh(
              onRefresh: () => _refresh(ref, quote.uuid),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
              children: [
                _headerCard(context, ref, quote, meta, canAccept),
                SizedBox(height: 14.h),
                if (party != null) ...[
                  _relatedCard(context, quote, party, isCust),
                  SizedBox(height: 14.h),
                ],
                _detailsCard(ref, quote),
                SizedBox(height: 14.h),
                _lineItemsCard(quote, owner),
                if (quote.note != null && quote.note!.isNotEmpty) ...[
                  SizedBox(height: 14.h),
                  FinanceCard(
                    title: 'Notes',
                    child: Text(quote.note!,
                        style: AppText.custom(size: 14, weight: FontWeight.w500, color: AppColors.textLabelAlt, height: 1.6)),
                  ),
                ],
                SizedBox(height: 14.h),
                _notesCard(ref, quote),
                SizedBox(height: 14.h),
                _activityCard(ref, quote, owner.name),
              ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCard(BuildContext context, WidgetRef ref, Quote quote, StatusMeta meta, bool canAccept) {
    final lookup = ref.watch(crmPartyLookupProvider);
    final issued = quote.issued == '—' ? 'Not issued yet' : 'Issued ${quote.issued}';
    final validity = quote.valid == '—' ? 'no validity set' : 'valid till ${quote.valid}';

    return FinanceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconChip(icon: PhosphorIconsRegular.fileText, size: 46, radius: 13, iconSize: 22),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('#${quote.id}',
                            style: AppText.custom(size: 19, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                        SizedBox(width: 8.w),
                        StatusPill.meta(meta),
                      ],
                    ),
                    SizedBox(height: 3.h),
                    Text(quoteHeadline(quote, lookup),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    SizedBox(height: 4.h),
                    Text('$issued · $validity',
                        style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                  ],
                ),
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 15)),
          Row(
            children: [
              Expanded(
                flex: canAccept ? 10 : 10,
                child: GestureDetector(
                  onTap: () => _openStatusSheet(context, ref, quote),
                  child: Container(
                    height: 44.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(11.r),
                      border: Border.all(color: const Color(0xFFE6E7EA)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 8.w, height: 8.w, decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle)),
                        SizedBox(width: 8.w),
                        Text(meta.label, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textBody)),
                        SizedBox(width: 6.w),
                        Icon(PhosphorIconsBold.caretDown, size: 11.sp, color: AppColors.textMuted2),
                      ],
                    ),
                  ),
                ),
              ),
              if (canAccept) ...[
                SizedBox(width: 10.w),
                Expanded(
                  flex: 14,
                  child: GestureDetector(
                    onTap: () => _acceptAndInvoice(ref, quote),
                    child: Container(
                      height: 44.h,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(11.r)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsBold.check, size: 15.sp, color: AppColors.white),
                          SizedBox(width: 7.w),
                          // Same trap as the invoice screen's primary button:
                          // an unbounded Text in a min-size Row takes its
                          // natural width and overflows rather than shortening.
                          // This row is tighter still — it also carries the
                          // fixed 44px reject square.
                          Flexible(
                            child: Text('Accept & invoice',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.white)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
                GestureDetector(
                  onTap: () => _reject(ref, quote),
                  child: Container(
                    width: 44.w,
                    height: 44.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(11.r),
                      border: Border.all(color: const Color(0xFFF3C1C1), width: 1.5),
                    ),
                    child: Icon(PhosphorIconsBold.x, size: 16.sp, color: AppColors.error),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// The built-in rows, used when the org's detail layout has not loaded (and in
  /// mock mode) — the panel exactly as it was before it became configurable.
  List<(String, String)> _fallbackRows(Quote quote) => [
        ('Template', quote.template),
        ('Payment type', quote.payType),
        ('Currency', quote.currency),
        ('Valid until', quote.valid),
        ('Due date', quote.dueDate.isEmpty ? '—' : quote.dueDate),
      ];

  /// "Quote details" — the org's own detail layout over the raw record.
  ///
  /// Both halves must be present: the schema says which rows and under what
  /// labels, the record supplies their values. Either missing falls back to the
  /// built-in five, so this panel is never empty because a layout call failed.
  ///
  /// `quotation_number`, `quotation_title` and `status` are skipped — the header
  /// card above already renders all three, and repeating them here reads as a
  /// duplicate rather than a readout.
  /// Saves one edited field of the Quote details card
  /// (`PATCH /quotations/quotations/{id}/`, verified against the dev backend).
  ///
  /// Keyed by the record uuid — the `QTN-…` number the header shows is not
  /// something the endpoint resolves.
  Future<void> _saveField(WidgetRef ref, Quote quote, String key, Object? value,
      String label) async {
    if (quote.uuid.isEmpty) return;
    try {
      await ref.read(quotesRepositoryProvider).updateQuote(quote.uuid, {key: value});
      ref.invalidate(quoteRowProvider(quote.uuid));
      ref.invalidate(quotesProvider);
      ref.read(toastProvider.notifier).show('$label updated');
    } on AppError catch (e) {
      ref.read(toastProvider.notifier).showError(e.message);
    }
  }

  Widget _detailsCard(WidgetRef ref, Quote quote) {
    final schema = ref.watch(quoteDetailSchemaProvider);
    // Keyed by the record UUID — `GET /quotations/quotations/{quotation_id}/`.
    // This used to pass `quote.id`, the `QTN-…` display number, which the
    // record endpoint does not resolve, so the panel silently fell back to its
    // built-in five rows on every quote.
    final row = quote.uuid.isEmpty
        ? null
        : ref.watch(quoteRowProvider(quote.uuid)).valueOrNull;
    final rows = (schema.isEmpty || row == null)
        ? [for (final r in _fallbackRows(quote)) (r.$1, r.$2, null)]
        : [
            for (final r in recordRows(row, schema, skip: const {
              'quotation_number',
              'quotation_title',
              'status',
              'line_items',
              'total_amount',
            }))
              (r.label, r.value, r.column),
          ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return FinanceCard(
      title: 'Quote details',
      child: Column(
        children: [
          // Long-press a row to edit it in place; a row that cannot be edited
          // says why rather than ignoring the press.
          for (int i = 0; i < rows.length; i++)
            InlineEditRow(
              label: rows[i].$1,
              display: rows[i].$2,
              column: rows[i].$3,
              rawValue: row?[rows[i].$3?.name],
              editForm: 'Edit quote',
              onSave: (key, value) =>
                  _saveField(ref, quote, key, value, rows[i].$1),
              onBlocked: (msg) => ref.read(toastProvider.notifier).show(msg),
              child: MetaRow(
                  label: rows[i].$1, value: rows[i].$2, last: i == rows.length - 1),
            ),
        ],
      ),
    );
  }

  Widget _relatedCard(BuildContext context, Quote quote, CrmParty party, bool isCust) {
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 15.h),
      onTap: () {
        if (isCust) {
          context.push('${Routes.customerDetail}?id=${quote.custId}');
        } else {
          context.push('${Routes.leadDetail}?id=${quote.leadId}');
        }
      },
      child: Row(
        children: [
          const IconChip(icon: PhosphorIconsRegular.buildings, size: 42, radius: 12, iconSize: 20),
          SizedBox(width: 13.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RELATED',
                    style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.5)),
                SizedBox(height: 2.h),
                Text(party.company,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 1.h),
                Text('${isCust ? 'Customer' : 'Lead'} · #${isCust ? quote.custId : quote.leadId}',
                    style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ),
          ),
          Icon(PhosphorIconsBold.caretRight, size: 15.sp, color: AppColors.textPlaceholder),
        ],
      ),
    );
  }

  Widget _lineItemsCard(Quote quote, AppUser owner) {
    final sub = quote.amountNum.toDouble();
    return FinanceCard(
      title: 'Line items',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final it in quote.items)
            Container(
              padding: EdgeInsets.symmetric(vertical: 11.h),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(it.name, style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textPrimary)),
                        SizedBox(height: 2.h),
                        Text('Qty ${it.qty} · ${it.rate}',
                            style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                      ],
                    ),
                  ),
                  SizedBox(width: 14.w),
                  Text(it.amt, style: AppText.custom(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
                ],
              ),
            ),
          SizedBox(height: 13.h),
          _totalRow('Subtotal', _fmt(sub), muted: true),
          SizedBox(height: 7.h),
          _totalRow('GST (18%)', _fmt(sub * 0.18), muted: true),
          SizedBox(height: 10.h),
          Container(
            padding: EdgeInsets.only(top: 10.h),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderCardSoft))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('TOTAL',
                    style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.4)),
                const Spacer(),
                Text(_fmt(sub * 1.18),
                    style: AppText.custom(size: 20, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
              ],
            ),
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 13)),
          Row(
            children: [
              Container(
                width: 38.w,
                height: 38.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: owner.color, shape: BoxShape.circle),
                child: Text(owner.initials, style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.white)),
              ),
              SizedBox(width: 11.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(owner.name, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text('Quote owner', style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool muted = false}) {
    return Row(
      children: [
        Text(label, style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
        const Spacer(),
        Text(value, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
      ],
    );
  }

  /// "Internal notes" — the shared CRM notes thread, scoped to this quote.
  ///
  /// `related_to=quotation` follows the house pattern (the lowercased model
  /// name, per `customer.md`'s Related-records table). The notifier is
  /// deliberately forgiving: a fetch that fails leaves the thread empty and an
  /// add that fails keeps the optimistic entry, so a backend that does not
  /// accept notes on quotations degrades to the local-only behaviour this card
  /// already had rather than erroring.
  Widget _notesCard(WidgetRef ref, Quote quote) {
    // No uuid → nothing to attach a note to; stays local-only.
    final seed = CrmNotesSeed(
      quote.uuid.isEmpty ? 'QUOTE-${quote.id}' : quote.uuid,
      () => const <notes_model.NoteEntry>[],
      apiModel: quote.uuid.isEmpty ? null : 'quotation',
    );
    final thread = ref.watch(crmNotesProvider(seed));
    return NotesCard(
      title: 'Internal notes',
      // The card carries its own lighter row type — no replies, no
      // attachments, initials instead of a colour — so the thread is mapped
      // across rather than shared.
      notes: [
        for (final n in thread)
          NoteEntry(
            initials: _initialsOf(n.author),
            author: n.author,
            time: n.time,
            body: n.body,
          ),
      ],
      countLabel: thread.isEmpty ? null : '${thread.length}',
      onSend: (body) {
        ref
            .read(crmNotesProvider(seed).notifier)
            .addNote(body, const [], ref.read(noteAuthorProvider));
        ref.read(toastProvider.notifier).show('Note added');
      },
    );
  }

  /// Up to two initials from a display name, for the note avatar.
  static String _initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  /// "Activity" — the record's real audit trail.
  ///
  /// `?model_name=Quotation&record_id=<uuid>`, refetched off the API write tick
  /// so every PATCH/POST/DELETE this screen makes (a status move, Accept &
  /// invoice, a note) lands here without the call sites saying so.
  ///
  /// Falls back to the derived timeline when the log is empty — mock mode, a
  /// quote with no uuid, or a role without `view_audit_log`, which 403s. That
  /// keeps the card from vanishing for users who simply cannot read the trail.
  Widget _activityCard(WidgetRef ref, Quote quote, String ownerName) {
    final entries = quote.uuid.isEmpty
        ? const <AuditEntry>[]
        : ref.watch(quoteActivityLogProvider(quote.uuid)).valueOrNull ?? const [];
    final rows = entries.isEmpty
        ? _activity(quote, ownerName)
        : [for (final e in entries) _auditRow(e)];
    return FinanceCard(
      title: 'Activity',
      child: Padding(
        padding: EdgeInsets.only(top: 6.h),
        child: ActivityTimeline(entries: rows),
      ),
    );
  }

  /// One audit row as a timeline entry, iconed by what kind of event it was.
  ActivityEntry _auditRow(AuditEntry e) {
    final (icon, tone, bg) = switch (e.kind) {
      AuditEventKind.created => (PhosphorIconsRegular.fileText, AppColors.blueBright, AppColors.tintBlue),
      AuditEventKind.statusChanged => (PhosphorIconsRegular.arrowsClockwise, AppColors.warning, AppColors.tintAmber),
      AuditEventKind.noteAdded => (PhosphorIconsRegular.note, AppColors.pending, AppColors.tintPurple),
      AuditEventKind.childAdded => (PhosphorIconsRegular.plusCircle, AppColors.success, AppColors.tintGreen),
      AuditEventKind.deleted => (PhosphorIconsRegular.trash, AppColors.error, AppColors.tintRed),
      _ => (PhosphorIconsRegular.pencilSimple, AppColors.blueBright, AppColors.tintBlue),
    };
    // Actor and "2h ago" on one line — the timeline gives each row a single
    // sub-line, and both are worth more than either alone.
    final when = e.at == null ? '' : relativeTime(e.at);
    final sub = [e.subtitle, e.actor, when].where((s) => s.isNotEmpty).join(' · ');
    return ActivityEntry(icon: icon, tone: tone, bg: bg, title: e.title, sub: sub);
  }

  /// The derived timeline, used when the audit trail is unavailable.
  List<ActivityEntry> _activity(Quote quote, String ownerName) {
    final entries = <ActivityEntry>[
      ActivityEntry(
        icon: PhosphorIconsRegular.fileText,
        tone: AppColors.blueBright,
        bg: AppColors.tintBlue,
        title: 'Quote created',
        sub: 'Issued ${quote.issued == '—' ? '—' : quote.issued} · $ownerName',
      ),
    ];
    if (quote.status != 'draft') {
      entries.insert(
        0,
        ActivityEntry(
          icon: PhosphorIconsRegular.paperPlaneTilt,
          tone: AppColors.warning,
          bg: AppColors.tintAmber,
          title: 'Sent to client',
          sub: quote.valid == '—' ? 'Awaiting validity' : 'Valid till ${quote.valid}',
        ),
      );
    }
    if (quote.status == 'accepted' || quote.status == 'rejected' || quote.status == 'expired') {
      final accepted = quote.status == 'accepted';
      final label = (StatusMeta$.quote[quote.status] ?? StatusMeta$.quote['draft']!).label.toLowerCase();
      entries.insert(
        0,
        ActivityEntry(
          icon: accepted ? PhosphorIconsRegular.checkCircle : PhosphorIconsRegular.xCircle,
          tone: accepted ? AppColors.success : AppColors.error,
          bg: accepted ? AppColors.tintGreen : AppColors.tintRed,
          title: 'Quote $label',
          sub: accepted ? 'Invoice generated from this quote' : 'Closed without conversion',
        ),
      );
    }
    return entries;
  }

  /// Moves the quote to another status.
  ///
  /// The options are the org's own statuses when `/quotations/statuses/` has
  /// loaded — keyed by `quotation_status_id`, which is what the PATCH sends —
  /// and the built-in five otherwise. Without the catalog there is no id to
  /// write, so that path stays toast-only rather than sending a key the server
  /// would reject.
  Future<void> _openStatusSheet(BuildContext context, WidgetRef ref, Quote quote) async {
    final catalog = ref.read(quoteStatusOptionsProvider);
    if (catalog.isEmpty) {
      const order = ['draft', 'sent', 'accepted', 'rejected', 'expired'];
      final chosen = await showStatusSheet(
        context: context,
        title: 'Quote status',
        currentKey: quote.status,
        options: [for (final k in order) StatusOption(k, StatusMeta$.quote[k]!)],
      );
      if (chosen != null && chosen != quote.status) {
        ref.read(toastProvider.notifier).show('Status set to ${StatusMeta$.quote[chosen]!.label}');
      }
      return;
    }

    final current = quoteStatusMeta(quote, catalog);
    final chosen = await showStatusSheet(
      context: context,
      title: 'Quote status',
      // Keyed by id so the pick is directly writable; the check mark matches on
      // the name, which is what the record carries.
      currentKey: [
        for (final s in catalog)
          if (s.key == quote.statusName.trim().toLowerCase()) s.id,
      ].firstOrNull ?? '',
      options: [
        for (final s in catalog)
          StatusOption(s.id, StatusMeta(s.name, s.color ?? current.color)),
      ],
    );
    if (chosen == null) return;

    final picked = catalog.firstWhere((s) => s.id == chosen);
    if (picked.key == quote.statusName.trim().toLowerCase()) return; // unchanged
    await _writeStatus(ref, quote, picked, 'Status set to ${picked.name}');
  }

  /// The one place a quote's status is written.
  ///
  /// Shared by the status sheet, Accept & invoice and Reject so all three
  /// refresh the same set — and so the invoice side effect is described in one
  /// place rather than three.
  Future<void> _writeStatus(
    WidgetRef ref,
    Quote quote,
    CatalogOption status,
    String success,
  ) async {
    final toast = ref.read(toastProvider.notifier);
    if (quote.uuid.isEmpty) {
      toast.showError('This quote cannot be updated — its record id is missing.');
      return;
    }
    try {
      await ref.read(quotesRepositoryProvider).updateQuoteStatus(quote.uuid, status.id);
    } on AppError catch (e) {
      toast.showError(e.message);
      return;
    }
    // The list is what the screen reads the quote out of, and the raw row backs
    // the "Quote details" panel. The activity log refreshes itself off the
    // write tick, so it is deliberately not listed here.
    ref.invalidate(quotesProvider);
    ref.invalidate(quoteRowProvider(quote.uuid));
    // Entering the converted status creates the invoice and its records, and
    // leaving it **deletes** them (doc §2b). Either way the Payments screen is
    // now wrong until these refetch.
    ref.invalidate(invoicesProvider);
    ref.invalidate(paymentsProvider);
    toast.show(success);
  }

  /// Accept & invoice — moves the quote into the org's converted status.
  ///
  /// The invoice is **not** created here: per doc §4 the server raises the
  /// `Payment` + `PaymentRecord`s itself when a quote enters an `is_converted`
  /// status (and deletes them when it leaves). So this is the same PATCH as any
  /// other status move, and the message only claims an invoice because that
  /// status is what the flag means.
  Future<void> _acceptAndInvoice(WidgetRef ref, Quote quote) async {
    final converted =
        ref.read(quoteStatusOptionsProvider).where((s) => s.isConverted).firstOrNull;
    if (converted == null) {
      ref.read(toastProvider.notifier).showError(
          'No accepted status is configured for quotes — ask an admin to set one.');
      return;
    }
    await _writeStatus(ref, quote, converted, 'Quote accepted · invoice generated');
  }

  /// Reject — the cross beside Accept & invoice.
  ///
  /// There is no `is_rejected` flag to match on (only `is_converted` exists), so
  /// the target is found by folding each org status name through
  /// [quoteStatusKey], the same folding the rest of the app uses.
  Future<void> _reject(WidgetRef ref, Quote quote) async {
    final rejected = ref
        .read(quoteStatusOptionsProvider)
        .where((s) => quoteStatusKey(name: s.name) == 'rejected')
        .firstOrNull;
    if (rejected == null) {
      ref.read(toastProvider.notifier).showError(
          'No rejected status is configured for quotes — ask an admin to set one.');
      return;
    }
    await _writeStatus(ref, quote, rejected, 'Quote rejected');
  }

  /// The prototype's `fmt` for the totals block: Cr above ₹1Cr, else L.
  String _fmt(double v) {
    if (v >= 10000000) {
      var s = (v / 10000000).toStringAsFixed(2);
      if (s.endsWith('.00')) s = s.substring(0, s.length - 3);
      return '₹${s}Cr';
    }
    var s = (v / 100000).toStringAsFixed(1);
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    return '₹${s}L';
  }
}
