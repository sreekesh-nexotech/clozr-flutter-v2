import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_text_styles.dart';
import '../../../../../core/network/app_error.dart';
import '../../../../../core/utils/inr_format.dart';
import '../../../../../core/widgets/app_bottom_sheet.dart';
import '../../../application/providers/quote_detail_providers.dart';
import '../../../application/quote_lifecycle.dart';
import '../finance_widgets.dart';

/// Webapp `money`: `₹2,50,640` (paise only when there are some).
String quoteMoney(Object? value) {
  if (value == null || '$value'.trim().isEmpty || '$value' == 'null') return '—';
  final n = parseAmount(value);
  final whole = (n * 100).round() % 100 == 0;
  final abs = n.abs();
  final parts = (whole ? abs.round().toString() : abs.toStringAsFixed(2)).split('.');
  final digits = parts[0];
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    grouped = '${groups.join(',')},$last3';
  }
  return '${n < 0 ? '-' : ''}₹$grouped${parts.length > 1 ? '.${parts[1]}' : ''}';
}

/// A small uppercase chip for the header ("REVISION 2", "LOCKED", …).
class QuoteHeadChip extends StatelessWidget {
  const QuoteHeadChip(this.label, {super.key, this.icon, this.color = AppColors.navy, this.bg = AppColors.tintNavy});
  final String label;
  final IconData? icon;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6.r)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 10.sp, color: color), SizedBox(width: 4.w)],
          Text(label, style: AppText.custom(size: 10.5, weight: FontWeight.w800, color: color, letterSpacing: 0.3)),
        ]),
      );
}

/// A tinted notice strip with optional action buttons and dismiss.
class QuoteNotice extends StatelessWidget {
  const QuoteNotice({
    super.key,
    required this.icon,
    required this.text,
    this.title,
    this.actions = const [],
    this.onDismiss,
    this.tone = AppColors.warningDeep,
    this.bg = AppColors.tintAmber,
  });

  final IconData icon;
  final String? title;
  final String text;
  final List<(String, VoidCallback)> actions;
  final VoidCallback? onDismiss;
  final Color tone;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(13.w, 12.h, 10.w, 12.h),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12.r)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16.sp, color: tone),
        SizedBox(width: 9.w),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(
              style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textSecondary, height: 1.45),
              children: [
                if (title != null)
                  TextSpan(text: '$title ', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                TextSpan(text: text),
              ],
            )),
            if (actions.isNotEmpty) ...[
              SizedBox(height: 9.h),
              Wrap(spacing: 8.w, runSpacing: 6.h, children: [
                for (final a in actions)
                  GestureDetector(
                    onTap: a.$2,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 11.w, vertical: 7.h),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(9.r),
                        border: Border.all(color: AppColors.borderInput),
                      ),
                      child: Text(a.$1, style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.navy)),
                    ),
                  ),
              ]),
            ],
          ]),
        ),
        if (onDismiss != null)
          GestureDetector(
            onTap: onDismiss,
            child: Padding(
              padding: EdgeInsets.only(left: 6.w),
              child: Icon(PhosphorIconsRegular.x, size: 15.sp, color: AppColors.textMuted),
            ),
          ),
      ]),
    );
  }
}

/// A label ⋯ value row that opens an editor on tap when [onTap] is set
/// (pencil shown), or says why it is locked ([lockedReason]).
class QuoteInfoRow extends StatelessWidget {
  const QuoteInfoRow({super.key, required this.label, required this.value, this.onTap, this.trailing, this.last = false, this.lockedReason, this.onLocked});

  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool last;
  final String? lockedReason;
  final void Function(String)? onLocked;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      decoration: last ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
      child: Row(children: [
        Text(label, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
        SizedBox(width: 14.w),
        Expanded(
          child: trailing ??
              Text(value,
                  textAlign: TextAlign.right,
                  style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
        ),
        if (onTap != null) ...[
          SizedBox(width: 6.w),
          Icon(PhosphorIconsRegular.pencilSimple, size: 13.sp, color: AppColors.textPlaceholder),
        ] else if (lockedReason != null) ...[
          SizedBox(width: 6.w),
          Icon(PhosphorIconsRegular.lockSimple, size: 13.sp, color: AppColors.textPlaceholder),
        ],
      ]),
    );
    final tap = onTap ?? (lockedReason != null && onLocked != null ? () => onLocked!(lockedReason!) : null);
    return tap == null ? row : GestureDetector(behavior: HitTestBehavior.opaque, onTap: tap, child: row);
  }
}

/// One status choice in [showQuoteStatusPicker].
class QuoteStatusChoice {
  const QuoteStatusChoice({required this.id, required this.name, required this.color, this.disabledReason});
  final String id;
  final String name;
  final Color color;

  /// Non-null: shown greyed with this reason (Accepted while blocked).
  final String? disabledReason;
}

/// The status picker — like the shared status sheet, plus greyed options.
Future<String?> showQuoteStatusPicker(BuildContext context, {required List<QuoteStatusChoice> options, required String currentId}) =>
    showClozrSheet<String>(
      context: context,
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        const SheetHeader(title: 'Quote status'),
        Padding(
          padding: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 24.h),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final o in options)
              Opacity(
                opacity: o.disabledReason == null ? 1 : 0.5,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: o.disabledReason == null ? () => Navigator.of(ctx).pop(o.id) : null,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 13.h),
                    decoration: BoxDecoration(
                      color: o.id == currentId ? const Color(0xFFF6F8FB) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Row(children: [
                      Container(width: 11.w, height: 11.w, decoration: BoxDecoration(color: o.color, shape: BoxShape.circle)),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(o.name, style: AppText.custom(size: 14.5, weight: FontWeight.w600, color: AppColors.textPrimary)),
                          if (o.disabledReason != null)
                            Text(o.disabledReason!, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                        ]),
                      ),
                      if (o.id == currentId) Icon(PhosphorIconsBold.check, size: 18.sp, color: AppColors.success),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );

/// "Payment instructions" — bank / UPI details and the UPI QR printed on the quote.
class QuotePaymentInstructionsCard extends ConsumerWidget {
  const QuotePaymentInstructionsCard({super.key, required this.quotationId, required this.canConfigure});
  final String quotationId;
  final bool canConfigure;

  Widget _row(String k, String v) => Padding(
        padding: EdgeInsets.symmetric(vertical: 3.h),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 100.w, child: Text(k, style: AppText.caption())),
          Expanded(child: Text(v, style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textPrimary))),
        ]),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(quotePaymentInstructionsProvider(quotationId));
    Widget body;
    if (async.isLoading) {
      body = Padding(padding: EdgeInsets.symmetric(vertical: 8.h), child: const LinearProgressIndicator(minHeight: 2));
    } else if (async.hasError) {
      body = Text(async.error is AppError ? (async.error as AppError).bareMessage : '${async.error}',
          style: AppText.caption(color: AppColors.error));
    } else if (async.value == null) {
      body = Text(
          '$kNoPaymentInstructions${canConfigure ? ' Add bank and UPI details under Settings › Quotes / Invoices › Quote settings.' : ''}',
          style: AppText.caption());
    } else {
      final pi = async.value!;
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final b in pi.bankAccounts) ...[
          if (b.bankName.isNotEmpty) _row('Bank', b.bankName),
          if (b.accountName.isNotEmpty) _row('Account name', b.accountName),
          if (b.accountNumber.isNotEmpty) _row('Account no.', b.accountNumber),
          if (b.ifsc.isNotEmpty) _row('IFSC', b.ifsc),
          if (b.branch.isNotEmpty) _row('Branch', b.branch),
          SizedBox(height: 8.h),
        ],
        if (pi.upiId.isNotEmpty) _row('UPI ID', pi.upiId),
        if (pi.paymentLink.isNotEmpty) _row('Payment link', pi.paymentLink),
        if (pi.upiQrBase64.isNotEmpty) ...[
          SizedBox(height: 10.h),
          Center(
            child: Column(children: [
              Container(
                decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: AppColors.borderCardSoft)),
                padding: EdgeInsets.all(6.r),
                child: Image.memory(base64Decode(pi.upiQrBase64),
                    width: 148.w, height: 148.w, filterQuality: FilterQuality.none, gaplessPlayback: true),
              ),
              SizedBox(height: 6.h),
              Text.rich(TextSpan(style: AppText.caption(), children: [
                const TextSpan(text: 'Scan to pay '),
                TextSpan(text: quoteMoney(pi.amount), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ])),
              if (pi.note.isNotEmpty) Text('Note: ${pi.note}', style: AppText.caption()),
            ]),
          ),
        ],
      ]);
    }
    return FinanceCard(title: 'Payment instructions', child: body);
  }
}

/// "Terms & conditions" — the clause list (frozen once sent), else the
/// legacy free text.
class QuoteTermsCard extends StatelessWidget {
  const QuoteTermsCard({super.key, required this.row});
  final Map<String, dynamic> row;

  static String _plain(String html) => html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|li|div|h\d)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  @override
  Widget build(BuildContext context) {
    final clauses = [for (final c in (row['clauses'] is List ? row['clauses'] as List : const [])) if (c is Map) c];
    final terms = '${row['terms_and_conditions'] ?? ''}'.trim();
    if (clauses.isEmpty && (terms.isEmpty || terms == 'null')) return const SizedBox.shrink();
    final allFrozen = clauses.isNotEmpty && clauses.every((c) => c['is_frozen'] == true);
    return Padding(
      padding: EdgeInsets.only(top: 14.h),
      child: FinanceCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Terms & conditions', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
            if (allFrozen) ...[SizedBox(width: 8.w), const QuoteHeadChip('FROZEN AT SEND', icon: PhosphorIconsBold.lock)],
          ]),
          SizedBox(height: 8.h),
          if (clauses.isEmpty)
            Text(terms, style: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textLabelAlt, height: 1.55))
          else
            for (var i = 0; i < clauses.length; i++)
              Container(
                padding: EdgeInsets.symmetric(vertical: 10.h),
                decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF3F4F5)))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 6.w, runSpacing: 4.h, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('${i + 1}. ${'${clauses[i]['title'] ?? ''}'.trim().isEmpty ? 'Untitled clause' : clauses[i]['title']}',
                        style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    if (clauses[i]['is_mandatory'] == true)
                      const QuoteHeadChip('MANDATORY', color: AppColors.error, bg: AppColors.tintRed),
                    if (clauses[i]['is_adhoc'] == true)
                      const QuoteHeadChip('AD-HOC', color: AppColors.textMuted, bg: AppColors.tintGrey)
                    else if (clauses[i]['version'] != null)
                      QuoteHeadChip('V${clauses[i]['version']}', color: AppColors.textMuted, bg: AppColors.tintGrey),
                    if (clauses[i]['is_frozen'] == true && !allFrozen) const QuoteHeadChip('FROZEN', icon: PhosphorIconsBold.lock),
                  ]),
                  SizedBox(height: 5.h),
                  Text(_plain('${clauses[i]['body_html'] ?? ''}'),
                      style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textLabelAlt, height: 1.5)),
                ]),
              ),
        ]),
      ),
    );
  }
}
