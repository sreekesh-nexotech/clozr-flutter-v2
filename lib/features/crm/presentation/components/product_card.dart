import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../application/providers/products_providers.dart';
import '../../application/product_columns.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/view_schema.dart';
import 'finance_widgets.dart';

/// A catalog list row: category icon, name + "SKU · HSN", Active/Inactive pill +
/// price, and a footer with the category dot, unit/GST and deals/revenue.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.schema = ViewSchema.empty,
  });
  final Product product;
  final VoidCallback onTap;

  /// The org's mobile card layout. Empty means "no opinion" — the fixed slots
  /// render and no extra chips are drawn.
  final ViewSchema schema;

  @override
  Widget build(BuildContext context) {
    final catColor = productCategoryColor(product.cat);
    // Everything else the org made visible, in its order — the card no longer
    // renders only the slots it was built with.
    final extras = productExtraColumns(product, schema);

    return ClozrCard(
      radius: 14,
      padding: EdgeInsets.all(13.r),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconChip(icon: productCategoryIcon(product.cat)),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 3.h),
                    // SKU and HSN are both optional; the `product_id` uuid is
                    // never a stand-in for either.
                    Text([
                      if (product.code.isNotEmpty) product.code,
                      if (product.hsn.isNotEmpty) 'HSN ${product.hsn}',
                    ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  product.active
                      ? const StatusPill(label: 'Active', color: AppColors.success)
                      : const StatusPill(label: 'Inactive', color: AppColors.error),
                  SizedBox(height: 5.h),
                  Text(product.price, style: AppText.custom(size: 15, weight: FontWeight.w800, color: AppColors.textPrimary)),
                ],
              ),
            ],
          ),
          // A package carries no category, billing unit or rate of its own, so
          // the footer had a category dot next to an empty line. Nothing to
          // say, nothing to draw.
          if (_hasFooter(product)) ...[
            const ClozrDivider(margin: EdgeInsets.only(top: 11, bottom: 11)),
            Row(
            children: [
              Container(width: 8.w, height: 8.w, decoration: BoxDecoration(color: catColor, shape: BoxShape.circle)),
              SizedBox(width: 8.w),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    text: product.cat,
                    style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt),
                    children: [
                      TextSpan(
                        // The rate the row carries. This was the literal
                        // "18% GST" on every card, so a 0%-rated item — which
                        // is every product on a live catalog — was shown as
                        // taxed. The unit is dropped when the row has none,
                        // rather than printing a dangling separator.
                        text: '${product.unit.isEmpty ? '' : ' · ${product.unit}'}'
                            '${product.gstKnown ? ' · ${product.gst}% GST' : ''}',
                        style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Usage figures only when something backs them. No endpoint
              // reports deals or revenue per catalog item, so every live row
              // printed "0 deals · ₹0" — which reads as "never sold", not as
              // "not known".
              if (product.deals > 0 || product.revNum > 0) ...[
                SizedBox(width: 8.w),
                Text('${product.deals} deals · ${product.revenue}',
                    style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ],
            ),
          ],
          if (extras.isNotEmpty) ...[
            SizedBox(height: 10.h),
            Wrap(
              spacing: 6.w,
              runSpacing: 6.h,
              children: [for (final e in extras) _chip(e.label, e.value)],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: AppColors.bgChipGrey,
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: RichText(
        text: TextSpan(children: [
          TextSpan(
            text: '$label ',
            style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textMuted),
          ),
          TextSpan(
            text: value,
            style: AppText.custom(size: 11.5, weight: FontWeight.w700, color: AppColors.textPrimary),
          ),
        ]),
      ),
    );
  }

  /// Whether the footer row would carry anything at all.
  static bool _hasFooter(Product p) =>
      p.cat.isNotEmpty ||
      p.unit.isNotEmpty ||
      p.gstKnown ||
      p.deals > 0 ||
      p.revNum > 0;
}
