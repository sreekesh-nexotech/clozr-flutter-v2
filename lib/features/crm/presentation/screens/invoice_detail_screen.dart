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
import '../../../../core/config/api_config.dart';
// Prefixed: `finance_widgets` exports its own, lighter `NoteEntry` for the card.
import '../../../../core/models/note.dart' as notes_model;
import '../../../../core/network/app_error.dart';
import '../../../../data/api/roster.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/api/status_keys.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/crm_notes_providers.dart';
import '../../application/providers/crm_party_providers.dart';
import '../../application/providers/crm_module_schema_providers.dart';
import '../../application/providers/invoices_providers.dart';
import '../../application/record_rows.dart';
import '../../application/providers/payments_providers.dart';
import '../../domain/entities/invoice.dart';
import '../../domain/entities/payment.dart';
import '../../infrastructure/data_sources/local/crm_party_directory.dart';
import '../components/crm_async.dart';
import '../components/finance_widgets.dart';
import '../components/record_payment_sheet.dart';

/// Invoice detail — header (id + status, total/paid/balance, action buttons) and
/// the installment schedule (tappable payment rows), plus notes.
class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({super.key});

  /// Pull-to-refresh: the invoice list, the payment schedule against it, and
  /// the party directory.
  /// [id] is the display id the schedule joins on; [uuid] is the `payment_id`
  /// the record and summary calls address.
  Future<void> _refresh(WidgetRef ref, String id, String uuid) async {
    ref.invalidate(invoicesProvider);
    ref.invalidate(paymentsProvider);
    ref.invalidate(paymentsForInvoiceProvider(id));
    ref.invalidate(paymentDetailSchemaFutureProvider);
    ref.invalidate(crmPartyLookupProvider);
    // Whole family: the notes notifier loads in its constructor, so dropping it
    // is what re-reads the thread.
    ref.invalidate(crmNotesProvider);
    if (uuid.isNotEmpty) {
      ref.invalidate(paymentRowProvider(uuid));
      ref.invalidate(invoiceSummaryProvider(uuid));
    }
    await settle([
      ref.read(invoicesProvider.future),
      ref.read(paymentsProvider.future),
      ref.read(paymentDetailSchemaFutureProvider.future),
      if (uuid.isNotEmpty) ref.read(paymentRowProvider(uuid).future),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final async = ref.watch(invoicesProvider);

    Widget scaffold(Widget child) => Container(
          color: AppColors.bgDetail,
          child: Column(
            children: [
              DetailAppBar(section: 'Invoice', onBack: () => context.pop()),
              Expanded(child: child),
            ],
          ),
        );

    return async.when(
      loading: () => scaffold(const DetailSkeleton()),
      error: (e, _) => scaffold(
        ErrorState.forError(crmAppError(e), onRetry: () => ref.invalidate(invoicesProvider)),
      ),
      data: (_) => _buildInvoice(context, ref, id, scaffold),
    );
  }

  Widget _buildInvoice(
    BuildContext context,
    WidgetRef ref,
    String id,
    Widget Function(Widget) scaffold,
  ) {
    final invoice = ref.watch(invoiceByIdProvider(id));
    if (invoice == null) {
      return scaffold(const EmptyState(
        icon: PhosphorIconsRegular.receipt,
        title: 'Invoice not found',
        body: 'This invoice may have been removed or you no longer have access to it.',
      ));
    }

    final lookup = ref.watch(crmPartyLookupProvider);
    final cust = lookup(custId: invoice.custId);
    final schedule = ref.watch(paymentsForInvoiceProvider(invoice.id));
    // The server's own figures where they are available (doc §2b's `summary`),
    // the header row's `amount_paid` otherwise. Summing the schedule's paid
    // rows — what this used to do — disagrees with both the moment a record is
    // part-paid, because a schedule row only knows its full face value.
    final summary = ref.watch(invoiceSummaryProvider(invoice.uuid)).valueOrNull;
    final paidNum = summary?.paidNum ?? invoice.paidNum;
    // The pill follows the same precedence as the figures beside it: the
    // server's own status from `summary` when it has arrived, the list row's
    // derived one otherwise. Without this the header could read "Unpaid" next
    // to a non-zero PAID total, because the two came from different sources.
    final statusKey = summary == null
        ? invoice.status
        : invoiceStatusKey(status: summary.status, amountPaid: summary.paidNum.toDouble());
    final meta = StatusMeta$.invoice[statusKey] ?? StatusMeta$.invoice['partial']!;

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: 'Invoice',
            name: invoiceWho(invoice, lookup),
            onBack: () => context.pop(),
            trailing: DetailIconAction(
              icon: PhosphorIconsBold.dotsThreeVertical,
              onTap: () => ref.read(toastProvider.notifier).show('Invoice actions'),
            ),
          ),
          Expanded(
            child: AppRefresh(
              onRefresh: () => _refresh(ref, invoice.id, invoice.uuid),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
              children: [
                _headerCard(context, ref, invoice, meta, cust, paidNum, summary),
                SizedBox(height: 14.h),
                _detailsCard(ref, invoice),
                FinanceCard(
                  title: 'Installment schedule',
                  child: Column(
                    children: [
                      for (int i = 0; i < schedule.length; i++)
                        _scheduleRow(context, ref, schedule[i], last: i == schedule.length - 1),
                    ],
                  ),
                ),
                SizedBox(height: 14.h),
                _notesCard(ref, invoice),
              ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "Invoice details" — the org's `payment` detail layout over the raw record.
  ///
  /// New with the schema wiring: this screen had no field readout at all, only a
  /// header, the installment schedule and notes. So unlike the other detail
  /// panels there is **no built-in fallback** — an empty schema renders nothing,
  /// which leaves the page exactly as it was in mock mode, on a failed fetch, or
  /// for an org the backend has not seeded a payment layout for.
  Widget _detailsCard(WidgetRef ref, Invoice invoice) {
    final schema = ref.watch(paymentDetailSchemaProvider);
    // Keyed by `payment_id` — `GET /quotations/payments/{payment_id}/`. This
    // used to pass `invoice.id`, which is the source quote's `QTN-…` number,
    // so the record never resolved and this panel rendered nothing at all.
    final row = invoice.uuid.isEmpty
        ? null
        : ref.watch(paymentRowProvider(invoice.uuid)).valueOrNull;
    if (schema.isEmpty || row == null) return const SizedBox.shrink();
    // The header card already carries who it is for, the status and the total.
    final rows = recordRows(row, schema, skip: const {
      'customer',
      'customer_name',
      'lead',
      'lead_name',
      'status',
      'total_amount',
      'installments',
      'payment_records',
    });
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        FinanceCard(
          title: 'Invoice details',
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++)
                MetaRow(
                    label: rows[i].label,
                    value: rows[i].value,
                    last: i == rows.length - 1),
            ],
          ),
        ),
        SizedBox(height: 14.h),
      ],
    );
  }

  /// The one-line schedule note under the invoice type: what is overdue, or
  /// when the next installment falls due. Both come only from `summary` —
  /// nothing in the list payload carries them.
  ///
  /// Null when there is nothing to say: a settled invoice with no next due date
  /// and nothing overdue.
  static String? _scheduleNote(InvoiceSummary s) {
    if (s.overdueRecords > 0) {
      final n = s.overdueRecords;
      return '$n ${n == 1 ? 'installment' : 'installments'} overdue';
    }
    final due = s.nextDue;
    return due == null ? null : 'Next due ${absoluteDate(due)}';
  }

  Widget _headerCard(BuildContext context, WidgetRef ref, Invoice invoice,
      StatusMeta meta, CrmParty? cust, int paidNum, InvoiceSummary? summary) {
    return FinanceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconChip(icon: PhosphorIconsRegular.receipt, size: 46, radius: 13, iconSize: 22),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(invoice.id,
                            style: AppText.custom(size: 18, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                        SizedBox(width: 8.w),
                        StatusPill.meta(meta),
                      ],
                    ),
                    SizedBox(height: 3.h),
                    Text('${cust?.company ?? invoice.custId ?? '—'} · ${cust?.name ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    SizedBox(height: 3.h),
                    // Counts prefer the server's, which apply the org's own
                    // overdue rule — something the app cannot reproduce.
                    Text('${invoice.type} · ${summary?.paidRecords ?? invoice.settled}'
                        ' of ${summary?.totalRecords ?? invoice.of} settled',
                        style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                    if (summary != null && _scheduleNote(summary) != null) ...[
                      SizedBox(height: 3.h),
                      Text(_scheduleNote(summary)!,
                          style: AppText.custom(
                              size: 12,
                              weight: FontWeight.w700,
                              color: summary.overdueRecords > 0
                                  ? AppColors.error
                                  : AppColors.textMuted)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 15)),
          Row(
            children: [
              _stat('TOTAL', invoice.total, AppColors.textPrimary),
              _stat('PAID', paidNum == 0 ? '₹0L' : _fmtAmt(paidNum), AppColors.success),
              _stat('BALANCE', invoice.balance, AppColors.error),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 15)),
          // Weights on all three, not just the last: the primary action carried
          // `flex: 12` while the other two defaulted to 1, so the row split
          // 12 : 1 : 1 and gave each ghost button ~20px — less than its own icon
          // plus gap. 9 : 9 : 14 is sized to the labels rather than picked for
          // looks: "Record payment" needs about 122px beside its icon, which 14
          // parts covers on a 360dp screen, and 9 fits "Customer" with the quote
          // chip ellipsising when its number runs long.
          Row(
            children: [
              Expanded(
                flex: 9,
                child: _ghostButton(
                  icon: PhosphorIconsRegular.buildings,
                  label: 'Customer',
                  onTap: () {
                    if (cust != null) {
                      context.push('${Routes.customerDetail}?id=${cust.id}');
                      return;
                    }
                    // A quote only gains a customer when its lead converts, so
                    // an invoice raised against an unconverted lead has none.
                    // Saying so beats a button that silently does nothing.
                    ref
                        .read(toastProvider.notifier)
                        .show('No customer linked — its lead has not converted yet');
                  },
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                flex: 9,
                child: _ghostButton(
                  icon: PhosphorIconsRegular.fileText,
                  label: '#${invoice.quoteId ?? '—'}',
                  onTap: () {
                    if (invoice.quoteId != null) {
                      context.push('${Routes.quoteDetail}?id=${invoice.quoteId}');
                    } else {
                      ref.read(toastProvider.notifier).show('Quote not found');
                    }
                  },
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                flex: 14,
                child: GestureDetector(
                  // Opens the sheet against *this* invoice. It used to only
                  // toast its own label, which is why no request was ever made
                  // from this screen.
                  onTap: () => showRecordPaymentSheet(context, invoiceId: invoice.id),
                  child: Container(
                    height: 44.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(11.r)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsBold.plus, size: 14.sp, color: AppColors.white),
                        SizedBox(width: 7.w),
                        // Flexible, or the ellipsis never engages: an unbounded
                        // Text takes its natural width and overflows the button
                        // rather than shortening inside it. `_ghostButton` had
                        // this right; this one did not.
                        Flexible(
                          child: Text('Record payment',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.4)),
          SizedBox(height: 3.h),
          Text(value, style: AppText.custom(size: 17, weight: FontWeight.w800, color: valueColor)),
        ],
      ),
    );
  }

  Widget _ghostButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
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
            Icon(icon, size: 16.sp, color: AppColors.textSecondary),
            SizedBox(width: 7.w),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textBody)),
            ),
          ],
        ),
      ),
    );
  }

  /// The invoice's notes thread, on the shared CRM notes engine.
  ///
  /// Hung off the **source quotation**, not the payment: `payment` is not an
  /// accepted `related_to` model — the API answers
  /// `Invalid model name. Must be one of: lead, deal, contact, customer,
  /// organization_contact, product, issue, task, project, project_task,
  /// quotation`. So an invoice and the quote it came from share one thread.
  /// That is the backend's shape rather than a choice: there is no notes bucket
  /// for a Payment to own.
  ///
  /// An invoice with no source quote keeps a local-only thread, since there is
  /// then nothing valid to attach a note to.
  Widget _notesCard(WidgetRef ref, Invoice invoice) {
    final quoteUuid = invoice.quoteUuid ?? '';
    final seed = CrmNotesSeed(
      quoteUuid.isEmpty ? 'INV-${invoice.id}' : quoteUuid,
      () => const <notes_model.NoteEntry>[],
      apiModel: quoteUuid.isEmpty ? null : 'quotation',
    );
    final thread = ref.watch(crmNotesProvider(seed));
    return NotesCard(
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

  /// Settles one installment — `PATCH /quotations/payment-records/{record_id}/`
  /// (doc §2b). This row's own record, not the sheet's "next unpaid one".
  ///
  /// Optimistic, then rolled back if the write is refused, mirroring the Record
  /// payment sheet. The server recalculates the parent invoice — `amount_paid`,
  /// `next_due_date`, completion — so both lists are refetched, and the summary
  /// follows on the write tick.
  Future<void> _settle(WidgetRef ref, Payment p) async {
    final prev = ref.read(paidOverrideProvider);
    ref.read(paidOverrideProvider.notifier).state = {...prev, p.id};

    if (ApiConfig.apiEnabled) {
      try {
        await ref.read(paymentsRepositoryProvider).markRecordPaid(
              p.id,
              amount: p.amountNum > 0 ? p.amountNum.toDouble() : null,
            );
      } on AppError catch (e) {
        ref.read(paidOverrideProvider.notifier).state = {...prev};
        ref.read(toastProvider.notifier).showError(e.message);
        return;
      }
      ref.invalidate(paymentsProvider);
      ref.invalidate(invoicesProvider);
    }
    ref.read(toastProvider.notifier).show('Installment settled');
  }

  Widget _scheduleRow(BuildContext context, WidgetRef ref, Payment p, {required bool last}) {
    final meta = StatusMeta$.payment[p.status] ?? StatusMeta$.payment['due']!;
    final methodLabel = p.method == '—' ? 'Not set' : p.method;
    final canPay = p.status != 'paid';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('${Routes.paymentDetail}?id=${p.id}'),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        decoration: last ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconChip(icon: payMethodIcon(p.method), iconSize: 18),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.label, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  SizedBox(height: 2.h),
                  Text('${p.id} · $methodLabel', style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                  SizedBox(height: 2.h),
                  Text(p.date, style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: paymentDateColor(p.status))),
                ],
              ),
            ),
            SizedBox(width: 10.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(p.amount, style: AppText.custom(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
                SizedBox(height: 5.h),
                StatusPill.meta(meta),
                if (canPay) ...[
                  SizedBox(height: 5.h),
                  GestureDetector(
                    onTap: () => _settle(ref, p),
                    child: Text('Settle now',
                        style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.blueBright)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The prototype's `fmtAmt` for the paid total (Cr above ₹1Cr, else L).
  String _fmtAmt(int x) {
    if (x >= 10000000) {
      return '₹${_trim((x / 100000).round() / 100)}Cr';
    }
    return '₹${_trim((x / 10000).round() / 10)}L';
  }

  String _trim(num v) {
    var s = v.toString();
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    return s;
  }
}
