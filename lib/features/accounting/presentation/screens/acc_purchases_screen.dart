import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/documents_providers.dart';
import '../components/acc_widgets.dart';
import '../components/document_card.dart';
import '../sheets/record_expense_sheet.dart';
import '../sheets/vendor_bill_sheet.dart';

final _purchaseTabProvider = StateProvider<String>((ref) => 'all');

/// Opens the "what are you recording" menu: an expense paid now, or a bill to
/// pay later.
Future<void> showPurchaseAddMenu(BuildContext context) => showActionMenu(
      context,
      title: 'Record a purchase',
      actions: [
        MenuAction(
          icon: PhosphorIconsRegular.shoppingCart,
          label: 'Record expense',
          sublabel: 'Already paid — posts the bill and the payment',
          onTap: () => showRecordExpenseSheet(context),
        ),
        MenuAction(
          icon: PhosphorIconsRegular.fileText,
          label: 'Vendor bill',
          sublabel: 'To pay later',
          onTap: () => showVendorBillSheet(context),
        ),
      ],
    );

/// Purchases (plan §4.9) — vendor bills, paged from the server like the
/// Invoices list, with the expense and bill forms behind the `+`.
class AccPurchasesScreen extends ConsumerWidget {
  const AccPurchasesScreen({super.key});

  static const _tabs = {'all': 'All', 'ISSUED': 'Posted', 'CANCELLED': 'Cancelled'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canCreate = ref.watch(accPermProvider('acc_purchase')).create;
    registerAdd(ref, canCreate ? AddAction(label: 'Record purchase', run: showPurchaseAddMenu) : null);
    final tab = ref.watch(_purchaseTabProvider);
    return Column(
      children: [
        ListHeader(
          children: [
            const AppHeaderBar(),
            SizedBox(height: 14.h),
            const HeaderHairline(),
            SizedBox(height: 14.h),
            ScreenTitleRow(
              title: 'Purchases',
              trailing: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.push(Routes.accVendors),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 8.h),
                  child: Row(
                    children: [
                      Icon(PhosphorIconsRegular.storefront, size: 18.sp, color: AppColors.textSecondary),
                      SizedBox(width: 5.w),
                      Text('Vendors', style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: 14.h),
            SizedBox(
              height: 40.h,
              child: TabChipRow(
                children: [
                  for (final e in _tabs.entries)
                    TabChip(
                      label: e.value,
                      active: tab == e.key,
                      onTap: () => ref.read(_purchaseTabProvider.notifier).state = e.key,
                    ),
                ],
              ),
            ),
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(child: AccountingGate(child: _list(context, ref, tab, canCreate))),
      ],
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, String tab, bool canCreate) {
    final q = DocQuery(docType: 'VENDOR_BILL', status: tab == 'all' ? null : tab);
    final state = ref.watch(docListProvider(q));
    final ctrl = ref.read(docListProvider(q).notifier);

    if (state.loading && state.items.isEmpty) return const ListSkeleton();
    if (state.error != null && state.items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [ErrorState.forError(state.error!, onRetry: ctrl.refresh)],
      );
    }
    if (state.items.isEmpty) {
      return AppRefresh(
        onRefresh: ctrl.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            EmptyState(
              icon: PhosphorIconsRegular.shoppingCart,
              title: 'No purchases yet',
              body: 'Vendor bills and expenses you record show up here.',
              ctaLabel: canCreate ? 'Record purchase' : null,
              ctaIcon: PhosphorIconsBold.plus,
              onCta: () => showPurchaseAddMenu(context),
            ),
          ],
        ),
      );
    }
    return AppRefresh(
      onRefresh: ctrl.refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels > n.metrics.maxScrollExtent - 400) ctrl.loadMore();
          return false;
        },
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
          itemCount: state.items.length + (state.hasMore ? 1 : 0),
          separatorBuilder: (_, __) => SizedBox(height: 10.h),
          itemBuilder: (context, i) {
            if (i >= state.items.length) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 12.h),
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.navy),
                  ),
                ),
              );
            }
            final d = state.items[i];
            return DocumentCard(
              document: d,
              onTap: () => context.push('${Routes.accDocumentDetail}?id=${d.id}'),
            );
          },
        ),
      ),
    );
  }
}
