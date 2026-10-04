import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/network/app_error.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/accounting_invalidation.dart';
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/documents_providers.dart';
import '../../domain/entities/acc_document.dart';
import '../components/acc_widgets.dart';
import 'acc_sheet_scaffold.dart';

/// "Issue invoice" for one payment-plan instalment (plan §5.2): creates the
/// draft from the record, lines pro-rated from the plan's quote.
///
/// Looks first. `from-payment-record/` makes a new draft on every call and
/// takes no idempotency key, and a plan on "invoice on due date" has usually
/// pre-created one already (handover §12.1) — so an existing draft is opened
/// rather than a second one raised. Resolves to the draft to open.
Future<AccDocument?> showInvoiceFromRecordSheet(
  BuildContext context, {
  required String recordId,
  String? customerId,
  DateTime? dueDate,
}) =>
    showClozrSheet<AccDocument>(
      context: context,
      builder: (_) => _InvoiceFromRecordSheet(recordId: recordId, customerId: customerId, dueDate: dueDate),
    );

class _InvoiceFromRecordSheet extends ConsumerStatefulWidget {
  const _InvoiceFromRecordSheet({required this.recordId, this.customerId, this.dueDate});

  final String recordId;
  final String? customerId;
  final DateTime? dueDate;

  @override
  ConsumerState<_InvoiceFromRecordSheet> createState() => _InvoiceFromRecordSheetState();
}

class _InvoiceFromRecordSheetState extends ConsumerState<_InvoiceFromRecordSheet> {
  late DateTime _date = DateTime.now();
  DateTime? _supplyDate;
  bool _busy = false;
  AppError? _error;

  Future<void> _create() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(accountingRepositoryProvider);
    try {
      // Re-checked at submit, not just at open: the daily sweep may have
      // created one in between.
      final existing = await ref.read(
          draftsForPaymentRecordProvider((recordId: widget.recordId, customerId: widget.customerId)).future);
      if (existing.isNotEmpty) {
        if (!mounted) return;
        ref.read(toastProvider.notifier).show('A draft already exists — opening it');
        Navigator.of(context).pop(existing.first);
        return;
      }
      final doc = await repo.invoiceFromPaymentRecord(
        widget.recordId,
        documentDate: isoDay(_date),
        supplyDate: _supplyDate == null ? null : isoDay(_supplyDate!),
      );
      invalidateAccountingReads(ref.invalidate);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Draft invoice created');
      Navigator.of(context).pop(doc);
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final drafts = ref.watch(draftsForPaymentRecordProvider((recordId: widget.recordId, customerId: widget.customerId)));
    final existing = drafts.valueOrNull ?? const <AccDocument>[];
    return AccSheetScaffold(
      title: 'Issue invoice',
      submitLabel: existing.isNotEmpty ? 'Open draft' : 'Create draft',
      submitIcon: existing.isNotEmpty ? PhosphorIconsBold.arrowRight : PhosphorIconsBold.plus,
      busyLabel: 'Creating…',
      busy: _busy || drafts.isLoading,
      error: _error,
      onSubmit: existing.isNotEmpty ? () => Navigator.of(context).pop(existing.first) : _create,
      children: [
        if (existing.isNotEmpty)
          AccInfoBanner(
            'This instalment already has a draft invoice${existing.first.documentDate == null ? '' : ' dated ${formatApiDay(existing.first.documentDate)}'}. Open it to preview and issue.',
          )
        else ...[
          AccDateBox(label: 'Invoice date', required: true, value: _date, showIstHint: true,
              onChanged: (d) => setState(() => _date = d ?? _date)),
          AccDateBox(label: 'Supply date', value: _supplyDate, clearable: true,
              onChanged: (d) => setState(() => _supplyDate = d)),
          const AccInfoBanner(
            'A draft is created from this instalment with the quote\'s items. Preview the tax and issue it from the draft.',
          ),
        ],
      ],
    );
  }
}
