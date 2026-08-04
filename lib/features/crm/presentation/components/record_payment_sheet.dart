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
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/invoices_providers.dart';
import '../../application/providers/payments_providers.dart';
import '../../domain/entities/invoice.dart';
import '../../domain/entities/payment.dart';

/// The prototype's `#35507C` info-banner text — no design token exists for it.
const Color _bannerText = Color(0xFF35507C);
const List<String> _payMethods = ['Bank transfer', 'UPI', 'Card', 'Cash', 'Cheque'];

/// Opens the "Record payment" sheet (prototype `recordPayment`). Settle marks the
/// next open installment paid; Ad-hoc inserts a new payment. Both toast.
Future<void> showRecordPaymentSheet(BuildContext context, {String? invoiceId}) {
  return showClozrSheet<void>(
    context: context,
    builder: (_) => _RecordPaymentSheet(initialInvoiceId: invoiceId),
  );
}

class _RecordPaymentSheet extends ConsumerStatefulWidget {
  const _RecordPaymentSheet({this.initialInvoiceId});
  final String? initialInvoiceId;

  @override
  ConsumerState<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends ConsumerState<_RecordPaymentSheet> {
  final _amount = TextEditingController();
  final _date = TextEditingController();
  final _label = TextEditingController();
  final _note = TextEditingController();

  String? _invId;
  String _mode = 'settle'; // 'settle' | 'adhoc'
  String _method = 'Bank transfer';
  int _seq = 20;

  @override
  void initState() {
    super.initState();
    final invoices = ref.read(invoicesProvider).valueOrNull ?? const [];
    _invId = widget.initialInvoiceId ??
        (invoices.where((i) => i.status != 'completed').isNotEmpty
            ? invoices.firstWhere((i) => i.status != 'completed').id
            : (invoices.isNotEmpty ? invoices.first.id : null));
  }

  @override
  void dispose() {
    for (final c in [_amount, _date, _label, _note]) {
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
    for (final p in payments) {
      if (p.invId == _invId && p.status != 'paid') return p;
    }
    return null;
  }

  void _pickInvoice() {
    final invoices = ref.read(invoicesProvider).valueOrNull ?? const [];
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
                                Text('${iv.id} · ${invoiceWho(iv)}', style: AppText.bodyStrong()),
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
      final override = {...ref.read(paidOverrideProvider), next.id};
      ref.read(paidOverrideProvider.notifier).state = override;
      if (ApiConfig.apiEnabled) {
        try {
          await ref.read(paymentsRepositoryProvider).markRecordPaid(
                next.id,
                amount: next.amountNum > 0 ? next.amountNum.toDouble() : null,
                method: const {
                      'Bank transfer': 'bank_transfer',
                      'UPI': 'upi',
                      'Card': 'card',
                      'Cash': 'cash',
                      'Cheque': 'cheque',
                    }[_method] ??
                    'upi',
              );
          if (!mounted) return;
          ref.invalidate(paymentsProvider);
          ref.invalidate(invoicesProvider);
        } on AppError catch (e) {
          if (!mounted) return;
          // Roll the optimistic override back — the record is still unpaid.
          ref.read(paidOverrideProvider.notifier).state = {
            ...ref.read(paidOverrideProvider)
          }..remove(next.id);
          ref.read(toastProvider.notifier).show(e.message);
          return;
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ref.read(toastProvider.notifier).show('Payment recorded');
      return;
    }
    final amt = int.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
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
                            inv != null ? '${inv.id} · ${invoiceWho(inv)}' : 'Select an invoice…',
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
                  _infoStrip(PhosphorIconsRegular.receipt,
                      '${inv.id} · balance ${inv.balance} · ${inv.settled}/${inv.of} settled'),
                ],
                SizedBox(height: 13.h),
                _segToggle(),
                SizedBox(height: 12.h),
                if (_mode == 'settle')
                  _infoBanner(next != null
                      ? '${next.label} · ${next.amount}. Recording will mark it as paid.'
                      : 'No open installments on this invoice.')
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

  Widget _footer() {
    return Container(
      padding: EdgeInsets.fromLTRB(18.w, 12.h, 18.w, 24.h),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderCardSoft))),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _submit,
        child: Container(
          height: 48.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(12.r)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(PhosphorIconsBold.check, size: 15.sp, color: AppColors.white),
              SizedBox(width: 8.w),
              Text('Record payment',
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

  Widget _field(String label, TextEditingController c, String hint, {bool number = false}) {
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
              keyboardType: number ? TextInputType.number : TextInputType.text,
              inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))] : null,
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
