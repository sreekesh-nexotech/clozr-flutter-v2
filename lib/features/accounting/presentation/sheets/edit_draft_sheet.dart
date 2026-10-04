import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/network/app_error.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/accounting_invalidation.dart';
import '../../application/providers/accounting_providers.dart';
import '../../domain/entities/acc_document.dart';
import '../components/acc_pickers.dart';
import '../components/acc_widgets.dart';
import '../config/accounting_copy.dart';
import 'acc_sheet_scaffold.dart';

/// "Edit draft" (plan §4.3) — the eight header fields the API lets a draft
/// change. Lines are not among them (handover §12.8), and neither is the
/// customer; both need the draft voided and raised again.
Future<AccDocument?> showEditDraftSheet(BuildContext context, AccDocument doc) =>
    showClozrSheet<AccDocument>(context: context, builder: (_) => _EditDraftSheet(doc: doc));

class _EditDraftSheet extends ConsumerStatefulWidget {
  const _EditDraftSheet({required this.doc});
  final AccDocument doc;

  @override
  ConsumerState<_EditDraftSheet> createState() => _EditDraftSheetState();
}

class _EditDraftSheetState extends ConsumerState<_EditDraftSheet> {
  late DateTime? _docDate = DateTime.tryParse(widget.doc.documentDate ?? '');
  late DateTime? _supplyDate = DateTime.tryParse(widget.doc.supplyDate ?? '');
  late DateTime? _dueDate = DateTime.tryParse(widget.doc.dueDate ?? '');
  late String? _pos = widget.doc.placeOfSupply;
  late String? _amountsAre = widget.doc.amountsAre;
  late final _narration = TextEditingController(text: widget.doc.narration ?? '');
  late final _terms = TextEditingController(text: widget.doc.terms ?? '');
  late final _notes = TextEditingController(text: widget.doc.notes ?? '');
  bool _busy = false;
  AppError? _error;

  @override
  void dispose() {
    _narration.dispose();
    _terms.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// The Indian fiscal year a date falls in (April–March).
  static int _fy(DateTime d) => d.month >= 4 ? d.year : d.year - 1;

  Future<void> _save() async {
    final original = DateTime.tryParse(widget.doc.documentDate ?? '');
    // The number is taken from the series of the draft's *creation* date, so a
    // draft moved across 1 April would issue with last year's number (§12.23).
    if (original != null && _docDate != null && _fy(original) != _fy(_docDate!)) {
      ref.read(toastProvider.notifier).showError(
          'Moving the date into another financial year needs a new draft — void this one and create it again.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await ref.read(accountingRepositoryProvider).patchDraft(widget.doc.id, {
        if (_docDate != null) 'document_date': isoDay(_docDate!),
        'supply_date': _supplyDate == null ? null : isoDay(_supplyDate!),
        'due_date': _dueDate == null ? null : isoDay(_dueDate!),
        'place_of_supply_state_code': _pos,
        if (_amountsAre != null) 'amounts_are': _amountsAre,
        'narration': _narration.text.trim(),
        'terms': _terms.text.trim(),
        'notes': _notes.text.trim(),
      });
      invalidateAccountingReads(ref.invalidate);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Draft updated');
      Navigator.of(context).pop(saved);
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
    final stateName = ref.watch(gstStateNameProvider);
    return AccSheetScaffold(
      title: 'Edit draft',
      submitLabel: 'Save draft',
      busyLabel: 'Saving…',
      posts: false,
      busy: _busy,
      error: _error,
      onSubmit: _save,
      children: [
        AccDateBox(label: 'Invoice date', required: true, value: _docDate, showIstHint: true,
            onChanged: (d) => setState(() => _docDate = d)),
        AccDateBox(label: 'Supply date', value: _supplyDate, clearable: true,
            onChanged: (d) => setState(() => _supplyDate = d)),
        AccDateBox(label: 'Due date', value: _dueDate, clearable: true,
            onChanged: (d) => setState(() => _dueDate = d)),
        AccPickerBox(
          label: 'Place of supply',
          value: _pos == null ? null : stateName(_pos),
          hint: 'From the customer (automatic)',
          icon: PhosphorIconsRegular.mapPin,
          onTap: () async {
            final code = await pickGstState(context, ref, selected: _pos);
            if (code != null) setState(() => _pos = code);
          },
        ),
        AccChoiceChips(
          label: 'Prices are',
          options: amountsAreLabels,
          selected: _amountsAre,
          onSelected: (v) => setState(() => _amountsAre = v),
        ),
        AccInput(label: 'Narration', controller: _narration, hint: 'Shown on the invoice', maxLines: 3),
        AccInput(label: 'Terms', controller: _terms, hint: 'Payment terms', maxLines: 3),
        AccInput(label: 'Notes', controller: _notes, hint: 'Internal note', maxLines: 3),
        const AccInfoBanner('Items and the customer cannot be changed on a draft. To change them, void it and create a new one.'),
      ],
    );
  }
}
