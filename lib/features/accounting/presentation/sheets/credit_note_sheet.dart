import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../crm/presentation/components/crm_check_box.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/accounting_invalidation.dart';
import '../../application/providers/accounting_providers.dart';
import '../../domain/entities/acc_document.dart';
import '../components/acc_widgets.dart';
import 'acc_sheet_scaffold.dart';

/// A credit note against an issued invoice (plan §4.7) — goods returned, or a
/// value correction. Discounts, rate corrections and debit notes need line-
/// level rate edits and an s.15(3) attestation, so they stay on the web.
///
/// No `settlement_leg` is sent. Its refund leg always posts to cash and the
/// split is not validated (handover §12.2), and the app cannot know the note's
/// total before the server computes its tax. The server default — reduce what
/// the customer owes, hold the rest as a credit — is the safe one.
Future<AccDocument?> showCreditNoteSheet(BuildContext context, AccDocument invoice) =>
    showClozrSheet<AccDocument>(context: context, builder: (_) => _CreditNoteSheet(invoice: invoice));

class _LineDraft {
  _LineDraft(this.line)
      : qty = TextEditingController(text: _trim(line.qty)),
        price = TextEditingController(text: line.unitPrice);

  final AccDocumentLine line;
  final TextEditingController qty;
  final TextEditingController price;
  bool on = false;

  static String _trim(String q) {
    final v = double.tryParse(q);
    if (v == null) return q;
    return v == v.roundToDouble() ? v.toInt().toString() : '$v';
  }
}

class _CreditNoteSheet extends ConsumerStatefulWidget {
  const _CreditNoteSheet({required this.invoice});
  final AccDocument invoice;

  @override
  ConsumerState<_CreditNoteSheet> createState() => _CreditNoteSheetState();
}

class _CreditNoteSheetState extends ConsumerState<_CreditNoteSheet> {
  String _reason = 'RETURN';
  bool _withGst = true;
  DateTime _date = DateTime.now();
  late final List<_LineDraft> _lines = [for (final l in widget.invoice.lines) _LineDraft(l)];
  bool _busy = false;
  AppError? _error;

  @override
  void dispose() {
    for (final l in _lines) {
      l.qty.dispose();
      l.price.dispose();
    }
    super.dispose();
  }

  /// qty × price over the chosen lines — a hint; tax is the server's.
  double get _taxableHint => _lines
      .where((l) => l.on)
      .fold(0.0, (s, l) => s + moneyNum(l.qty.text) * moneyNum(l.price.text));

  Future<void> _submit() async {
    final chosen = _lines.where((l) => l.on).toList();
    if (chosen.isEmpty) {
      ref.read(toastProvider.notifier).showError('Pick at least one line to credit');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final note = await ref.read(accountingRepositoryProvider).createCreditNote({
        'references_document': widget.invoice.id,
        'reason': _reason,
        'with_gst': _withGst,
        'document_date': isoDay(_date),
        'lines': [
          for (int i = 0; i < chosen.length; i++)
            {
              'original_line_no': chosen[i].line.lineNo,
              'line_no': i + 1,
              'qty': chosen[i].qty.text.trim().isEmpty ? chosen[i].line.qty : chosen[i].qty.text.trim(),
              'unit_price': moneyInput(chosen[i].price.text) ?? chosen[i].line.unitPrice,
              'description': chosen[i].line.description,
            },
        ],
      });
      invalidateAccountingReads(ref.invalidate);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Credit note ${note?.number ?? ''} issued');
      Navigator.of(context).pop(note);
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
      title: 'Credit note',
      submitLabel: 'Issue credit note',
      busyLabel: 'Issuing…',
      busy: _busy,
      error: _error,
      errorAction: _error?.code == 'CN_CUTOFF_PASSED' ? 'Issue without GST' : null,
      onErrorAction: () => setState(() {
        _withGst = false;
        _error = null;
      }),
      submitEnabled: ref.watch(accPermProvider('acc_document')).create,
      onSubmit: _submit,
      children: [
        AccChoiceChips(
          label: 'Reason',
          required: true,
          options: const {'RETURN': 'Goods returned', 'VALUE_CORRECTION': 'Value correction'},
          selected: _reason,
          onSelected: (v) => setState(() => _reason = v),
        ),
        AccCheckRow(
          label: 'Reverse GST',
          value: _withGst,
          hint: 'Untick once the GST cut-off for the original invoice has passed.',
          onChanged: (v) => setState(() => _withGst = v),
        ),
        AccDateBox(label: 'Note date', value: _date, showIstHint: true, onChanged: (d) => setState(() => _date = d ?? _date)),
        Text(_reason == 'RETURN' ? 'What came back' : 'What to reduce',
            style: AppText.custom(size: 13, weight: FontWeight.w800, color: AppColors.textPrimary)),
        for (final l in _lines) _lineRow(l),
        if (_taxableHint > 0)
          Text('About ${formatMoneyStr(toMoneyStr(_taxableHint))} before tax — the server works out the exact note.',
              style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
        const AccInfoBanner(
          'The note first reduces what the customer still owes; anything beyond that is kept as a customer credit.',
        ),
      ],
    );
  }

  Widget _lineRow(_LineDraft l) {
    return Container(
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: l.on ? AppColors.blueSubtle : AppColors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: l.on ? const Color(0xFFA6D1FF) : AppColors.borderCardSoft),
      ),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => l.on = !l.on),
            child: Row(
              children: [
                CrmCheckBox(done: l.on, onTap: () => setState(() => l.on = !l.on), size: 22),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(l.line.description.isEmpty ? 'Line ${l.line.lineNo}' : l.line.description,
                      style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
                Text('${_LineDraft._trim(l.line.qty)} × ${formatMoneyStr(l.line.unitPrice)}',
                    style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textMuted)),
              ],
            ),
          ),
          if (l.on) ...[
            SizedBox(height: 10.h),
            Row(
              children: [
                Expanded(
                  child: AccInput(
                    label: _reason == 'RETURN' ? 'Qty returned' : 'Qty',
                    controller: l.qty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SizedBox(width: 9.w),
                Expanded(
                  child: MoneyField(
                    label: _reason == 'RETURN' ? 'Unit price' : 'Reduce per unit',
                    controller: l.price,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
