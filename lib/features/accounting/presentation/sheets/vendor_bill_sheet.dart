import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/accounting_invalidation.dart';
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/settlement_providers.dart';
import '../../domain/entities/acc_masters.dart';
import '../components/acc_pickers.dart';
import '../components/acc_widgets.dart';
import '../components/purchase_lines_editor.dart';
import '../config/accounting_copy.dart';
import 'acc_sheet_scaffold.dart';
import 'record_expense_sheet.dart';

/// "Vendor bill" (plan §4.9, form D1) — a supplier's bill to pay later. Posts
/// immediately (§12.9), so a confirm step shows the estimated amount first;
/// on success the new bill opens.
Future<bool?> showVendorBillSheet(BuildContext context, {String? vendorId}) =>
    showClozrSheet<bool>(context: context, builder: (_) => _VendorBillSheet(vendorId: vendorId));

class _VendorBillSheet extends ConsumerStatefulWidget {
  const _VendorBillSheet({this.vendorId});
  final String? vendorId;

  @override
  ConsumerState<_VendorBillSheet> createState() => _VendorBillSheetState();
}

class _VendorBillSheetState extends ConsumerState<_VendorBillSheet> {
  String _eventId = newEventId();
  Vendor? _vendor;
  ExpenseCategory? _category;
  bool _trading = false;
  final List<PurchaseLineDraft> _lines = [PurchaseLineDraft()];
  DateTime _date = DateTime.now();
  DateTime? _supplyDate;
  DateTime? _invoiceDate;
  String? _pos;
  final _invoiceNo = TextEditingController();
  final _rcmReason = TextEditingController();
  bool _personal = false;
  bool? _rcm;
  String? _tdsOverride;
  bool _busy = false;
  AppError? _error;

  @override
  void initState() {
    super.initState();
    if (widget.vendorId != null) {
      ref.read(vendorsProvider.future).then((vs) {
        final v = vs.where((v) => v.id == widget.vendorId).firstOrNull;
        if (mounted && v != null) setState(() => _vendor = v);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    _invoiceNo.dispose();
    _rcmReason.dispose();
    super.dispose();
  }

  void _fail(String m) => ref.read(toastProvider.notifier).showError(m);

  Future<void> _submit() async {
    if (_busy) return;
    if (_vendor == null) return _fail('Pick the vendor');
    if (!_trading && _category == null) return _fail('Pick what the bill is for');
    if (!_lines.every((l) => l.complete)) return _fail('Every line needs a description and an amount');
    if (!_lines.every((l) => l.hsnValid)) return _fail('HSN/SAC must be 4 to 8 digits');
    final ok = await confirmAcc(
      context,
      title: 'Post this bill?',
      body: 'About ${formatMoneyStr(purchaseLinesHint(_lines))} (estimated — tax and TDS are worked out by the server). '
          'The bill posts to the ledger now and cannot be edited afterwards.',
      confirmLabel: 'Post bill',
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final out = await ref.read(accountingRepositoryProvider).recordVendorBill({
        'vendor': _vendor!.id,
        'target': _trading ? 'PURCHASES' : 'EXPENSE:${_category!.key}',
        'lines': [for (final l in _lines) l.toJson()],
        'document_date': isoDay(_date),
        'supply_date': _supplyDate == null ? null : isoDay(_supplyDate!),
        'vendor_invoice_no': _invoiceNo.text.trim(),
        'vendor_invoice_date': _invoiceDate == null ? null : isoDay(_invoiceDate!),
        'place_of_supply_state_code': _pos,
        if (_personal) 'personal_use_flag': true,
        'tds_nature_override': _tdsOverride,
        if (_rcm != null) 'rcm_override': {'applies': _rcm, 'reason': _rcmReason.text.trim()},
        'event_id': _eventId,
      });
      invalidateAccountingReads(ref.invalidate);
      if (!mounted) return;
      final toast = ref.read(toastProvider.notifier);
      final router = GoRouter.of(context);
      Navigator.of(context).pop(true);
      if (out.skipped) {
        toast.show(out.skipReason ?? 'Already recorded — nothing new was posted');
      } else {
        toast.show('Bill posted${out.value?.number == null ? '' : ' · ${out.value!.number}'}');
        if (out.value != null) router.push('${Routes.accDocumentDetail}?id=${out.value!.id}');
      }
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
  Widget build(BuildContext context) {
    final stateName = ref.watch(gstStateNameProvider);
    return AccSheetScaffold(
      title: 'Vendor bill',
      submitLabel: 'Post bill',
      busy: _busy,
      error: _error,
      submitEnabled: ref.watch(accPermProvider('acc_purchase')).create,
      onSubmit: _submit,
      children: [
        VendorPickerField(vendor: _vendor, onChanged: (v) => setState(() => _vendor = v)),
        AccChoiceChips(
          label: 'Booked to',
          options: const {'EXPENSE': 'An expense', 'PURCHASES': 'Goods for resale'},
          selected: _trading ? 'PURCHASES' : 'EXPENSE',
          onSelected: (v) => setState(() => _trading = v == 'PURCHASES'),
        ),
        if (!_trading)
          AccPickerBox(
            label: 'Category',
            required: true,
            value: _category?.label,
            hint: 'What is it for?',
            footnote: _category == null ? null : itcHintFor(_category!),
            onTap: () async {
              final c = await pickExpenseCategory(context, selected: _category?.key);
              if (c != null) setState(() => _category = c);
            },
          ),
        PurchaseLinesEditor(lines: _lines, onChanged: () => setState(() {})),
        AccDateBox(label: 'Bill date', required: true, value: _date, showIstHint: true,
            onChanged: (d) => setState(() => _date = d ?? _date)),
        AccInput(label: 'Vendor invoice no', controller: _invoiceNo, hint: 'As printed on their bill'),
        AccDateBox(label: 'Vendor invoice date', value: _invoiceDate, clearable: true,
            onChanged: (d) => setState(() => _invoiceDate = d)),
        AccDisclosure(
          title: 'More options',
          children: [
            AccDateBox(label: 'Supply date', value: _supplyDate, clearable: true,
                onChanged: (d) => setState(() => _supplyDate = d)),
            AccPickerBox(
              label: 'Place of supply',
              value: _pos == null ? null : stateName(_pos),
              hint: 'Automatic',
              icon: PhosphorIconsRegular.mapPin,
              onTap: () async {
                final code = await pickGstState(context, ref, selected: _pos);
                if (code != null) setState(() => _pos = code);
              },
            ),
            AccCheckRow(
              label: 'Personal use',
              value: _personal,
              hint: 'Not a business expense — no input credit is claimed.',
              onChanged: (v) => setState(() => _personal = v),
            ),
            AccPickerBox(
              label: 'TDS nature',
              value: _tdsOverride == null ? null : tdsNatures[_tdsOverride],
              hint: 'Category default',
              onTap: () async {
                final n = await pickTdsNature(context, selected: _tdsOverride);
                if (n != null) setState(() => _tdsOverride = n);
              },
            ),
            AccChoiceChips(
              label: 'Reverse charge',
              options: const {'auto': 'Automatic', 'yes': 'Applies', 'no': 'Does not apply'},
              selected: _rcm == null ? 'auto' : (_rcm! ? 'yes' : 'no'),
              onSelected: (v) => setState(() => _rcm = v == 'auto' ? null : v == 'yes'),
            ),
            if (_rcm != null) AccInput(label: 'Reason', controller: _rcmReason, hint: 'Why the default is overridden'),
          ],
        ),
      ],
    );
  }
}
