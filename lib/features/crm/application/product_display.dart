// How a product is named on screen (Oct 2026 product `short_name`).
//
// Every product payload — the product's own row, `/crm/products/options/`,
// and each item of a lead's `products[]` — carries `short_name`, `""` when the
// org set none. **Lists** show the short name when it is set and the full
// `product_name` otherwise; **detail** screens keep `product_name`.

/// The server's ceiling for `short_name`; a longer one is a `400` on the field.
const kProductShortNameMax = 60;

/// A product's name for a list row: its `short_name` when non-blank, else its
/// `product_name` (or a bare `name`, which some nested shapes use). '' when
/// [product] names neither.
String productListName(Map<dynamic, dynamic> product) {
  final short = '${product['short_name'] ?? ''}'.trim();
  if (short.isNotEmpty) return short;
  return '${product['product_name'] ?? product['name'] ?? ''}'.trim();
}

/// What a PATCH sends for a typed short name: the trimmed text, or null to
/// clear it — the server stores both `null` and `""` as "no short name".
String? productShortNameWriteValue(String text) {
  final v = text.trim();
  return v.isEmpty ? null : v;
}

/// Why a typed short name would be refused, or null when it may be sent.
/// Checked before the round trip so the dialog keeps what was typed.
String? productShortNameError(String text) =>
    text.trim().length > kProductShortNameMax
        ? 'Short name can be at most $kProductShortNameMax characters'
        : null;
