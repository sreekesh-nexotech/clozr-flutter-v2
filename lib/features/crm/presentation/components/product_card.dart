import 'package:flutter/material.dart';
import '../../application/product_columns.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/view_schema.dart';
import 'schema_mobile_card.dart';

/// The Products (and Packages) list card — the webapp's **View Settings ›
/// Products › Mobile view** card, the same [SchemaMobileCard] the Leads,
/// Customers, Tasks and Follow-ups lists use, laid out from the org's mobile
/// layout (`/crm/products/schema/?view_type=mobile`).
///
/// A product has no status, time or people columns, so on the webapp's card
/// it shows the name, the SKU as the sub-line, the price, the visible columns
/// as rows and the call button — which here opens the product, as there is no
/// one to call.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.schema = ViewSchema.empty,
  });
  final Product product;
  final VoidCallback onTap;

  /// The org's mobile card layout.
  final ViewSchema schema;

  @override
  Widget build(BuildContext context) {
    final custom = product.raw['custom_fields'];
    return SchemaMobileCard(
      name: product.name,
      raw: product.raw,
      customFields: custom is Map ? custom.cast<String, Object?>() : const {},
      schema: schema,
      statusLabel: product.active ? 'Active' : 'Inactive',
      fallbackCompany: product.code,
      fallbackValue: product.price,
      mockCell: (c) => productColumnText(product, c),
      onTap: onTap,
    );
  }
}
