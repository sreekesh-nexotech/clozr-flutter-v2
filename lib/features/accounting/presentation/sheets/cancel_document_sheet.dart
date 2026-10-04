import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/accounting_invalidation.dart';
import '../../application/providers/accounting_providers.dart';
import '../../domain/entities/acc_document.dart';
import '../components/acc_widgets.dart';
import 'acc_sheet_scaffold.dart';

/// Cancel an issued document (plan §4.3) — reverses its tax and its
/// receivable (or payable). Refused once money or a note touches it, in which
/// case the refusal says what to do instead.
Future<AccDocument?> showCancelDocumentSheet(BuildContext context, AccDocument doc) =>
    showClozrSheet<AccDocument>(context: context, builder: (_) => _CancelSheet(doc: doc));

class _CancelSheet extends ConsumerStatefulWidget {
  const _CancelSheet({required this.doc});
  final AccDocument doc;

  @override
  ConsumerState<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends ConsumerState<_CancelSheet> {
  final _reason = TextEditingController();
  bool _busy = false;
  AppError? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      ref.read(toastProvider.notifier).showError('Say why it is being cancelled');
      return;
    }
    final ok = await confirmAcc(
      context,
      title: 'Cancel ${widget.doc.displayNumber}?',
      body: 'This reverses its tax and what is owed. It cannot be undone.',
      confirmLabel: 'Cancel document',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final doc = await ref.read(accountingRepositoryProvider).cancel(widget.doc.id, reason);
      invalidateAccountingReads(ref.invalidate);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('${widget.doc.displayNumber} cancelled');
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
    return AccSheetScaffold(
      title: 'Cancel ${widget.doc.displayNumber}',
      submitLabel: 'Cancel document',
      submitIcon: PhosphorIconsBold.prohibit,
      busyLabel: 'Cancelling…',
      busy: _busy,
      error: _error,
      onSubmit: _cancel,
      children: [
        AccInput(
          label: 'Reason',
          required: true,
          controller: _reason,
          hint: 'e.g. Raised against the wrong customer',
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
        ),
        const AccInfoBanner(
          'Once money has been received, or a GST return filed, an invoice cannot be cancelled — raise a credit note instead.',
        ),
      ],
    );
  }
}
