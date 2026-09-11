import '../domain/entities/product.dart';
import '../domain/entities/view_schema.dart';
import 'schema_columns.dart';

/// Schema-configured columns for the Products card.
///
/// The card drew a fixed set of slots, so a column the org added outside that
/// set rendered as nothing. This gives it the same open-ended strip the Leads,
/// Customers, Tasks and Follow-ups cards have.

/// Columns the card draws itself.
const Set<String> kProductCardFrameColumns = {
  'product_name',
  'product_code',
  'price',
  'product_type',
  'is_active',
};

/// Columns the **detail** page renders in its own chrome, or must never print
/// raw — everything else in the org's detail layout goes into the Details card.
///
/// Three kinds of exclusion, all deliberate:
///
/// * **Already on screen.** The header owns the name, price and Active pill;
///   Description and the pricing / composition cards own the rest. A field
///   repeated inside Details reads as a rendering fault, not as emphasis.
/// * **Documented stubs.** `deals_count`, `lifetime_revenue` and `avg_per_deal`
///   are `0`/`null` until the quote↔product link lands (`products.md` §2,
///   known gap 4), and the doc says not to build UI implying they are real.
///   The performance card already hides itself when they are empty; a Details
///   row saying "Deals using this: 0" would put the same claim back.
/// * **Values that are not information.** `product_id` is a mandatory column
///   (§1) so it is *always* in the layout, and `product_type` is the category's
///   uuid — its label arrives separately as `product_type_name`, which is also
///   mandatory, so the category is never lost by skipping the id. Same
///   reasoning as [kNeverChipped] on the cards.
const Set<String> kProductDetailChromeColumns = {
  ...kNeverChipped,
  // Rendered by the page's own chrome.
  'product_name',
  'description',
  'is_active',
  'price',
  'tax_rate',
  'currency',
  // The composition card owns the package breakdown and its six totals (§7).
  'components',
  'adjustments',
  'components_subtotal_excl',
  'components_subtotal_incl',
  'adjustments_total_excl',
  'adjustments_total_incl',
  'computed_total_excl',
  'computed_total_incl',
  // Stubs pending the quote↔product link.
  'deals_count',
  'lifetime_revenue',
  'avg_per_deal',
  // Identifiers and storage paths.
  'product_id',
  'product_type',
  'image_url',
  'image_path',
};

/// Every renderable field on the product row — the org's configured columns
/// first, then anything else the payload carried.
///
/// Deliberately response-driven rather than schema-driven: the products payload
/// gains and loses fields as the backend changes (the pricing breakdown and the
/// deal rollups are on the row today but in no layout), and a field that does
/// not exist yet should render the day it appears rather than waiting for a
/// release.
List<({String label, String value})> productExtraColumns(
  Product product,
  ViewSchema schema,
) =>
    dynamicRowColumns(
      raw: product.raw,
      schema: schema,
      frame: kProductCardFrameColumns,
      text: (c) => productColumnText(product, c),
    );

String? productColumnText(Product product, ViewColumn column) {
  // The entity's own fields first — already formatted the way the card reads
  // them (`₹14,999` rather than `14999.000000`).
  final typed = switch (column.name) {
    'product_name' => product.name,
    'product_code' => product.code,
    'price' => product.price,
    'product_type' => product.cat,
    'hsn_code' || 'hsn' => product.hsn,
    'unit' => product.unit,
    _ => null,
  };
  if (typed != null && typed.trim().isNotEmpty) return typed.trim();
  return rawColumnText(product.raw, column);
}
