import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/accounting_providers.dart';
import '../../domain/entities/acc_document.dart';
import '../components/acc_widgets.dart';

/// The server's print payload for one document.
final _printProvider = FutureProvider.autoDispose.family<InvoicePrint, String>(
  (ref, id) => ref.watch(accountingRepositoryProvider).renderContext(id),
);

/// Share / print (plan §4.6).
///
/// The backend has no PDF yet (`documents/{id}/pdf/` is a 501, handover
/// §12.7), and the app carries no PDF or share-sheet package. So this renders
/// the invoice from `render-context` as a page the user can read or
/// screenshot, and shares its summary as text — copied, or handed to email or
/// WhatsApp through the device. State names come from the states lookup and
/// the HSN summary is added up from the lines, both on the client, as §12.7
/// asks.
class AccDocumentPrintScreen extends ConsumerWidget {
  const AccDocumentPrintScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final async = ref.watch(_printProvider(id));
    final stateName = ref.watch(gstStateNameProvider);
    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(section: 'Share', name: async.valueOrNull?.s('invoice_number'), onBack: () => context.pop()),
          Expanded(
            child: AccountingGate(
              child: async.when(
                loading: () => const DetailSkeleton(),
                error: (e, _) => ErrorState.forError(
                  e is AppError ? e : const AppError(type: AppErrorType.unknown, message: 'Could not load.'),
                  onRetry: () => ref.invalidate(_printProvider(id)),
                ),
                data: (p) => ListView(
                  padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
                  children: [
                    const AccInfoBanner('A PDF is not available yet. Share the summary below, or take a screenshot of the invoice.'),
                    SizedBox(height: 14.h),
                    _Paper(print: p, stateName: stateName),
                  ],
                ),
              ),
            ),
          ),
          if (async.valueOrNull != null) _shareBar(context, ref, async.value!),
        ],
      ),
    );
  }

  Widget _shareBar(BuildContext context, WidgetRef ref, InvoicePrint p) {
    final text = _summary(p);
    final subject = '${p.s('doc_type_label').isEmpty ? 'Invoice' : p.s('doc_type_label')} ${p.s('invoice_number')}';
    Future<void> open(Uri uri) async {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) ref.read(toastProvider.notifier).showError('No app on this device can open that');
    }

    return StickyActionBar(children: [
      Expanded(
        child: PrimaryButton(
          label: 'Copy',
          icon: PhosphorIconsRegular.copy,
          ghost: true,
          height: 48,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: text));
            ref.read(toastProvider.notifier).show('Invoice summary copied');
          },
        ),
      ),
      SizedBox(width: 10.w),
      Expanded(
        child: PrimaryButton(
          label: 'Email',
          icon: PhosphorIconsRegular.envelopeSimple,
          ghost: true,
          height: 48,
          onTap: () => open(Uri(
            scheme: 'mailto',
            path: p.s('recipient_email'),
            query: _query({'subject': subject, 'body': text}),
          )),
        ),
      ),
      SizedBox(width: 10.w),
      Expanded(
        child: PrimaryButton(
          label: 'WhatsApp',
          icon: PhosphorIconsRegular.whatsappLogo,
          height: 48,
          onTap: () => open(Uri.https('wa.me', '/', {'text': text})),
        ),
      ),
    ]);
  }

  /// `mailto:` wants `%20`, not `+`, for spaces — [Uri.queryParameters] would
  /// encode them as `+`, which mail apps show literally.
  static String _query(Map<String, String> params) =>
      params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');

  static String _summary(InvoicePrint p) {
    final b = StringBuffer()
      ..writeln('${p.s('doc_type_label').isEmpty ? 'Invoice' : p.s('doc_type_label')} ${p.s('invoice_number')}')
      ..writeln('Date: ${formatApiDay(p.s('invoice_date'))}');
    if (p.s('due_date').isNotEmpty) b.writeln('Due: ${formatApiDay(p.s('due_date'))}');
    b
      ..writeln('From: ${p.s('supplier_name')}${p.s('supplier_gstin').isEmpty ? '' : ' (GSTIN ${p.s('supplier_gstin')})'}')
      ..writeln('To: ${p.s('recipient_name')}${p.s('recipient_gstin').isEmpty ? '' : ' (GSTIN ${p.s('recipient_gstin')})'}')
      ..writeln()
      ..writeln('Taxable: ${formatMoneyStr(p.s('taxable_total'))}');
    for (final h in const [('CGST', 'tax_cgst'), ('SGST', 'tax_sgst'), ('IGST', 'tax_igst'), ('Cess', 'tax_cess')]) {
      if (!moneyIsZero(p.s(h.$2))) b.writeln('${h.$1}: ${formatMoneyStr(p.s(h.$2))}');
    }
    b.writeln('Total: ${formatMoneyStr(p.s('grand_total'))}');
    if (p.s('grand_total_in_words').isNotEmpty) b.writeln(p.s('grand_total_in_words'));
    return b.toString().trim();
  }
}

/// The invoice itself, laid out like a printed page on a white card.
class _Paper extends StatelessWidget {
  const _Paper({required this.print, required this.stateName});

  final InvoicePrint print;
  final String Function(String?) stateName;

  @override
  Widget build(BuildContext context) {
    final p = print;
    final lines = p.lines;
    // HSN summary — not in the payload, so added up here (§12.7).
    final hsn = <String, double>{};
    for (final l in lines) {
      final k = '${l['hsn_sac'] ?? '—'}';
      hsn[k] = (hsn[k] ?? 0) + moneyNum(l['taxable']);
    }
    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.all(18.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.s('supplier_legal_name').isEmpty ? p.s('supplier_name') : p.s('supplier_legal_name'),
                        style: AppText.custom(size: 16, weight: FontWeight.w800, color: AppColors.textPrimary)),
                    if (p.s('supplier_address').isNotEmpty) _small(p.s('supplier_address')),
                    if (p.s('supplier_gstin').isNotEmpty) _small('GSTIN ${p.s('supplier_gstin')}'),
                    if (p.s('supplier_pan').isNotEmpty) _small('PAN ${p.s('supplier_pan')}'),
                    if (p.s('supplier_state_code').isNotEmpty) _small(stateName(p.s('supplier_state_code'))),
                  ],
                ),
              ),
              SizedBox(width: 10.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text((p.s('doc_type_label').isEmpty ? 'Tax invoice' : p.s('doc_type_label')).toUpperCase(),
                      style: AppText.custom(size: 11, weight: FontWeight.w800, color: AppColors.navy, letterSpacing: 0.6)),
                  SizedBox(height: 3.h),
                  Text(p.s('invoice_number'), style: AppText.custom(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
                  _small(formatApiDay(p.s('invoice_date'))),
                ],
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 14)),
          Text('BILL TO', style: _label),
          SizedBox(height: 4.h),
          Text(p.s('recipient_organization').isEmpty ? p.s('recipient_name') : p.s('recipient_organization'),
              style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
          if (p.s('recipient_organization').isNotEmpty && p.s('recipient_name').isNotEmpty) _small(p.s('recipient_name')),
          if (p.s('recipient_address').isNotEmpty) _small(p.s('recipient_address')),
          if (p.s('recipient_gstin').isNotEmpty) _small('GSTIN ${p.s('recipient_gstin')}'),
          if (p.s('place_of_supply_state_code').isNotEmpty) _small('Place of supply: ${stateName(p.s('place_of_supply_state_code'))}'),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 14)),
          for (final l in lines) _line(l),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 10)),
          _total('Taxable value', p.s('taxable_total')),
          for (final h in const [('CGST', 'tax_cgst'), ('SGST', 'tax_sgst'), ('IGST', 'tax_igst'), ('Cess', 'tax_cess')])
            if (!moneyIsZero(p.s(h.$2))) _total(h.$1, p.s(h.$2)),
          if (!moneyIsZero(p.s('round_off'))) _total('Round-off', p.s('round_off')),
          SizedBox(height: 6.h),
          Row(
            children: [
              Expanded(child: Text('Total', style: AppText.custom(size: 15, weight: FontWeight.w800, color: AppColors.textPrimary))),
              Text(formatMoneyStr(p.s('grand_total')),
                  style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary)),
            ],
          ),
          if (p.s('grand_total_in_words').isNotEmpty) ...[
            SizedBox(height: 4.h),
            Text(p.s('grand_total_in_words'), style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.textMuted)),
          ],
          if (hsn.length > 1 || (hsn.length == 1 && hsn.keys.first != '—')) ...[
            const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 14)),
            Text('HSN / SAC SUMMARY', style: _label),
            SizedBox(height: 4.h),
            for (final e in hsn.entries) _total(e.key, toMoneyStr(e.value)),
          ],
          if (p.s('narration').isNotEmpty || p.s('terms').isNotEmpty) ...[
            const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 14)),
            if (p.s('narration').isNotEmpty) _small(p.s('narration')),
            if (p.s('terms').isNotEmpty) ...[
              SizedBox(height: 6.h),
              Text('TERMS', style: _label),
              _small(p.s('terms')),
            ],
          ],
        ],
      ),
    );
  }

  static TextStyle get _label =>
      AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.5);

  Widget _small(String t) => Padding(
        padding: EdgeInsets.only(top: 2.h),
        child: Text(t, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted, height: 1.4)),
      );

  Widget _total(String label, String value) => Padding(
        padding: EdgeInsets.symmetric(vertical: 3.h),
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted))),
            Text(formatMoneyStr(value), style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
          ],
        ),
      );

  Widget _line(Map<String, dynamic> l) {
    final meta = [
      if ((l['hsn_sac'] ?? '').toString().isNotEmpty) 'HSN ${l['hsn_sac']}',
      if (l['rate_pct'] != null) '${l['rate_pct']}%',
    ].join(' · ');
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${l['description'] ?? ''}', style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary)),
                Text('${l['qty'] ?? ''} × ${formatMoneyStr(l['unit_price'])}${meta.isEmpty ? '' : ' · $meta'}',
                    style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ),
          ),
          Text(formatMoneyStr(l['taxable']), style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
