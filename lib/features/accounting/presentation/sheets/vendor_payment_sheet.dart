import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../crm/presentation/components/crm_check_box.dart';
import '../../../crm/presentation/sheets/add_sheet_kit.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/accounting_invalidation.dart';
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/documents_providers.dart';
import '../../application/providers/settlement_providers.dart';
import '../../domain/entities/acc_document.dart';
import '../../domain/entities/acc_masters.dart';
import '../components/acc_pickers.dart';
import '../components/acc_widgets.dart';
import '../config/accounting_copy.dart';
import 'acc_sheet_scaffold.dart';

/// "Pay vendor" (plan §4.8, form D2) — money out against open vendor bills.
///
/// Vendors allow no unapplied remainder: the amount must be fully covered by
/// open bills (409 `PAYMENT_EXCEEDS_OPEN_BILLS` / `NO_OPEN_BILL`). A
/// prepayment is a vendor advance, which stays on the web app.
Future<bool?> showVendorPaymentSheet(BuildContext context, {String? vendorId, AccDocument? bill}) =>
    showClozrSheet<bool>(
      context: context,
      builder: (_) => _VendorPaymentSheet(vendorId: vendorId ?? bill?.vendorId, bill: bill),
    );

class _VendorPaymentSheet extends ConsumerStatefulWidget {
  const _VendorPaymentSheet({this.vendorId, this.bill});
  final String? vendorId;
  final AccDocument? bill;

  @override
  ConsumerState<_VendorPaymentSheet> createState() => _VendorPaymentSheetState();
}

class _VendorPaymentSheetState extends ConsumerState<_VendorPaymentSheet> {
  String _eventId = newEventId();
  late String? _vendorId = widget.vendorId;
  late final _amount = TextEditingController(text: _open(widget.bill) ?? '');
  final _reference = TextEditingController();
  final _owner = TextEditingController();
  final _tds = TextEditingController();
  String? _tdsNature;
  DateTime _date = DateTime.now();
  String _source = 'BANK';
  String _method = 'neft';
  BankAccount? _bank;
  late final Set<String> _targets = {if (widget.bill != null) widget.bill!.id};
  bool _busy = false;
  AppError? _error;

  static String? _open(AccDocument? d) {
    if (d == null) return null;
    final v = d.openBalance ?? d.payable;
    return v == null || moneyIsZero(v) ? null : v;
  }

  @override
  void initState() {
    super.initState();
    ref.read(bankAccountsProvider.future).then((accounts) {
      if (!mounted || _bank != null) return;
      final banks = [for (final a in accounts) if (a.kind == 'BANK') a];
      final def = banks.where((a) => a.isDefault).firstOrNull ?? (banks.length == 1 ? banks.first : null);
      if (def != null) setState(() => _bank = def);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [_amount, _reference, _owner, _tds]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fail(String m) => ref.read(toastProvider.notifier).showError(m);

  Future<void> _submit() async {
    final amount = moneyInput(_amount.text);
    if (_vendorId == null) return _fail('Pick the vendor');
    if (amount == null || moneyIsZero(amount)) return _fail('Enter the amount paid');
    if (_source == 'BANK' && _bank == null) return _fail('Pick the bank account it was paid from');
    if (_source == 'OWNER' && _owner.text.trim().isEmpty) return _fail('Say who paid from their own funds');
    final tds = moneyInput(_tds.text);
    if (tds != null && !moneyIsZero(tds) && _tdsNature == null) return _fail('Pick the TDS nature');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final out = await ref.read(accountingRepositoryProvider).recordVendorPayment({
        'vendor': _vendorId,
        'amount_paid': amount,
        'source_account_kind': _source,
        'payment_date': isoDay(_date),
        'bank_account': _source == 'BANK' ? _bank?.id : null,
        'owner': _source == 'OWNER' ? _owner.text.trim() : null,
        'tds_now': tds,
        'tds_nature': tds == null || moneyIsZero(tds) ? null : _tdsNature,
        if (_targets.isNotEmpty) 'targeted_document_ids': _targets.toList(),
        'method': _source == 'CASH' ? 'cash' : _method,
        'reference': _reference.text.trim(),
        'event_id': _eventId,
      });
      invalidateAccountingReads(ref.invalidate);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(out.skipped
          ? (out.skipReason ?? 'Already recorded — nothing new was posted')
          : 'Payment posted');
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
    final vendorName = ref.watch(vendorNameProvider)(_vendorId);
    return AccSheetScaffold(
      title: 'Pay vendor',
      submitLabel: 'Post payment',
      busy: _busy,
      error: _error,
      submitEnabled: ref.watch(accPermProvider('acc_settlement')).create,
      onSubmit: _submit,
      children: [
        AccPickerBox(
          label: 'Vendor',
          required: true,
          value: vendorName ?? (_vendorId == null ? null : 'Vendor'),
          hint: 'Select vendor…',
          icon: PhosphorIconsRegular.magnifyingGlass,
          enabled: widget.bill == null,
          onTap: () async {
            final v = await pickVendor(context, ref, selectedId: _vendorId);
            if (v != null) {
              setState(() {
                _vendorId = v.id;
                _targets.clear();
              });
            }
          },
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: MoneyField(label: 'Amount paid', required: true, controller: _amount)),
            SizedBox(width: 9.w),
            Expanded(
              child: AccDateBox(label: 'Paid on', value: _date, showIstHint: true,
                  onChanged: (d) => setState(() => _date = d ?? _date)),
            ),
          ],
        ),
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
        if (_source == 'BANK')
          AccChoiceChips(
            label: 'Method',
            options: {for (final e in paymentMethods.entries) if (e.key != 'cash' && e.key != 'gateway') e.key: e.value},
            selected: _method,
            onSelected: (v) => setState(() => _method = v),
          ),
        AccInput(label: 'Reference', controller: _reference, hint: 'UTR, cheque no…'),
        AccDisclosure(
          title: 'TDS deducted now',
          children: [
            MoneyField(label: 'TDS amount', controller: _tds, hint: 'Optional'),
            AccPickerBox(
              label: 'TDS nature',
              value: _tdsNature == null ? null : tdsNatures[_tdsNature],
              hint: 'Select nature…',
              onTap: () async {
                final n = await pickTdsNature(context, selected: _tdsNature);
                if (n != null) setState(() => _tdsNature = n);
              },
            ),
          ],
        ),
        if (_vendorId != null) _billPicker(_vendorId!),
        const AccInfoBanner(
          'The payment must be fully covered by open bills. To pay before a bill arrives, record a vendor advance on the web app.',
        ),
      ],
    );
  }

  Widget _billPicker(String vendorId) {
    final async = ref.watch(billsForVendorProvider(vendorId));
    final open = [
      for (final d in async.valueOrNull ?? const <AccDocument>[])
        if (d.isIssued && (d.paymentState == 'UNPAID' || d.paymentState == 'PARTIAL')) d,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetFieldLabel('Against bills'),
        if (async.isLoading && open.isEmpty)
          Text('Loading open bills…', style: AppText.caption())
        else if (open.isEmpty)
          Text('No open bills for this vendor.',
              style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted))
        else ...[
          Text(_targets.isEmpty ? 'Oldest bills first' : '${_targets.length} selected',
              style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
          SizedBox(height: 6.h),
          for (final d in open)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _targets.contains(d.id) ? _targets.remove(d.id) : _targets.add(d.id)),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 7.h),
                child: Row(
                  children: [
                    CrmCheckBox(
                      done: _targets.contains(d.id),
                      size: 22,
                      onTap: () => setState(() => _targets.contains(d.id) ? _targets.remove(d.id) : _targets.add(d.id)),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text(
                        '${d.displayNumber}${(d.vendorInvoiceNo ?? '').isEmpty ? '' : ' · ${d.vendorInvoiceNo}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textBody),
                      ),
                    ),
                    Text(formatMoneyStr(d.openBalance ?? d.payable),
                        style: AppText.custom(size: 13, weight: FontWeight.w800, color: AppColors.textPrimary)),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}
