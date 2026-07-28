import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/invoices_providers.dart';
import '../../application/providers/payments_providers.dart';
import '../components/invoice_card.dart';
import '../components/mode_toggle.dart';
import '../components/payment_card.dart';
import '../components/saved_chip_row.dart';

/// Payments + Invoices — a mode toggle over two status-tab lists (payment rows
/// or invoice rows) sharing one header and search field.
class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  final _searchCtrl = TextEditingController();

  static const _savedViews = [
    SavedView('pod', 'Collections risk'),
    SavedView('phv', 'High value'),
  ];

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(paySearchProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(payModeProvider);
    final isPayments = mode == 'payments';
    final searchOpen = ref.watch(paySearchOpenProvider);
    final query = ref.watch(paySearchProvider);

    final allPayments = ref.watch(paymentsProvider).valueOrNull ?? const [];
    final allInvoices = ref.watch(invoicesProvider).valueOrNull ?? const [];
    final payTab = ref.watch(payTabProvider);
    final invTab = ref.watch(invTabProvider);
    final saved = ref.watch(paySavedProvider);

    const payTabKeys = ['all', 'paid', 'due', 'overdue', 'scheduled'];
    const invTabKeys = ['all', 'unpaid', 'partial', 'completed'];

    return Column(
      children: [
        ListHeader(
          children: [
            const AppHeaderBar(),
            SizedBox(height: 14.h),
            const HeaderHairline(),
            SizedBox(height: 14.h),
            ScreenTitleRow(
              title: 'Payments',
              hasSearchQuery: query.isNotEmpty,
              onSearch: () => ref.read(paySearchOpenProvider.notifier).state = !searchOpen,
              onFilter: () => ref.read(toastProvider.notifier).show('Filters — full CRM filter engine'),
            ),
            SizedBox(height: 14.h),
            ModeToggle(
              options: const [
                ModeOption(PhosphorIconsRegular.wallet, 'Payments'),
                ModeOption(PhosphorIconsRegular.receipt, 'Invoices'),
              ],
              selectedIndex: isPayments ? 0 : 1,
              onChanged: (i) => ref.read(payModeProvider.notifier).state = i == 0 ? 'payments' : 'invoices',
            ),
            SizedBox(height: 14.h),
            if (searchOpen) ...[
              SearchField(
                controller: _searchCtrl,
                hint: 'Search invoices, customer, quote…',
                onChanged: (v) => ref.read(paySearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(paySearchProvider.notifier).state = '';
                  ref.read(paySearchOpenProvider.notifier).state = false;
                },
              ),
              SizedBox(height: 14.h),
            ],
            SizedBox(
              height: 40.h,
              child: TabChipRow(
                children: isPayments
                    ? [
                        for (final k in payTabKeys)
                          TabChip(
                            label: '${k == 'all' ? 'All' : StatusMeta$.payment[k]!.label} (${payTabCount(allPayments, k)})',
                            active: payTab == k,
                            onTap: () => ref.read(payTabProvider.notifier).state = k,
                          ),
                      ]
                    : [
                        for (final k in invTabKeys)
                          TabChip(
                            label: '${k == 'all' ? 'All' : StatusMeta$.invoice[k]!.label} (${invTabCount(allInvoices, k)})',
                            active: invTab == k,
                            onTap: () => ref.read(invTabProvider.notifier).state = k,
                          ),
                      ],
              ),
            ),
            if (isPayments) ...[
              SizedBox(height: 12.h),
              SavedChipRow(
                views: _savedViews,
                active: saved,
                onToggle: (key) {
                  final next = {...saved};
                  next.contains(key) ? next.remove(key) : next.add(key);
                  ref.read(paySavedProvider.notifier).state = next;
                },
                onClear: () => ref.read(paySavedProvider.notifier).state = {},
              ),
            ],
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(child: isPayments ? _paymentsList(context, ref) : _invoicesList(context, ref)),
      ],
    );
  }

  Widget _paymentsList(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(visiblePaymentsProvider);
    if (visible.isEmpty) {
      return ListView(
        children: const [
          EmptyState(
            icon: PhosphorIconsRegular.wallet,
            title: 'No payments found',
            body: 'Try a different status or clear filters.',
          ),
        ],
      );
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
      itemCount: visible.length,
      separatorBuilder: (_, __) => SizedBox(height: 10.h),
      itemBuilder: (context, i) {
        final payment = visible[i];
        return PaymentCard(
          payment: payment,
          onTap: () => context.push('${Routes.paymentDetail}?id=${payment.id}'),
        );
      },
    );
  }

  Widget _invoicesList(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(visibleInvoicesProvider);
    return ListView(
      padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
      children: [
        _invoiceBanner(),
        SizedBox(height: 10.h),
        if (visible.isEmpty)
          const EmptyState(
            icon: PhosphorIconsRegular.receipt,
            title: 'No invoices found',
            body: 'Try a different status or clear filters.',
          )
        else
          for (int i = 0; i < visible.length; i++) ...[
            if (i > 0) SizedBox(height: 10.h),
            InvoiceCard(
              invoice: visible[i],
              onTap: () => context.push('${Routes.invoiceDetail}?id=${visible[i].id}'),
            ),
          ],
      ],
    );
  }

  Widget _invoiceBanner() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 11.h),
      decoration: BoxDecoration(color: AppColors.blueSubtle, borderRadius: BorderRadius.circular(12.r)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsRegular.info, size: 16.sp, color: AppColors.blueBright),
          SizedBox(width: 9.w),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'An invoice is generated when a quote is accepted. It groups that customer\'s installments and rolls up to ',
                style: AppText.custom(size: 12, weight: FontWeight.w500, color: _bannerText, height: 1.5),
                children: [
                  TextSpan(text: 'Completed', style: AppText.custom(size: 12, weight: FontWeight.w700, color: _bannerText)),
                  TextSpan(text: ' once every installment settles.', style: AppText.custom(size: 12, weight: FontWeight.w500, color: _bannerText)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The prototype's `#35507C` info-banner text — no design token exists for it.
const Color _bannerText = Color(0xFF35507C);
