import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/products_providers.dart';
import '../../domain/entities/product.dart';
import '../components/crm_async.dart';
import '../components/finance_widgets.dart';

/// Product detail — header (name + active toggle + edit), description,
/// performance, pricing, details and notes.
class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final async = ref.watch(productsProvider);

    Widget scaffold(Widget child) => Container(
          color: AppColors.bgDetail,
          child: Column(
            children: [
              DetailAppBar(section: 'Product', onBack: () => context.pop()),
              Expanded(child: child),
            ],
          ),
        );

    return async.when(
      loading: () => scaffold(const DetailSkeleton()),
      error: (e, _) => scaffold(
        ErrorState.forError(crmAppError(e), onRetry: () => ref.invalidate(productsProvider)),
      ),
      data: (_) => _buildProduct(context, ref, id, scaffold),
    );
  }

  Widget _buildProduct(
    BuildContext context,
    WidgetRef ref,
    String id,
    Widget Function(Widget) scaffold,
  ) {
    final product = ref.watch(productByIdProvider(id));
    if (product == null) {
      return scaffold(const EmptyState(
        icon: PhosphorIconsRegular.package,
        title: 'Product not found',
        body: 'This catalog item may have been removed or you no longer have access to it.',
      ));
    }

    final notes = [
      for (final n in product.notes)
        NoteEntry(initials: _initials(n.author), author: n.author, time: n.time, body: n.body),
    ];

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: 'Product',
            name: product.name,
            onBack: () => context.pop(),
            trailing: DetailIconAction(
              icon: PhosphorIconsBold.dotsThreeVertical,
              onTap: () => ref.read(toastProvider.notifier).show('Product actions'),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
              children: [
                _headerCard(ref, product),
                SizedBox(height: 14.h),
                FinanceCard(
                  title: 'Description',
                  child: Text(_desc(product),
                      style: AppText.custom(size: 14, weight: FontWeight.w500, color: AppColors.textLabelAlt, height: 1.6)),
                ),
                SizedBox(height: 14.h),
                _performanceCard(product),
                SizedBox(height: 14.h),
                _pricingCard(product),
                SizedBox(height: 14.h),
                FinanceCard(
                  title: 'Details',
                  child: Column(
                    children: [
                      MetaRow(label: 'Category', value: product.cat),
                      MetaRow(label: 'Billing unit', value: product.unit),
                      MetaRow(label: 'SKU / code', value: product.id),
                      MetaRow(label: 'HSN / SAC', value: product.hsn, last: true),
                    ],
                  ),
                ),
                SizedBox(height: 14.h),
                NotesCard(
                  title: 'Notes',
                  countLabel: '${product.notes.length} ${product.notes.length == 1 ? 'note' : 'notes'}',
                  notes: notes,
                  onSend: (_) => ref.read(toastProvider.notifier).show('Note added'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCard(WidgetRef ref, Product product) {
    return FinanceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconChip(icon: productCategoryIcon(product.cat), size: 46, radius: 13, iconSize: 22),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8.w,
                      runSpacing: 4.h,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(product.name,
                            style: AppText.custom(size: 18, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                        product.active
                            ? const StatusPill(label: 'Active', color: AppColors.success)
                            : const StatusPill(label: 'Inactive', color: AppColors.error),
                      ],
                    ),
                    SizedBox(height: 3.h),
                    Text('${product.id} · ${product.cat}',
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    SizedBox(height: 3.h),
                    Text('# HSN/SAC ${product.hsn}',
                        style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                  ],
                ),
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 15)),
          Row(
            children: [
              Expanded(
                child: Text('Catalog item · used across quotes & deals',
                    style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
              ),
              SizedBox(width: 10.w),
              _pillButton(
                icon: PhosphorIconsRegular.power,
                label: product.active ? 'Deactivate' : 'Activate',
                onTap: () => ref.read(toastProvider.notifier)
                    .show(product.active ? 'Product deactivated' : 'Product activated'),
              ),
              SizedBox(width: 8.w),
              _pillButton(
                icon: PhosphorIconsRegular.pencilSimple,
                label: 'Edit',
                onTap: () => ref.read(toastProvider.notifier).show('Edit product — coming soon'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pillButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38.h,
        padding: EdgeInsets.symmetric(horizontal: 13.w),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: const Color(0xFFE6E7EA)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15.sp, color: AppColors.textSecondary),
            SizedBox(width: 6.w),
            Text(label, style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textBody)),
          ],
        ),
      ),
    );
  }

  Widget _performanceCard(Product product) {
    final perf = <(String, String)>[
      ('${product.deals}', 'Deals using this'),
      (product.revenue, 'Lifetime revenue'),
      (product.avg, 'Avg. per deal'),
    ];
    return FinanceCard(
      title: 'Performance',
      child: Padding(
        padding: EdgeInsets.only(top: 6.h),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final p in perf)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.$1, style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.blueBright, letterSpacing: -0.3)),
                    SizedBox(height: 3.h),
                    Text(p.$2, style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textMuted, height: 1.35)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pricingCard(Product product) {
    final unitBare = product.unit.replaceFirst('per ', '');
    return FinanceCard(
      title: 'Pricing',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MetaRow(label: 'Unit price ($unitBare)', value: product.price),
          MetaRow(label: 'GST rate', value: '${product.gst}%'),
          MetaRow(label: 'GST amount', value: product.gstAmt, last: true),
          Padding(
            padding: EdgeInsets.only(top: 12.h, bottom: 2.h),
            child: Row(
              children: [
                Text('Gross unit price', style: AppText.custom(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
                const Spacer(),
                Text(product.gross, style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
              ],
            ),
          ),
          SizedBox(height: 10.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            decoration: BoxDecoration(color: AppColors.bgScreen, borderRadius: BorderRadius.circular(10.r)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(PhosphorIconsRegular.info, size: 14.sp, color: AppColors.textPlaceholder),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    'Price changes apply to new quotes only. Existing quotes keep the name and price captured when they were generated.',
                    style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted2, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _desc(Product p) =>
      p.desc ??
      '${p.name} delivered by Kairali Interior Works. Billed ${p.unit} at ${p.price} + 18% GST.';

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }
}
