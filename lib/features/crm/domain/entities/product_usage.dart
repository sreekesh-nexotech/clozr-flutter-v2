import 'package:equatable/equatable.dart';

/// How much a catalog item is actually used — `GET /crm/products/{id}/usage/`.
///
/// Deliberately only the two counts the endpoint reports. Deals value, lifetime
/// revenue and average-per-deal are **not** in this response, and the product
/// record carries no usage figures either, so nothing here may stand in for
/// them: a "₹0 lifetime revenue" tile would be a claim the backend never made.
class ProductUsage extends Equatable {
  const ProductUsage({this.leads = 0, this.quotes = 0});

  final int leads;
  final int quotes;

  /// Whether this item has any related activity at all. False means the usage
  /// section is hidden rather than shown as a row of zeros.
  bool get hasActivity => leads > 0 || quotes > 0;

  static ProductUsage fromJson(Object? body) {
    if (body is! Map) return const ProductUsage();
    int count(String key, String listKey) {
      final n = body[key];
      if (n is num) return n.toInt();
      // Fall back to the list length when the count is absent but the rows
      // are there, rather than reporting "no activity" for a used item.
      final list = body[listKey];
      return list is List ? list.length : 0;
    }
    return ProductUsage(
      leads: count('leads_count', 'leads'),
      quotes: count('quotes_count', 'quotes'),
    );
  }

  @override
  List<Object?> get props => [leads, quotes];
}
