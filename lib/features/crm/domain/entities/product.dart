import 'package:equatable/equatable.dart';

import 'package_composition.dart';

/// A note pinned to a catalog product.
class ProductNote extends Equatable {
  final String author;
  final String time;
  final String body;
  const ProductNote({required this.author, required this.time, required this.body});

  @override
  List<Object?> get props => [author, time, body];
}

/// A catalog product or package. Fields mirror the prototype's `products` seed
/// 1:1 so the mock data source maps directly and the shape is API-ready.
class Product extends Equatable {
  final String id;

  /// `product_code` — the human SKU ("PRD-NEXOCR-9AF0"). [id] is the
  /// `product_id` uuid: the lookup key, not something to show a user.
  final String code;
  final String name;
  final String kind; // "product" | "package"
  final String cat; // category key (Fit-out, Furniture, …)
  final String hsn;
  final String unit; // "per sq.ft.", "per project", …
  final String price; // display, e.g. "₹2,400"

  /// The unit price in rupees, unformatted.
  ///
  /// [price] is a **display** string and `formatInr` abbreviates it — ₹184,991
  /// renders as "₹1.8L" — so digits cannot be recovered from it. Anything doing
  /// arithmetic, above all the quote line items sent to the API, must read this
  /// instead. Mirrors the `amount`/`amountNum` pairing on Quote and Invoice.
  final double priceNum;
  final int gst; // percent, e.g. 18

  /// Whether [gst] came from the row rather than from the 18% fallback.
  ///
  /// The org's view settings decide which columns the serializer returns, and
  /// `tax_rate` can be switched off — in which case the rate is *unknown*, not
  /// 18%. Screens must not print a tax figure they were never given.
  final bool gstKnown;
  final String gstAmt; // display
  final String gross; // display gross unit price
  final int deals;
  final String revenue; // display, e.g. "₹8.64Cr"
  final int revNum; // sortable
  final String avg; // display avg per deal
  final bool active;
  final String? desc;

  /// What a package is made of, and its server-computed totals. Null for a
  /// plain product — the serializer gives packages alone those figures.
  final PackageComposition? composition;
  final List<ProductNote> notes;

  /// The row exactly as the API sent it — what makes the card's extra columns
  /// dynamic. A field the org adds to its layout is read from here by name.
  final Map<String, dynamic> raw;

  const Product({
    this.raw = const {},
    required this.id,
    this.code = '',
    required this.name,
    required this.kind,
    required this.cat,
    required this.hsn,
    required this.unit,
    required this.price,
    this.priceNum = 0,
    required this.gst,
    this.gstKnown = true,
    required this.gstAmt,
    required this.gross,
    required this.deals,
    required this.revenue,
    required this.revNum,
    required this.avg,
    required this.active,
    this.desc,
    this.composition,
    this.notes = const [],
  });

  bool get isPackage => kind == 'package';

  @override
  List<Object?> get props => [id];
}
