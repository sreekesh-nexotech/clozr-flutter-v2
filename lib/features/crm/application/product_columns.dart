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
