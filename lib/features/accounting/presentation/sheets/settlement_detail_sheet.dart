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
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../crm/application/providers/crm_party_providers.dart';
import '../../../crm/presentation/components/finance_widgets.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/accounting_invalidation.dart';
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/documents_providers.dart';
import '../../application/providers/reports_providers.dart';
import '../../application/providers/settlement_providers.dart';
import '../../domain/entities/acc_settlement.dart';
import '../components/acc_widgets.dart';
import '../components/journal_entry_card.dart';
import '../config/accounting_copy.dart';
import 'acc_sheet_scaffold.dart';

/// Detail of one receipt — the full read with its allocations — and the
/// Reverse action.
Future<void> showReceiptDetailSheet(BuildContext context, AccReceipt row) =>
    showClozrSheet<void>(context: context, builder: (_) => _ReceiptDetail(row: row));

/// Detail of one vendor payment, with Reverse.
Future<void> showVendorPaymentDetailSheet(BuildContext context, AccVendorPayment row) =>
    showClozrSheet<void>(context: context, builder: (_) => _VendorPaymentDetail(row: row));

class _ReceiptDetail extends ConsumerWidget {
  const _ReceiptDetail({required this.row});
  final AccReceipt row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(receiptDetailProvider(row.id)).valueOrNull ?? row;
    final party = ref.watch(crmPartyLookupProvider)(custId: r.customerId);
    final canReverse = r.isPosted && ref.watch(accPermProvider('acc_settlement')).update;
    return _DetailFrame(
      title: 'Receipt',
      status: r.status,
      rows: [
        ('Customer', party?.name ?? 'Customer'),
        ('Date', formatApiDay(r.date)),
        ('Amount', formatMoneyStr(r.amount)),
        if (!moneyIsZero(r.tdsDeducted)) ('TDS deducted', formatMoneyStr(r.tdsDeducted)),
        if (!moneyIsZero(r.unallocated)) ('Kept as credit', formatMoneyStr(r.unallocated)),
        ('Into', label(sourceAccountLabels, r.sourceAccountKind)),
        if (r.method != null) ('Method', label(paymentMethods, r.method)),
        if ((r.reference ?? '').isNotEmpty) ('Reference', r.reference!),
      ],
      allocations: [for (final a in r.allocations) (a.documentId, a.amountApplied)],
      journalEntryId: r.journalEntryId,
      action: canReverse
          ? PrimaryButton(
              label: 'Reverse receipt',
              icon: PhosphorIconsRegular.arrowCounterClockwise,
              ghost: true,
              height: 48,
              onTap: () async {
                final done = await showClozrSheet<bool>(context: context, builder: (_) => _ReverseReceiptSheet(receipt: r));
                if (done == true && context.mounted) Navigator.of(context).pop();
              },
            )
          : null,
    );
  }
}

class _VendorPaymentDetail extends ConsumerStatefulWidget {
  const _VendorPaymentDetail({required this.row});
  final AccVendorPayment row;

  @override
  ConsumerState<_VendorPaymentDetail> createState() => _VendorPaymentDetailState();
}

class _VendorPaymentDetailState extends ConsumerState<_VendorPaymentDetail> {
  String _eventId = newEventId();
  bool _busy = false;

  Future<void> _reverse(AccVendorPayment p) async {
    final ok = await confirmAcc(
      context,
      title: 'Reverse this payment?',
      body: 'The bills it paid become open again. This cannot be undone.',
      confirmLabel: 'Reverse',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final out = await ref.read(accountingRepositoryProvider).reverseVendorPayment(p.id, eventId: _eventId);
      invalidateAccountingReads(ref.invalidate);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(out.skipped ? 'Already reversed' : 'Payment reversed');
      Navigator.of(context).pop();
    } on AppError catch (e) {
      _eventId = nextEventId(_eventId, e);
      if (!mounted) return;
      setState(() => _busy = false);
      ref.read(toastProvider.notifier).showError(conflictCopy(e).body);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(vendorPaymentDetailProvider(widget.row.id)).valueOrNull ?? widget.row;
    final vendor = ref.watch(vendorNameProvider)(p.vendorId);
    final canReverse = p.isPosted && ref.watch(accPermProvider('acc_settlement')).update;
    return _DetailFrame(
      title: 'Vendor payment',
      status: p.status,
      rows: [
        ('Vendor', vendor ?? 'Vendor'),
        ('Date', formatApiDay(p.date)),
        ('Amount', formatMoneyStr(p.amount)),
        if (!moneyIsZero(p.tdsNow)) ('TDS deducted', formatMoneyStr(p.tdsNow)),
        ('From', label(sourceAccountLabels, p.sourceAccountKind)),
        if ((p.reference ?? '').isNotEmpty) ('Reference', p.reference!),
      ],
      allocations: [for (final a in p.allocations) (a.documentId, a.amountApplied)],
      journalEntryId: p.journalEntryId,
      action: canReverse
          ? PrimaryButton(
              label: _busy ? 'Reversing…' : 'Reverse payment',
              icon: PhosphorIconsRegular.arrowCounterClockwise,
              ghost: true,
              height: 48,
              onTap: _busy ? null : () => _reverse(p),
            )
          : null,
    );
  }
}

/// Shared body of the two detail sheets.
class _DetailFrame extends ConsumerWidget {
  const _DetailFrame({
    required this.title,
    required this.status,
    required this.rows,
    required this.allocations,
    this.journalEntryId,
    this.action,
  });

  final String title;
  final String status;
  final List<(String, String)> rows;
  final List<(String, String)> allocations;
  final String? journalEntryId;
  final Widget? action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canJournal = ref.watch(accPermProvider('acc_journal')).read;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: title),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 24.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AccPill(StatusMeta$.accPosting, status),
                SizedBox(height: 6.h),
                for (int i = 0; i < rows.length; i++) MetaRow(label: rows[i].$1, value: rows[i].$2, last: i == rows.length - 1),
                if (allocations.isNotEmpty) ...[
                  SizedBox(height: 16.h),
                  Text('Applied to', style: AppText.custom(size: 13, weight: FontWeight.w800, color: AppColors.textPrimary)),
                  SizedBox(height: 4.h),
                  for (final a in allocations) _AllocationRow(documentId: a.$1, amount: a.$2),
                ],
                if (journalEntryId != null && canJournal) ...[
                  SizedBox(height: 14.h),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showClozrSheet<void>(
                      context: context,
                      builder: (_) => _JournalSheet(entryId: journalEntryId!),
                    ),
                    child: Row(
                      children: [
                        Icon(PhosphorIconsRegular.bookOpenText, size: 16.sp, color: AppColors.blueBright),
                        SizedBox(width: 7.w),
                        Text('View journal entry',
                            style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.blueBright)),
                      ],
                    ),
                  ),
                ],
                if (action != null) ...[SizedBox(height: 18.h), action!],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One allocation, with the document's number once it has loaded.
class _AllocationRow extends ConsumerWidget {
  const _AllocationRow({required this.documentId, required this.amount});
  final String documentId;
  final String amount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(accDocumentProvider(documentId)).valueOrNull;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final router = GoRouter.of(context);
        Navigator.of(context).pop();
        router.push('${Routes.accDocumentDetail}?id=$documentId');
      },
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 9.h),
        child: Row(
          children: [
            Expanded(
              child: Text(doc?.displayNumber ?? 'Document',
                  style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.blueBright)),
            ),
            Text(formatMoneyStr(amount), style: AppText.custom(size: 13, weight: FontWeight.w800, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _JournalSheet extends ConsumerWidget {
  const _JournalSheet({required this.entryId});
  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(journalEntryProvider(entryId));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetHeader(title: 'Journal entry'),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 24.h),
            child: async.when(
              loading: () => SizedBox(
                height: 120.h,
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.navy)),
              ),
              error: (e, _) => ConflictBanner(
                error: e is AppError ? e : const AppError(type: AppErrorType.unknown, message: 'Could not load.'),
              ),
              data: (entry) => entry == null
                  ? Text('No entry found.', style: AppText.body(color: AppColors.textMuted))
                  : JournalEntryCard(entry: entry),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReverseReceiptSheet extends ConsumerStatefulWidget {
  const _ReverseReceiptSheet({required this.receipt});
  final AccReceipt receipt;

  @override
  ConsumerState<_ReverseReceiptSheet> createState() => _ReverseReceiptSheetState();
}

class _ReverseReceiptSheetState extends ConsumerState<_ReverseReceiptSheet> {
  String _eventId = newEventId();
  final _reason = TextEditingController();
  bool _busy = false;
  AppError? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason.text.trim().isEmpty) {
      ref.read(toastProvider.notifier).showError('Say why it is being reversed');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final out = await ref
          .read(accountingRepositoryProvider)
          .reverseReceipt(widget.receipt.id, reason: _reason.text.trim(), eventId: _eventId);
      invalidateAccountingReads(ref.invalidate);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(out.skipped ? 'Already reversed' : 'Receipt reversed');
      Navigator.of(context).pop(true);
    } on AppError catch (e) {
      _eventId = nextEventId(_eventId, e);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AccSheetScaffold(
        title: 'Reverse receipt',
        submitLabel: 'Reverse receipt',
        submitIcon: PhosphorIconsBold.arrowCounterClockwise,
        busyLabel: 'Reversing…',
        busy: _busy,
        error: _error,
        onSubmit: _submit,
        children: [
          AccInput(
            label: 'Reason',
            required: true,
            controller: _reason,
            hint: 'e.g. Cheque bounced',
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
          const AccInfoBanner('The invoices it paid become open again. This cannot be undone.'),
        ],
      );
}
