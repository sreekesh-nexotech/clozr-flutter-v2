import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/network/app_error.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../crm/application/providers/crm_party_providers.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/accounting_invalidation.dart';
import '../../application/providers/accounting_providers.dart';
import '../../domain/entities/acc_masters.dart';
import '../components/acc_pickers.dart';
import '../components/acc_widgets.dart';
import '../config/accounting_copy.dart';
import 'acc_sheet_scaffold.dart';

/// "Record advance" (plan §4.8, form B3) — money received before any invoice.
/// Services are taxed at receipt, so the nature, supply and rate are asked.
/// The response is the receipt row, not the advance (§12.12); the advance
/// appears in the Advances list on refresh.
Future<bool?> showRecordAdvanceSheet(BuildContext context, {String? customerId}) =>
    showClozrSheet<bool>(context: context, builder: (_) => _RecordAdvanceSheet(customerId: customerId));

class _RecordAdvanceSheet extends ConsumerStatefulWidget {
  const _RecordAdvanceSheet({this.customerId});
  final String? customerId;

  @override
  ConsumerState<_RecordAdvanceSheet> createState() => _RecordAdvanceSheetState();
}

class _RecordAdvanceSheetState extends ConsumerState<_RecordAdvanceSheet> {
  String _eventId = newEventId();
  late String? _customerId = widget.customerId;
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _reference = TextEditingController();
  final _gateway = TextEditingController();
  DateTime _date = DateTime.now();
  String _source = 'BANK';
  String _method = 'upi';
  String _supply = 'INTRA';
  String _nature = 'SERVICE';
  bool _taxable = true;
  BankAccount? _bank;
  bool _busy = false;
  AppError? _error;

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
    for (final c in [_amount, _rate, _reference, _gateway]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fail(String m) => ref.read(toastProvider.notifier).showError(m);

  Future<void> _submit() async {
    final amount = moneyInput(_amount.text);
    if (_customerId == null) return _fail('Pick the customer who paid');
    if (amount == null || moneyIsZero(amount)) return _fail('Enter the amount received');
    if (_source == 'BANK' && _bank == null) return _fail('Pick the bank account it came into');
    if (_source == 'GATEWAY' && _gateway.text.trim().isEmpty) return _fail('Say which gateway collected it');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final out = await ref.read(accountingRepositoryProvider).recordAdvance({
        'customer': _customerId,
        'amount_received': amount,
        'source_account_kind': _source,
        'receipt_date': isoDay(_date),
        'supply': _supply,
        'supply_nature': _nature,
        'rate_pct': _rate.text.trim(),
        'taxable_supply': _taxable,
        'bank_account': _source == 'BANK' ? _bank?.id : null,
        'gateway_provider': _source == 'GATEWAY' ? _gateway.text.trim() : null,
        'method': _source == 'CASH' ? 'cash' : _method,
        'reference': _reference.text.trim(),
        'event_id': _eventId,
      });
      invalidateAccountingReads(ref.invalidate);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(
          out.skipped ? (out.skipReason ?? 'Already recorded — nothing new was posted') : 'Advance posted');
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
    final party = ref.watch(crmPartyLookupProvider)(custId: _customerId);
    return AccSheetScaffold(
      title: 'Record advance',
      submitLabel: 'Post advance',
      busy: _busy,
      error: _error,
      submitEnabled: ref.watch(accPermProvider('acc_settlement')).create,
      onSubmit: _submit,
      children: [
        AccPickerBox(
          label: 'Customer',
          required: true,
          value: party?.name ?? (_customerId == null ? null : 'Customer'),
          hint: 'Select customer…',
          icon: PhosphorIconsRegular.magnifyingGlass,
          enabled: widget.customerId == null,
          onTap: () async {
            final c = await pickCustomer(context, ref, selectedId: _customerId);
            if (c != null) setState(() => _customerId = c.id);
          },
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: MoneyField(label: 'Amount received', required: true, controller: _amount)),
            SizedBox(width: 9.w),
            Expanded(
              child: AccDateBox(label: 'Received on', value: _date, showIstHint: true,
                  onChanged: (d) => setState(() => _date = d ?? _date)),
            ),
          ],
        ),
        AccChoiceChips(
          label: 'Into',
          required: true,
          options: const {'BANK': 'Bank', 'CASH': 'Cash', 'GATEWAY': 'Gateway'},
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
        if (_source == 'GATEWAY') AccInput(label: 'Gateway', required: true, controller: _gateway, hint: 'e.g. razorpay'),
        if (_source != 'CASH')
          AccChoiceChips(
            label: 'Method',
            options: {for (final e in paymentMethods.entries) if (e.key != 'cash') e.key: e.value},
            selected: _method,
            onSelected: (v) => setState(() => _method = v),
          ),
        AccChoiceChips(
          label: 'Nature',
          required: true,
          options: supplyNatureLabels,
          selected: _nature,
          onSelected: (v) => setState(() => _nature = v),
        ),
        AccChoiceChips(
          label: 'Supply',
          required: true,
          options: const {'INTRA': 'Within the state', 'INTER': 'Another state'},
          selected: _supply,
          onSelected: (v) => setState(() => _supply = v),
        ),
        AccInput(
          label: 'GST rate %',
          controller: _rate,
          hint: 'e.g. 18',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
        ),
        AccCheckRow(
          label: 'Taxable supply',
          value: _taxable,
          hint: 'Untick for nil-rated or exempt supplies.',
          onChanged: (v) => setState(() => _taxable = v),
        ),
        AccInput(label: 'Reference', controller: _reference, hint: 'UTR, cheque no…'),
        const AccInfoBanner('The advance is set off against the invoice when it is issued.'),
      ],
    );
  }
}
