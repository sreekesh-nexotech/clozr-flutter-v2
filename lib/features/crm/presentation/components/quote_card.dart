import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../application/providers/crm_catalog_providers.dart';
import '../../application/providers/crm_party_providers.dart';
import '../../application/providers/quotes_providers.dart';
import '../../domain/entities/quote.dart';
import '../../domain/entities/view_schema.dart';
import 'finance_widgets.dart';

/// A quote list row: file icon, who + "#id · N items", status pill + amount, and
/// a footer with the validity line and payment type.
///
/// Org-configurable via [schema] (`/quotations/quotations/schema/?view_type=
/// mobile`). Empty means "no opinion" and everything renders, so mock mode and a
/// failed fetch look as they did before.
///
/// `quotation_number` is never gated — it is the module's protected anchor
/// field, and the docs call it the only fixed column on the quote list.
class QuoteCard extends ConsumerWidget {
  const QuoteCard({
    super.key,
    required this.quote,
    required this.onTap,
    this.schema = ViewSchema.empty,
  });

  final Quote quote;
  final VoidCallback onTap;

  /// The org's configured column set for the mobile card.
  final ViewSchema schema;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The org's own status name and colour where the catalog knows it, so the
    // pill agrees with the tab the row sits under.
    final meta = quoteStatusMeta(quote, ref.watch(quoteStatusOptionsProvider));
    final lookup = ref.watch(crmPartyLookupProvider);
    final itemsLabel = '${quote.items.length} ${quote.items.length == 1 ? 'item' : 'items'}';
    final validLabel = quote.valid == '—' ? 'Draft — not issued' : 'Valid till ${quote.valid}';

    // Column names per `docs-backend/quotation-schema-and-list-view-api.md` §1.
    // `line_items` is a detail column rather than a list one — the doc's own Gaps
    // note says ITEMS has to be read off detail until the list seed is extended —
    // so the item count follows the title it shares a line with.
    // `lead` / `customer` are the names the schema actually uses for the linked
    // party; `customer_name` / `lead_name` are kept for layouts that flatten
    // them. Without the real two, an org that shows the party but no title
    // would have had its headline gated off.
    final showWho = schema.showsAny(
        const ['quotation_title', 'customer_name', 'lead_name', 'customer', 'lead']);
    final showStatus = schema.shows('status');
    final showAmount = schema.showsAny(const ['total_amount', 'currency']);
    final showValid = schema.shows('valid_until');
    final showPayType = schema.shows('payment_type');
    // Both halves of the footer gone means the hairline above it has nothing
    // left to separate.
    final showFooter = showValid || showPayType;
    final showSideColumn = showStatus || showAmount;

    return ClozrCard(
      radius: 14,
      padding: EdgeInsets.all(13.r),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconChip(icon: PhosphorIconsRegular.fileText),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showWho)
                      Text(quoteHeadline(quote, lookup),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    if (showWho) SizedBox(height: 3.h),
                    Text('#${quote.id} · $itemsLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                  ],
                ),
              ),
              if (showSideColumn) ...[
                SizedBox(width: 8.w),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (showStatus) StatusPill.meta(meta),
                    if (showAmount) ...[
                      SizedBox(height: 5.h),
                      Text(quote.amount, style: AppText.custom(size: 15, weight: FontWeight.w800, color: AppColors.textPrimary)),
                    ],
                  ],
                ),
              ],
            ],
          ),
          if (showFooter) ...[
            const ClozrDivider(margin: EdgeInsets.only(top: 11, bottom: 11)),
            Row(
              children: [
                Expanded(
                  child: showValid
                      ? Text(validLabel, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted))
                      : const SizedBox.shrink(),
                ),
                if (showPayType)
                  Text(quote.payType, style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
