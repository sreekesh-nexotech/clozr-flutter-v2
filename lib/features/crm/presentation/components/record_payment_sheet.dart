import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/utils/money_format.dart';
import '../../../accounting/application/providers/accounting_invalidation.dart';
import '../../../accounting/application/providers/accounting_providers.dart';
import '../../../accounting/domain/entities/acc_masters.dart';
import '../../../accounting/presentation/components/acc_pickers.dart';
import '../../../accounting/presentation/components/acc_widgets.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../sheets/add_sheet_kit.dart' show pickSheetDate, sheetDateLabel;
import '../../application/providers/crm_party_providers.dart';
import '../../application/providers/invoices_providers.dart';
import '../../application/providers/payments_providers.dart';
import '../../domain/entities/invoice.dart';
import '../../domain/entities/payment.dart';

/// The prototype's `#35507C` info-banner text — no design token exists for it.
const Color _bannerText = Color(0xFF35507C);
const List<String> _payMethods = ['Bank transfer', 'UPI', 'Card', 'Cash', 'Cheque'];

/// Opens the "Record payment" sheet (prototype `recordPayment`). Settle marks the
/// next open installment paid — or [recordId], when the caller is one specific
/// instalment; Ad-hoc inserts a new payment. Both toast.
Future<void> showRecordPaymentSheet(BuildContext context, {String? invoiceId, String? recordId}) {
  return showClozrSheet<void>(
    context: context,
    builder: (_) => _RecordPaymentSheet(initialInvoiceId: invoiceId, recordId: recordId),
  );
}

class _RecordPaymentSheet extends ConsumerStatefulWidget {
  const _RecordPaymentSheet({this.initialInvoiceId, this.recordId});
  final String? initialInvoiceId;

  /// Settle this record rather than the invoice's next open one.
  final String? recordId;

  @override
  ConsumerState<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends ConsumerState<_RecordPaymentSheet> {
  final _amount = TextEditingController();
  final _date = TextEditingController();
  final _label = TextEditingController();
  final _note = TextEditingController();

  /// Amounts withheld from the receipt. Only sent when settling, and only when
  /// non-zero — the API accepts them on a record being marked paid.
  final _tds = TextEditingController();
  final _bankCharge = TextEditingController();

  String? _invId;
  String _mode = 'settle'; // 'settle' | 'adhoc'
  String _method = 'Bank transfer';
  int _seq = 20;

  /// When the money actually arrived. It used to be forced to today, which
  /// posts a receipt into the wrong period whenever it is recorded late.
  DateTime _received = DateTime.now();

  /// Accounting only: the bank account a non-cash receipt landed in. Without
  /// one (and without an org default) the ledger refuses the whole write.
  BankAccount? _bank;

  /// Accounting only, and only for a record with no issued invoice: book the
  /// money as a taxed advance or as a customer credit. Null = the server's
  /// default (services → advance, goods → credit).
  String? _treatAs;
  final _gatewayRef = TextEditingController();
  bool _busy = false;
  AppError? _error;

  @override
  void initState() {
    super.initState();
    final invoices = ref.read(invoicesProvider).valueOrNull ?? const [];
    _invId = widget.initialInvoiceId ??
        (invoices.where((i) => i.status != 'completed').isNotEmpty
            ? invoices.firstWhere((i) => i.status != 'completed').id
            : (invoices.isNotEmpty ? invoices.first.id : null));
    // Pre-select the org's default bank, so the common case needs no tap.
    if (ref.read(accountingActiveProvider)) {
      ref.read(bankAccountsProvider.future).then((accounts) {
        if (!mounted || _bank != null) return;
        final banks = [for (final a in accounts) if (a.kind == 'BANK') a];
        final def = banks.where((a) => a.isDefault).firstOrNull ?? (banks.length == 1 ? banks.first : null);
        if (def != null) setState(() => _bank = def);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    for (final c in [_amount, _date, _label, _note, _tds, _bankCharge, _gatewayRef]) {
      c.dispose();
    }
    super.dispose();
  }

  Invoice? get _invoice {
    final invoices = ref.read(invoicesProvider).valueOrNull ?? const [];
    for (final iv in invoices) {
      if (iv.id == _invId) return iv;
    }
    return null;
  }

  Payment? get _nextInstallment {
    final payments = ref.read(allPaymentsProvider);
    if (widget.recordId != null) {
      final own = payments.where((p) => p.id == widget.recordId).firstOrNull;
      if (own != null && own.status != 'paid') return own;
    }
    for (final p in payments) {
      // Both keys, matching paymentsForInvoiceProvider: `Invoice.id` is the
      // quote number when there is one and the plan uuid otherwise, so the
      // second clause survives the deprecated `invoice_id` being removed.
      if ((p.invId == _invId || p.planUuid == _invId) && p.status != 'paid') {
        return p;
      }
    }
    return null;
  }

  void _pickInvoice() {
    final invoices = ref.read(invoicesProvider).valueOrNull ?? const [];
    final lookup = ref.read(crmPartyLookupProvider);
    showClozrSheet<void>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: 'Select invoice', onClose: () => Navigator.of(ctx).pop()),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(14.w, 4.h, 14.w, 28.h),
              children: [
                for (final iv in invoices)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() => _invId = iv.id);
                      Navigator.of(ctx).pop();
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 9.h, horizontal: 6.w),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${iv.id} · ${invoiceWho(iv, lookup)}', style: AppText.bodyStrong()),
                                SizedBox(height: 2.h),
                                Text('Balance ${iv.balance}', style: AppText.caption()),
                              ],
                            ),
                          ),
                          if (_invId == iv.id)
                            Icon(PhosphorIconsBold.check, size: 19.sp, color: AppColors.success),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Everything withheld from the receipt, in rupees and paise.
  double get _deductions => moneyNum(_tds.text.trim()) + moneyNum(_bankCharge.text.trim());

  /// The instalment's contracted amount, exactly — never the rounded display.
  double _expected(Payment p) =>
      p.amountExact.isNotEmpty ? moneyNum(p.amountExact) : p.amountNum.toDouble();

  Future<void> _submit() async {
    final inv = _invoice;
    if (inv == null) {
      ref.read(toastProvider.notifier).show('Pick an invoice');
      return;
    }
    if (_mode == 'settle') {
      final next = _nextInstallment;
      if (next == null) {
        Navigator.of(context).pop();
        ref.read(toastProvider.notifier).show('All installments already settled');
        return;
      }
      // Guarded here rather than by a 400: the API refuses a negative cash
      // figure, and silently sending one would roll the optimistic tick back
      // with a message the user cannot act on.
      final expected = _expected(next);
      if (_deductions > expected + 0.005) {
        ref.read(toastProvider.notifier).show(
            'Deductions cannot be more than ${formatMoneyStr(toMoneyStr(expected))}');
        return;
      }
      final accounting = ref.read(accountingActiveProvider);
      final code = const {
            'Bank transfer': 'bank_transfer',
            'UPI': 'upi',
            'Card': 'card',
            'Cash': 'cash',
            'Cheque': 'cheque',
          }[_method] ??
          'upi';
      if (accounting && code != 'cash' && _bank == null) {
        ref.read(toastProvider.notifier).showError('Pick the bank account the money came into');
        return;
      }
      if (_busy) return;
      setState(() {
        _busy = true;
        _error = null;
      });
      final override = {...ref.read(paidOverrideProvider), next.id};
      ref.read(paidOverrideProvider.notifier).state = override;
      var posted = false;
      if (ApiConfig.apiEnabled) {
        try {
          posted = await ref.read(paymentsRepositoryProvider).markRecordPaid(
                next.id,
                // Cash actually received. The instalment still settles for its
                // full contracted amount — the withheld part counts toward
                // completion server-side.
                amountPaid: expected > 0 ? toMoneyStr(expected - _deductions) : null,
                method: code,
                paidDate: _received,
                tdsDeducted: moneyInput(_tds.text),
                bankCharge: moneyInput(_bankCharge.text),
                bankAccountId: accounting && code != 'cash' ? _bank?.id : null,
                treatAs: accounting && next.linkedDocumentId == null ? _treatAs : null,
                gatewayRef: accounting ? _gatewayRef.text.trim() : null,
              );
          if (!mounted) return;
          ref.invalidate(paymentsProvider);
          ref.invalidate(invoicesProvider);
          if (accounting) invalidateAccountingReads(ref.invalidate);
        } on AppError catch (e) {
          if (!mounted) return;
          // Roll the optimistic override back — the record is still unpaid —
          // and keep the sheet open with the reason, so the user can fix it
          // (a missing bank account, a closed period) without retyping.
          ref.read(paidOverrideProvider.notifier).state = {
            ...ref.read(paidOverrideProvider)
          }..remove(next.id);
          setState(() {
            _busy = false;
            _error = e;
          });
          return;
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ref.read(toastProvider.notifier).show(posted ? 'Payment recorded · receipt posted' : 'Payment recorded');
      return;
    }
    // Ad-hoc branch. No backend endpoint exists, so in API mode we don't
    // fabricate a local Payment or claim success — we say so honestly. (The UI
    // also hides the ad-hoc toggle in API mode; this is a defensive guard.)
    if (ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show("Recording ad-hoc payments isn't available yet");
      return;
    }
    final amt = moneyNum(_amount.text).round();
    if (amt <= 0) {
      ref.read(toastProvider.notifier).show('Enter the amount received');
      return;
    }
    final id = 'PAY-${4020 + _seq}';
    final pay = Payment(
      id: id,
      custId: inv.custId,
      invId: inv.id,
      label: _label.text.trim().isEmpty ? 'Ad-hoc payment' : _label.text.trim(),
      amount: _fmtAmt(amt),
      amountNum: amt,
      method: _method,
      status: 'paid',
      date: _date.text.trim().isEmpty ? 'Paid just now' : _date.text.trim(),
      owner: 'me',
    );
    ref.read(manualPaymentsProvider.notifier).state = [pay, ...ref.read(manualPaymentsProvider)];
    _seq++;
    Navigator.of(context).pop();
    ref.read(toastProvider.notifier).show('Payment recorded');
  }

  @override
  Widget build(BuildContext context) {
    final inv = _invoice;
    final next = _nextInstallment;
    final lookup = ref.watch(crmPartyLookupProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'Record payment', onClose: () => Navigator.of(context).maybePop()),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 12.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null) ...[
                  ConflictBanner(error: _error!),
                  SizedBox(height: 13.h),
                ],
                _label$('Invoice', required: true),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _pickInvoice,
                  child: Container(
                    height: 46.h,
                    padding: EdgeInsets.symmetric(horizontal: 14.w),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(11.r),
                      border: Border.all(color: AppColors.borderInput, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            inv != null ? '${inv.id} · ${invoiceWho(inv, lookup)}' : 'Select an invoice…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: inv != null
                                ? AppText.body()
                                : AppText.body(color: AppColors.textPlaceholder),
                          ),
                        ),
                        Icon(PhosphorIconsRegular.magnifyingGlass,
                            size: 15.sp, color: AppColors.textPlaceholder),
                      ],
                    ),
                  ),
                ),
                if (inv != null) ...[
                  SizedBox(height: 11.h),
                  _infoStrip(
                      PhosphorIconsRegular.receipt,
                      '${inv.id} · balance ${inv.balance}'
                      '${inv.hasRecordCounts ? " · ${inv.settled}/${inv.of} settled" : ""}'),
                ],
                SizedBox(height: 13.h),
                // Ad-hoc recording has no backend endpoint yet, so in API mode
                // only the (real) "settle an installment" flow is offered.
                if (!ApiConfig.apiEnabled) ...[
                  _segToggle(),
                  SizedBox(height: 12.h),
                ],
                if (_mode == 'settle') ...[
                  _infoBanner(next != null
                      ? '${next.label} · ${next.amount}. Recording will mark it as paid.'
                      : 'No open installments on this invoice.'),
                  // Optional, and left blank on an ordinary receipt. Without
                  // these the full gross is recorded as cash that never
                  // arrived, overstating the org's cash position whenever tax
                  // is withheld at source.
                  if (next != null) ...[
                    SizedBox(height: 13.h),
                    _label$('Received on', required: true),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () async {
                        final d = await pickSheetDate(context, isoDay(_received));
                        if (d != null) setState(() => _received = d);
                      },
                      child: Container(
                        height: 44.h,
                        padding: EdgeInsets.symmetric(horizontal: 13.w),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(11.r),
                          border: Border.all(color: AppColors.borderInput, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            Expanded(child: Text(sheetDateLabel(_received), style: AppText.body())),
                            Icon(PhosphorIconsRegular.calendarBlank, size: 15.sp, color: AppColors.textPlaceholder),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 13.h),
                    Row(
                      children: [
                        // Rebuilt on every keystroke: the "cash received"
                        // line below is the only confirmation that a deduction
                        // was understood, and it reads these controllers.
                        Expanded(
                            child: _field('TDS withheld (₹)', _tds, 'Optional',
                                number: true, onChanged: (_) => setState(() {}))),
                        SizedBox(width: 9.w),
                        Expanded(
                            child: _field('Bank charge (₹)', _bankCharge, 'Optional',
                                number: true, onChanged: (_) => setState(() {}))),
                      ],
                    ),
                    if (_deductions > 0) ...[
                      SizedBox(height: 7.h),
                      Text(
                          'Cash ${formatMoneyStr(toMoneyStr(_expected(next) - _deductions))}'
                          ' + withheld ${formatMoneyStr(toMoneyStr(_deductions))}'
                          ' = settles ${formatMoneyStr(toMoneyStr(_expected(next)))}',
                          style: AppText.custom(
                              size: 11.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                    ],
                  ],
                ]
                else ...[
                  Row(
                    children: [
                      Expanded(child: _field('Amount (₹)', _amount, 'e.g. 250000', number: true)),
                      SizedBox(width: 9.w),
                      Expanded(child: _field('Date received', _date, 'e.g. 25 Jun 2026')),
                    ],
                  ),
                  SizedBox(height: 13.h),
                  _field('Reference / label', _label, 'e.g. Part payment'),
                ],
                SizedBox(height: 13.h),
                _label$('Method'),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [for (final m in _payMethods) _methodChip(m)],
                ),
                if (_mode == 'settle' && next != null && ref.watch(accountingActiveProvider)) ..._accountingFields(next),
                SizedBox(height: 13.h),
                _field('Notes', _note, 'Internal note, e.g. Installment 1 of 3'),
                SizedBox(height: 6.h),
              ],
            ),
          ),
        ),
        _footer(),
      ],
    );
  }

  /// The receipt the ledger will post: which bank it landed in and, for an
  /// instalment with no issued invoice, how to book it (handover §9.1).
  List<Widget> _accountingFields(Payment next) {
    final cash = _method == 'Cash';
    return [
      if (!cash) ...[
        SizedBox(height: 13.h),
        AccPickerBox(
          label: 'Into bank account',
          required: true,
          value: _bank?.label,
          hint: 'Select account…',
          onTap: () async {
            final b = await pickBankAccount(context, ref, selectedId: _bank?.id);
            if (b != null) setState(() => _bank = b);
          },
        ),
        SizedBox(height: 13.h),
        _field('Gateway / UTR reference', _gatewayRef, 'Optional'),
      ],
      if (next.linkedDocumentId == null) ...[
        SizedBox(height: 13.h),
        AccChoiceChips(
          label: 'No invoice yet — book it as',
          options: const {'': 'Automatic', 'ADVANCE': 'Advance', 'CUSTOMER_CREDIT': 'Customer credit'},
          selected: _treatAs ?? '',
          onSelected: (v) => setState(() => _treatAs = v.isEmpty ? null : v),
        ),
      ],
    ];
  }

  Widget _footer() {
    return Container(
      padding: EdgeInsets.fromLTRB(18.w, 12.h, 18.w, 24.h),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderCardSoft))),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _busy ? null : _submit,
        child: Container(
          height: 48.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: _busy ? AppColors.navy.withOpacity(0.6) : AppColors.navy,
              borderRadius: BorderRadius.circular(12.r)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(PhosphorIconsBold.check, size: 15.sp, color: AppColors.white),
              SizedBox(width: 8.w),
              Text(_busy ? 'Recording…' : 'Record payment',
                  style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segToggle() {
    return Container(
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(12.r)),
      child: Row(
        children: [
          Expanded(child: _seg('settle', PhosphorIconsRegular.checkCircle, 'Settle an installment')),
          SizedBox(width: 6.w),
          Expanded(child: _seg('adhoc', PhosphorIconsRegular.currencyInr, 'Ad-hoc amount')),
        ],
      ),
    );
  }

  Widget _seg(String key, IconData icon, String label) {
    final on = _mode == key;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _mode = key),
      child: Container(
        height: 38.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15.sp, color: on ? AppColors.navy : AppColors.textMuted),
            SizedBox(width: 6.w),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.custom(
                      size: 12.5,
                      weight: FontWeight.w700,
                      color: on ? AppColors.navy : AppColors.textMuted)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _methodChip(String m) {
    final on = _method == m;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _method = m),
      child: Container(
        height: 34.h,
        padding: EdgeInsets.symmetric(horizontal: 13.w),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.navy : AppColors.white,
          borderRadius: BorderRadius.circular(9.r),
          border: on ? null : Border.all(color: AppColors.borderInput),
        ),
        child: Text(m,
            style: AppText.custom(
                size: 12.5,
                weight: on ? FontWeight.w700 : FontWeight.w600,
                color: on ? AppColors.white : AppColors.textLabel)),
      ),
    );
  }

  Widget _infoStrip(IconData icon, String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(10.r)),
      child: Row(
        children: [
          Icon(icon, size: 15.sp, color: AppColors.navy),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(text,
                style: AppText.custom(size: 12, weight: FontWeight.w600, color: _bannerText)),
          ),
        ],
      ),
    );
  }

  Widget _infoBanner(String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 11.h),
      decoration: BoxDecoration(color: AppColors.blueSubtle, borderRadius: BorderRadius.circular(10.r)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsRegular.info, size: 15.sp, color: AppColors.blueBright),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(text,
                style: AppText.custom(size: 12, weight: FontWeight.w500, color: _bannerText, height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c, String hint,
      {bool number = false, ValueChanged<String>? onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label$(label),
        Container(
          height: 44.h,
          padding: EdgeInsets.symmetric(horizontal: 13.w),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(11.r),
            border: Border.all(color: AppColors.borderInput, width: 1.5),
          ),
          child: Center(
            child: TextField(
              controller: c,
              onChanged: onChanged,
              keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
              // Paise allowed: TDS is rarely a round figure.
              inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))] : null,
              style: AppText.body(),
              cursorColor: AppColors.blueBright,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: AppText.body(color: AppColors.textPlaceholder),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _label$(String text, {bool required = false}) => Padding(
        padding: EdgeInsets.only(bottom: 7.h),
        child: Row(
          children: [
            Text(text,
                style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
            if (required)
              Text(' *', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.error)),
          ],
        ),
      );

  String _fmtAmt(int n) {
    if (n >= 10000000) return '₹${(n / 10000000).toStringAsFixed(n % 10000000 == 0 ? 0 : 2)}Cr';
    if (n >= 100000) return '₹${(n / 100000).toStringAsFixed(n % 100000 == 0 ? 0 : 1)}L';
    return '₹${(n / 1000).toStringAsFixed(0)}K';
  }
}
