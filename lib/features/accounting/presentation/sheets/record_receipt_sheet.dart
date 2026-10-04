import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../crm/application/providers/crm_party_providers.dart';
import '../../../crm/presentation/components/crm_check_box.dart';
import '../../../crm/presentation/sheets/add_sheet_kit.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/accounting_invalidation.dart';
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/documents_providers.dart';
import '../../domain/entities/acc_document.dart';
import '../../domain/entities/acc_masters.dart';
import '../components/acc_pickers.dart';
import '../components/acc_widgets.dart';
import '../config/accounting_copy.dart';
import 'acc_sheet_scaffold.dart';

/// "Record receipt" (plan §4.8) — customer money in, posted straight to the
/// ledger and allocated to the customer's open invoices.
///
/// Opened from an invoice it targets that invoice; opened from Money it lets
/// the user pick the customer and, optionally, the invoices (blank = oldest
/// first). The [_eventId] is minted when the sheet opens and reused on a
/// network retry, so a double tap or a timeout replay posts once; once the
/// server has answered it is replaced (see [nextEventId]).
Future<bool?> showRecordReceiptSheet(BuildContext context, {String? customerId, AccDocument? invoice}) =>
    showClozrSheet<bool>(
      context: context,
      builder: (_) => _RecordReceiptSheet(customerId: customerId ?? invoice?.customerId, invoice: invoice),
    );

class _RecordReceiptSheet extends ConsumerStatefulWidget {
  const _RecordReceiptSheet({this.customerId, this.invoice});
  final String? customerId;
  final AccDocument? invoice;

  @override
  ConsumerState<_RecordReceiptSheet> createState() => _RecordReceiptSheetState();
}

class _RecordReceiptSheetState extends ConsumerState<_RecordReceiptSheet> {
  String _eventId = newEventId();
  late String? _customerId = widget.customerId;
  late final _amount = TextEditingController(
      text: widget.invoice?.openBalance == null || moneyIsZero(widget.invoice!.openBalance)
          ? ''
          : widget.invoice!.openBalance);
  final _reference = TextEditingController();
  final _tds = TextEditingController();
  final _tdsCert = TextEditingController();
  final _bankCharge = TextEditingController();
  final _gateway = TextEditingController();
  DateTime _date = DateTime.now();
  String _source = 'BANK';
  String _method = 'upi';
  BankAccount? _bank;
  late final Set<String> _targets = {if (widget.invoice != null) widget.invoice!.id};
  bool _busy = false;
  AppError? _error;

  @override
  void initState() {
    super.initState();
    // Pre-select the default bank so the common case is one tap.
    ref.read(bankAccountsProvider.future).then((accounts) {
      if (!mounted || _bank != null) return;
      final banks = [for (final a in accounts) if (a.kind == 'BANK') a];
      final def = banks.where((a) => a.isDefault).firstOrNull ?? (banks.length == 1 ? banks.first : null);
      if (def != null) setState(() => _bank = def);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [_amount, _reference, _tds, _tdsCert, _bankCharge, _gateway]) {
      c.dispose();
    }
    super.dispose();
  }

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
      final out = await ref.read(accountingRepositoryProvider).recordReceipt({
        'customer': _customerId,
        'amount_received': amount,
        'source_account_kind': _source,
        'receipt_date': isoDay(_date),
        'bank_account': _source == 'BANK' ? _bank?.id : null,
        'gateway_provider': _source == 'GATEWAY' ? _gateway.text.trim() : null,
        'tds_deducted': moneyInput(_tds.text),
        'tds_certificate_ref': _tdsCert.text.trim(),
        'bank_charge': moneyInput(_bankCharge.text),
        if (_targets.isNotEmpty) 'targeted_document_ids': _targets.toList(),
        'method': _source == 'CASH' ? 'cash' : _method,
        'reference': _reference.text.trim(),
        'event_id': _eventId,
      });
      invalidateAccountingReads(ref.invalidate);
      if (!mounted) return;
      final toast = ref.read(toastProvider.notifier);
      if (out.skipped) {
        toast.show(out.skipReason ?? 'Already recorded — nothing new was posted');
      } else {
        final unallocated = out.value?.unallocated;
        toast.show(moneyIsZero(unallocated)
            ? 'Receipt posted'
            : 'Receipt posted · ${formatMoneyStr(unallocated)} kept as customer credit');
      }
      Navigator.of(context).pop(true);
    } on AppError catch (e) {
      _eventId = nextEventId(_eventId, e);
      if (!mounted) return;
      // Nothing is invalidated on a refusal: nothing was posted.
      setState(() {
        _busy = false;
        _error = e;
      });
    }
  }

  void _fail(String msg) => ref.read(toastProvider.notifier).showError(msg);

  @override
  Widget build(BuildContext context) {
    final lookup = ref.watch(crmPartyLookupProvider);
    final party = lookup(custId: _customerId);
    final cash = _source == 'CASH' && moneyNum(_amount.text) >= 200000;
    return AccSheetScaffold(
      title: 'Record receipt',
      submitLabel: 'Post receipt',
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
          enabled: widget.invoice == null,
          onTap: () async {
            final c = await pickCustomer(context, ref, selectedId: _customerId);
            if (c != null) {
              setState(() {
                _customerId = c.id;
                _targets.clear();
              });
            }
          },
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: MoneyField(label: 'Amount received', required: true, controller: _amount, onChanged: (_) => setState(() {}))),
            SizedBox(width: 9.w),
            Expanded(
              child: AccDateBox(label: 'Received on', value: _date, showIstHint: true, onChanged: (d) => setState(() => _date = d ?? _date)),
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
        if (cash)
          const AccInfoBanner('Cash of ₹2 lakh or more from one customer in a day is restricted under section 269ST.',
              icon: PhosphorIconsRegular.warning),
        AccInput(label: 'Reference', controller: _reference, hint: 'UTR, cheque no…'),
        AccDisclosure(
          title: 'TDS and charges',
          initiallyOpen: false,
          children: [
            Row(
              children: [
                Expanded(child: MoneyField(label: 'TDS deducted', controller: _tds, hint: 'Optional')),
                SizedBox(width: 9.w),
                Expanded(child: MoneyField(label: 'Bank charge', controller: _bankCharge, hint: 'Optional')),
              ],
            ),
            AccInput(label: 'TDS certificate ref', controller: _tdsCert, hint: 'Optional'),
          ],
        ),
        if (_customerId != null && widget.invoice == null) _targetPicker(_customerId!),
        const AccInfoBanner('Anything more than the invoices owe is kept as a customer credit.'),
      ],
    );
  }

  Widget _targetPicker(String customerId) {
    final async = ref.watch(openInvoicesForCustomerProvider(customerId));
    final open = async.valueOrNull ?? const <AccDocument>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetFieldLabel('Apply to'),
        if (async.isLoading && open.isEmpty)
          Text('Loading open invoices…', style: AppText.caption())
        else if (open.isEmpty)
          Text('No open invoices — the whole amount becomes a customer credit.',
              style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted))
        else ...[
          Text(_targets.isEmpty ? 'Oldest invoices first' : '${_targets.length} selected',
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
                      child: Text('${d.displayNumber} · ${formatApiDay(d.documentDate)}',
                          style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textBody)),
                    ),
                    Text(formatMoneyStr(d.openBalance),
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
