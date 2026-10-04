import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
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
import 'vendor_form_sheet.dart';

/// "Record expense" (plan §4.9, form D3) — a vendor bill and its payment in
/// one call. Purchases post immediately (no draft, no preview, §12.9), so the
/// submit goes through a confirm step with the amount labelled estimated.
Future<bool?> showRecordExpenseSheet(BuildContext context, {String? vendorId}) =>
    showClozrSheet<bool>(context: context, builder: (_) => _RecordExpenseSheet(vendorId: vendorId));

/// The ITC note shown under a chosen expense category.
String? itcHintFor(ExpenseCategory c) => switch (c.itc) {
      ItcHint.blocked => 'No input credit on this category.',
      ItcHint.notApplicable => 'No GST applies to this category.',
      ItcHint.eligible => null,
    };

class _RecordExpenseSheet extends ConsumerStatefulWidget {
  const _RecordExpenseSheet({this.vendorId});
  final String? vendorId;

  @override
  ConsumerState<_RecordExpenseSheet> createState() => _RecordExpenseSheetState();
}

class _RecordExpenseSheetState extends ConsumerState<_RecordExpenseSheet> {
  String _eventId = newEventId();
  Vendor? _vendor;
  ExpenseCategory? _category;
  final List<PurchaseLineDraft> _lines = [PurchaseLineDraft()];
  DateTime _date = DateTime.now();
  String _source = 'BANK';
  BankAccount? _bank;
  final _owner = TextEditingController();
  final _invoiceNo = TextEditingController();
  bool _personal = false;
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
    ref.read(bankAccountsProvider.future).then((accounts) {
      if (!mounted || _bank != null) return;
      final banks = [for (final a in accounts) if (a.kind == 'BANK') a];
      final def = banks.where((a) => a.isDefault).firstOrNull ?? (banks.length == 1 ? banks.first : null);
      if (def != null) setState(() => _bank = def);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    _owner.dispose();
    _invoiceNo.dispose();
    super.dispose();
  }

  void _fail(String m) => ref.read(toastProvider.notifier).showError(m);

  Future<void> _submit() async {
    if (_busy) return;
    if (_vendor == null) return _fail('Pick the vendor');
    if (_category == null) return _fail('Pick what the expense was for');
    if (!_lines.every((l) => l.complete)) return _fail('Every line needs a description and an amount');
    if (!_lines.every((l) => l.hsnValid)) return _fail('HSN/SAC must be 4 to 8 digits');
    if (_source == 'BANK' && _bank == null) return _fail('Pick the bank account it was paid from');
    if (_source == 'OWNER' && _owner.text.trim().isEmpty) return _fail('Say who paid from their own funds');
    final ok = await confirmAcc(
      context,
      title: 'Post this expense?',
      body: 'About ${formatMoneyStr(purchaseLinesHint(_lines))} (estimated — tax and TDS are worked out by the server). '
          'This posts the bill and the payment to the ledger now. It cannot be edited afterwards.',
      confirmLabel: 'Post expense',
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final out = await ref.read(accountingRepositoryProvider).recordExpense({
        'vendor': _vendor!.id,
        'target': 'EXPENSE:${_category!.key}',
        'lines': [for (final l in _lines) l.toJson()],
        'document_date': isoDay(_date),
        'source_account_kind': _source,
        'bank_account': _source == 'BANK' ? _bank?.id : null,
        'owner': _source == 'OWNER' ? _owner.text.trim() : null,
        'vendor_invoice_no': _invoiceNo.text.trim(),
        if (_personal) 'personal_use_flag': true,
        'tds_nature_override': _tdsOverride,
        'event_id': _eventId,
      });
      invalidateAccountingReads(ref.invalidate);
      if (!mounted) return;
      final toast = ref.read(toastProvider.notifier);
      if (out.skipped) {
        toast.show(out.skipReason ?? 'Already recorded — nothing new was posted');
      } else {
        toast.show('Expense posted${out.value?.number == null ? '' : ' · ${out.value!.number}'} · payment posted');
      }
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
  Widget build(BuildContext context) {
    return AccSheetScaffold(
      title: 'Record expense',
      submitLabel: 'Post expense',
      busy: _busy,
      error: _error,
      submitEnabled: ref.watch(accPermProvider('acc_purchase')).create,
      onSubmit: _submit,
      children: [
        VendorPickerField(
          vendor: _vendor,
          onChanged: (v) => setState(() => _vendor = v),
        ),
        AccPickerBox(
          label: 'Category',
          required: true,
          value: _category?.label,
          hint: 'What was it for?',
          footnote: _category == null ? null : itcHintFor(_category!),
          onTap: () async {
            final c = await pickExpenseCategory(context, selected: _category?.key);
            if (c != null) setState(() => _category = c);
          },
        ),
        PurchaseLinesEditor(lines: _lines, onChanged: () => setState(() {})),
        AccDateBox(label: 'Date', required: true, value: _date, showIstHint: true,
            onChanged: (d) => setState(() => _date = d ?? _date)),
        AccChoiceChips(
          label: 'Paid from',
          required: true,
          options: const {'BANK': 'Bank', 'CASH': 'Cash', 'OWNER': "Owner's funds"},
          selected: _source,
          onSelected: (v) => setState(() => _source = v),
        ),
        if (_source == 'BANK')
          AccPickerBox(
            label: 'Bank account',
            required: true,
            value: _bank?.label,
            hint: 'Select account…',
            onTap: () async {
              final b = await pickBankAccount(context, ref, selectedId: _bank?.id);
              if (b != null) setState(() => _bank = b);
            },
          ),
        if (_source == 'OWNER') AccInput(label: 'Paid by', required: true, controller: _owner, hint: 'Owner or partner name'),
        AccInput(label: 'Vendor invoice no', controller: _invoiceNo, hint: 'Optional'),
        AccDisclosure(
          title: 'More options',
          children: [
            AccCheckRow(
              label: 'Personal use',
              value: _personal,
              hint: 'Not a business expense — no input credit is claimed.',
              onChanged: (v) => setState(() => _personal = v),
            ),
            AccPickerBox(
              label: 'TDS nature',
              value: _tdsOverride == null ? null : tdsNatures[_tdsOverride],
              hint: _category?.tdsNature == null
                  ? 'Category default'
                  : 'Default: ${tdsNatures[_category!.tdsNature]}',
              footnote: 'Leave as is unless your accountant says otherwise.',
              onTap: () async {
                final n = await pickTdsNature(context, selected: _tdsOverride);
                if (n != null) setState(() => _tdsOverride = n);
              },
            ),
          ],
        ),
        const AccInfoBanner('Posts the bill and its payment together. Tax, TDS and what is payable are worked out by the server.'),
      ],
    );
  }
}

/// The vendor picker row used by the purchase sheets, with a "Quick add"
/// action that opens the vendor form (and its duplicate-name check).
class VendorPickerField extends ConsumerWidget {
  const VendorPickerField({super.key, required this.vendor, required this.onChanged, this.enabled = true});

  final Vendor? vendor;
  final ValueChanged<Vendor> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccPickerBox(
          label: 'Vendor',
          required: true,
          value: vendor?.name,
          hint: 'Select vendor…',
          icon: PhosphorIconsRegular.magnifyingGlass,
          enabled: enabled,
          onTap: () async {
            final v = await pickVendor(context, ref, selectedId: vendor?.id);
            if (v != null) onChanged(v);
          },
        ),
        if (enabled && ref.watch(accPermProvider('acc_purchase')).create)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              final v = await showVendorFormSheet(context);
              if (v != null) onChanged(v);
            },
            child: Padding(
              padding: EdgeInsets.only(top: 7.h),
              child: Row(
                children: [
                  Icon(PhosphorIconsBold.plus, size: 12.sp, color: AppColors.blueBright),
                  SizedBox(width: 5.w),
                  Text('Quick add vendor',
                      style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.blueBright)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
