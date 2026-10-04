import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../crm/application/providers/invoices_providers.dart';
import '../../../crm/application/providers/quotes_providers.dart';
import '../../../crm/presentation/components/crm_detail_parts.dart';
import '../../../crm/presentation/components/finance_widgets.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/accounting_invalidation.dart';
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/documents_providers.dart';
import '../../domain/entities/acc_document.dart';
import '../components/acc_widgets.dart';
import '../components/document_card.dart';
import '../components/journal_entry_card.dart';
import '../config/accounting_copy.dart';
import '../sheets/acc_sheet_scaffold.dart';
import '../sheets/cancel_document_sheet.dart';
import '../sheets/credit_note_sheet.dart';
import '../sheets/edit_draft_sheet.dart';
import '../sheets/issue_document_sheet.dart';
import '../sheets/record_receipt_sheet.dart';
import '../sheets/vendor_payment_sheet.dart';

/// Document detail (plan §4.3) — any accounting document: header with the
/// money, the warnings, then Details · Items · Tax · Journal · Links, and the
/// actions its status allows in a sticky bar.
class AccDocumentDetailScreen extends ConsumerStatefulWidget {
  const AccDocumentDetailScreen({super.key});

  @override
  ConsumerState<AccDocumentDetailScreen> createState() => _AccDocumentDetailScreenState();
}

class _AccDocumentDetailScreenState extends ConsumerState<AccDocumentDetailScreen> {
  int _tab = 0;
  bool _busy = false;

  static const _tabs = ['Details', 'Items', 'Tax', 'Journal', 'Links'];

  String get _id => GoRouterState.of(context).uri.queryParameters['id'] ?? '';

  Future<void> _refresh() async {
    ref.invalidate(accDocumentProvider(_id));
    ref.invalidate(documentJournalProvider(_id));
    await settle([ref.read(accDocumentProvider(_id).future)]);
  }

  @override
  Widget build(BuildContext context) {
    final id = _id;
    final async = ref.watch(accDocumentProvider(id));
    final doc = async.valueOrNull;

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: doc == null ? 'Invoice' : label(docTypeLabels, doc.docType),
            name: doc?.displayNumber,
            onBack: () => context.pop(),
            trailing: doc == null
                ? null
                : DetailIconAction(icon: PhosphorIconsBold.dotsThreeVertical, onTap: () => _menu(doc)),
          ),
          Expanded(
            child: AccountingGate(
              child: async.when(
                skipLoadingOnRefresh: true,
                loading: () => const DetailSkeleton(),
                error: (e, _) => ErrorState.forError(
                  e is AppError ? e : const AppError(type: AppErrorType.unknown, message: 'Something went wrong.'),
                  onRetry: _refresh,
                ),
                data: (d) => d == null
                    ? const EmptyState(
                        icon: PhosphorIconsRegular.receipt,
                        title: 'Not found',
                        body: 'This document may have been removed or you no longer have access to it.',
                      )
                    : _body(d),
              ),
            ),
          ),
          if (doc != null && ref.watch(accountingActiveProvider)) _actionBar(doc),
        ],
      ),
    );
  }

  Widget _body(AccDocument d) {
    return AppRefresh(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
        children: [
          _header(d),
          if (d.warnings.isNotEmpty || d.configDraftRows > 0) ...[
            SizedBox(height: 12.h),
            WarningsStrip(warnings: d.warnings, configDraftRows: d.configDraftRows),
          ],
          if (d.isCancelled && (d.cancelReason ?? '').isNotEmpty) ...[
            SizedBox(height: 12.h),
            AccInfoBanner('Cancelled: ${d.cancelReason}', icon: PhosphorIconsRegular.prohibit),
          ],
          if (d.isDraft) ...[
            SizedBox(height: 12.h),
            const AccInfoBanner('This is a draft. Items cannot be edited — to change them, void it and create a new one.'),
          ],
          SizedBox(height: 14.h),
          ClozrCard(
            radius: 18,
            padding: EdgeInsets.fromLTRB(18.w, 12.h, 18.w, 6.h),
            child: DetailUnderlineTabs(labels: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i)),
          ),
          SizedBox(height: 14.h),
          ...switch (_tab) {
            0 => [_details(d)],
            1 => [AccLinesCard(lines: d.lines), SizedBox(height: 14.h), AccTotalsCard(totals: AccTotalsCard.ofDocument(d), estimated: d.isDraft)],
            2 => [_tax(d)],
            3 => _journal(d),
            _ => [_links(d)],
          },
        ],
      ),
    );
  }

  Widget _header(AccDocument d) {
    final party = documentPartyName(ref, d);
    final open = d.isInward ? (d.payable ?? d.openBalance) : d.openBalance;
    final settled = toMoneyStr((moneyNum(d.isInward ? d.payable : d.grandTotal) - moneyNum(open)).clamp(0, double.infinity));
    return FinanceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconChip(icon: documentSourceIcon(d), size: 46, radius: 13, iconSize: 22),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8.w,
                      runSpacing: 4.h,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(d.displayNumber,
                            style: AppText.custom(size: 18, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                        DocStatusPill(d.status),
                        if (d.isIssued) PaymentStatePill(d.paymentState),
                      ],
                    ),
                    SizedBox(height: 3.h),
                    GestureDetector(
                      onTap: () => _openParty(d),
                      child: Text(party,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.blueBright)),
                    ),
                    SizedBox(height: 3.h),
                    Text('${label(docTypeLabels, d.docType)} · ${formatApiDay(d.documentDate)}',
                        style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                  ],
                ),
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 15)),
          Row(
            children: [
              _stat(d.isDraft ? 'EST. TOTAL' : 'TOTAL', formatMoneyStr(d.isInward ? (d.payable ?? d.grandTotal) : d.grandTotal),
                  AppColors.textPrimary),
              if (d.isIssued) ...[
                _stat(d.isInward ? 'PAID' : 'SETTLED', formatMoneyStr(settled), AppColors.success),
                _stat('OPEN', formatMoneyStr(open), moneyIsZero(open) ? AppColors.textMuted : AppColors.error),
              ] else
                _stat('TAX', formatMoneyStr(toMoneyStr(moneyNum(d.taxCgst) + moneyNum(d.taxSgst) + moneyNum(d.taxIgst) + moneyNum(d.taxCess))),
                    AppColors.textMuted),
            ],
          ),
          if (d.isInward && !moneyIsZero(d.tdsAmount)) ...[
            SizedBox(height: 8.h),
            Text('TDS ${formatMoneyStr(d.tdsAmount)} withheld from the vendor',
                style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.4)),
            SizedBox(height: 3.h),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: AppText.custom(size: 16, weight: FontWeight.w800, color: color)),
            ),
          ],
        ),
      );

  Widget _details(AccDocument d) {
    final state = ref.watch(gstStateNameProvider);
    final snap = d.partySnapshot;
    final rows = <(String, String)>[
      ('Invoice date', formatApiDay(d.documentDate)),
      if (d.supplyDate != null) ('Supply date', formatApiDay(d.supplyDate)),
      if (d.dueDate != null) ('Due date', formatApiDay(d.dueDate)),
      if (d.tosDate != null) ('Time of supply', formatApiDay(d.tosDate)),
      if (d.postingDate != null) ('Posted on', formatApiDay(d.postingDate)),
      if (d.isInward && d.vendorInvoiceNo != null) ('Vendor invoice no', d.vendorInvoiceNo!),
      ('Place of supply', d.placeOfSupply == null ? 'Automatic' : state(d.placeOfSupply)),
      if (d.supply != null) ('Supply', d.supply == 'INTER' ? 'Inter-state' : 'Intra-state'),
      if (d.transactionClass != null) ('Class', label(transactionClassLabels, d.transactionClass)),
      ('Prices', label(amountsAreLabels, d.amountsAre)),
      if (d.rcmApplies) ('Reverse charge', 'Applies'),
      if (d.sourceType != null) ('Raised from', label(sourceTypeLabels, d.sourceType)),
      if (snap['gstin'] is String && (snap['gstin'] as String).isNotEmpty) ('GSTIN', snap['gstin'] as String),
      if (d.reasonCode != null) ('Reason', label(const {'RETURN': 'Goods returned', 'VALUE_CORRECTION': 'Value correction'}, d.reasonCode)),
      if ((d.narration ?? '').isNotEmpty) ('Narration', d.narration!),
      if ((d.terms ?? '').isNotEmpty) ('Terms', d.terms!),
      if ((d.notes ?? '').isNotEmpty) ('Notes', d.notes!),
    ];
    return FinanceCard(
      title: 'Details',
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) MetaRow(label: rows[i].$1, value: rows[i].$2, last: i == rows.length - 1),
        ],
      ),
    );
  }

  Widget _tax(AccDocument d) {
    if (d.taxLines.isEmpty) {
      return FinanceCard(
        title: 'Tax',
        child: Padding(
          padding: EdgeInsets.only(top: 4.h),
          child: Text(d.isDraft ? 'Tax lines are written when the invoice is issued.' : 'No tax on this document.',
              style: AppText.body(color: AppColors.textMuted)),
        ),
      );
    }
    return FinanceCard(
      title: 'Tax',
      child: Column(
        children: [
          for (int i = 0; i < d.taxLines.length; i++)
            MetaRow(
              label: [
                d.taxLines[i].head,
                if (d.taxLines[i].ratePct != null) '${d.taxLines[i].ratePct}%',
                if (d.isInward && d.taxLines[i].itcStatus != null) 'ITC ${label(const {}, d.taxLines[i].itcStatus)}',
              ].join(' · '),
              value: formatMoneyStr(d.taxLines[i].amount),
              last: i == d.taxLines.length - 1,
            ),
        ],
      ),
    );
  }

  List<Widget> _journal(AccDocument d) {
    if (d.isDraft || d.isVoid) {
      return [
        const DetailTabEmpty(
          icon: PhosphorIconsRegular.bookOpenText,
          title: 'Nothing posted yet',
          body: 'The journal is written when the document is issued.',
        ),
      ];
    }
    if (!ref.watch(accPermProvider('acc_journal')).read) {
      return [
        const DetailTabEmpty(
          icon: PhosphorIconsRegular.lock,
          title: 'No journal access',
          body: 'Your role cannot see ledger entries.',
        ),
      ];
    }
    final async = ref.watch(documentJournalProvider(d.id));
    return async.when(
      loading: () => [const ListSkeleton(itemCount: 2, itemHeight: 120)],
      error: (e, _) => [ErrorState.forError(e is AppError ? e : const AppError(type: AppErrorType.unknown, message: 'Could not load.'),
          onRetry: () => ref.invalidate(documentJournalProvider(d.id)))],
      data: (entries) => entries.isEmpty
          ? [
              const DetailTabEmpty(
                icon: PhosphorIconsRegular.bookOpenText,
                title: 'No entries',
                body: 'No journal entries are linked to this document.',
              ),
            ]
          : [
              for (final e in entries) ...[JournalEntryCard(entry: e), SizedBox(height: 12.h)],
            ],
    );
  }

  Widget _links(AccDocument d) {
    final quotes = ref.watch(quotesProvider).valueOrNull ?? const [];
    final invoices = ref.watch(invoicesProvider).valueOrNull ?? const [];
    final quote = d.quotationId == null ? null : quotes.where((q) => q.uuid == d.quotationId).firstOrNull;
    final plan = d.paymentPlanId == null ? null : invoices.where((i) => i.uuid == d.paymentPlanId).firstOrNull;
    final links = <(IconData, String, String, VoidCallback?)>[
      if (d.referencesDocument != null)
        (PhosphorIconsRegular.receipt, 'Original invoice', 'Open',
            () => context.push('${Routes.accDocumentDetail}?id=${d.referencesDocument}')),
      if (d.quotationId != null)
        (PhosphorIconsRegular.fileText, 'Quote', quote?.id ?? 'Linked',
            quote == null ? null : () => context.push('${Routes.quoteDetail}?id=${quote.id}')),
      if (d.paymentPlanId != null)
        (PhosphorIconsRegular.calendarCheck, 'Payment plan', plan?.id ?? 'Linked',
            plan == null ? null : () => context.push('${Routes.invoiceDetail}?id=${plan.id}')),
      if (d.projectId != null)
        (PhosphorIconsRegular.kanban, 'Project', 'Open', () => context.push('${Routes.projectDetail}?id=${d.projectId}')),
      if (d.sourceType == 'TICKET' && d.sourceId != null)
        (PhosphorIconsRegular.ticket, 'Ticket', 'Open', () => context.push('${Routes.ticketDetail}?id=${d.sourceId}')),
    ];
    if (links.isEmpty) {
      return const DetailTabEmpty(
        icon: PhosphorIconsRegular.linkSimple,
        title: 'No links',
        body: 'This document was raised on its own.',
      );
    }
    return FinanceCard(
      title: 'Linked records',
      child: Column(
        children: [
          for (int i = 0; i < links.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: links[i].$4,
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 11.h),
                decoration: i == links.length - 1
                    ? null
                    : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
                child: Row(
                  children: [
                    Icon(links[i].$1, size: 18.sp, color: AppColors.navy),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Text(links[i].$2, style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textBody)),
                    ),
                    Text(links[i].$3,
                        style: AppText.custom(
                            size: 13, weight: FontWeight.w700, color: links[i].$4 == null ? AppColors.textMuted : AppColors.blueBright)),
                    if (links[i].$4 != null) ...[
                      SizedBox(width: 4.w),
                      Icon(PhosphorIconsBold.caretRight, size: 12.sp, color: AppColors.textPlaceholder),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openParty(AccDocument d) {
    if (d.isInward && d.vendorId != null) {
      context.push('${Routes.accVendorDetail}?id=${d.vendorId}');
    } else if (!d.isInward && d.customerId != null) {
      context.push('${Routes.customerDetail}?id=${d.customerId}');
    }
  }

  // ── Actions ──

  Widget _actionBar(AccDocument d) {
    final perm = ref.watch(accPermProvider('acc_document'));
    final settle = ref.watch(accPermProvider('acc_settlement'));
    Widget ghost(String label, IconData icon, VoidCallback? onTap) =>
        Expanded(child: PrimaryButton(label: label, icon: icon, ghost: true, height: 48, onTap: _busy ? null : onTap));
    Widget primary(String label, IconData icon, VoidCallback? onTap) =>
        Expanded(child: PrimaryButton(label: label, icon: icon, height: 48, onTap: _busy ? null : onTap));

    final buttons = <Widget>[
      if (d.isDraft) ...[
        if (perm.update) ghost('Edit', PhosphorIconsRegular.pencilSimple, () => _editDraft(d)),
        primary('Preview & issue', PhosphorIconsBold.sealCheck, () => _issue(d)),
      ] else if (d.isIssued && !d.isInward) ...[
        ghost('Share', PhosphorIconsRegular.shareNetwork, () => _share(d)),
        if (settle.create && !moneyIsZero(d.openBalance))
          primary('Record receipt', PhosphorIconsBold.plus, () => _receipt(d)),
      ] else if (d.isIssued && d.isInward) ...[
        ghost('Share', PhosphorIconsRegular.shareNetwork, () => _share(d)),
        if (settle.create && !moneyIsZero(d.openBalance ?? d.payable))
          primary('Pay vendor', PhosphorIconsBold.arrowUp, () => _payVendor(d)),
      ] else
        ghost('Share', PhosphorIconsRegular.shareNetwork, () => _share(d)),
    ];
    final spaced = <Widget>[
      for (int i = 0; i < buttons.length; i++) ...[if (i > 0) SizedBox(width: 10.w), buttons[i]],
    ];
    return StickyActionBar(children: spaced);
  }

  Future<void> _menu(AccDocument d) async {
    final perm = ref.watch(accPermProvider('acc_document'));
    final active = ref.read(accountingActiveProvider);
    await showActionMenu(
      context,
      title: d.displayNumber,
      actions: [
        MenuAction(icon: PhosphorIconsRegular.shareNetwork, label: 'Share or print', onTap: () => _share(d)),
        if (active && d.isDraft && perm.update)
          MenuAction(icon: PhosphorIconsRegular.pencilSimple, label: 'Edit draft', onTap: () => _editDraft(d)),
        if (active && d.isDraft && perm.update)
          MenuAction(icon: PhosphorIconsRegular.trash, label: 'Void draft', destructive: true, onTap: () => _void(d)),
        if (active && d.canCreditNote && perm.create)
          MenuAction(
              icon: PhosphorIconsRegular.arrowUUpLeft,
              label: 'Credit note',
              sublabel: 'Goods returned or a value correction',
              onTap: () => _creditNote(d)),
        if (active && d.isIssued && perm.approve)
          MenuAction(icon: PhosphorIconsRegular.prohibit, label: 'Cancel', destructive: true, onTap: () => _cancel(d)),
      ],
    );
  }

  void _share(AccDocument d) => context.push('${Routes.accDocumentPrint}?id=${d.id}');

  Future<void> _editDraft(AccDocument d) async {
    final saved = await showEditDraftSheet(context, d);
    if (saved != null) ref.invalidate(accDocumentProvider(d.id));
  }

  Future<void> _issue(AccDocument d) async {
    final result = await showIssueSheet(context, d);
    if (!mounted) return;
    if (result == IssueFollowUp.editDraft) {
      await _editDraft(d);
    } else if (result == IssueFollowUp.voidDraft) {
      await _void(d);
    } else if (result is AccDocument) {
      ref.invalidate(accDocumentProvider(d.id));
    }
  }

  Future<void> _void(AccDocument d) async {
    final ok = await confirmAcc(
      context,
      title: 'Void this draft?',
      body: 'It will be kept as a void draft and can no longer be issued.',
      confirmLabel: 'Void draft',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(accountingRepositoryProvider).voidDraft(d.id);
      invalidateAccountingReads(ref.invalidate);
      if (mounted) ref.read(toastProvider.notifier).show('Draft voided');
    } on AppError catch (e) {
      if (mounted) ref.read(toastProvider.notifier).showError(conflictCopy(e).body);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _creditNote(AccDocument d) async {
    final note = await showCreditNoteSheet(context, d);
    if (note != null && mounted) context.push('${Routes.accDocumentDetail}?id=${note.id}');
  }

  Future<void> _cancel(AccDocument d) async {
    final doc = await showCancelDocumentSheet(context, d);
    if (doc != null) ref.invalidate(accDocumentProvider(d.id));
  }

  Future<void> _payVendor(AccDocument d) async {
    final ok = await showVendorPaymentSheet(context, vendorId: d.vendorId, bill: d);
    if (ok == true) ref.invalidate(accDocumentProvider(d.id));
  }

  Future<void> _receipt(AccDocument d) async {
    final ok = await showRecordReceiptSheet(context, invoice: d);
    if (ok == true) ref.invalidate(accDocumentProvider(d.id));
  }
}
