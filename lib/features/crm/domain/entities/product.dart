import 'package:equatable/equatable.dart';

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
  final String name;
  final String kind; // "product" | "package"
  final String cat; // category key (Fit-out, Furniture, …)
  final String hsn;
  final String unit; // "per sq.ft.", "per project", …
  final String price; // display, e.g. "₹2,400"
  final int gst; // percent, e.g. 18
  final String gstAmt; // display
  final String gross; // display gross unit price
  final int deals;
  final String revenue; // display, e.g. "₹8.64Cr"
  final int revNum; // sortable
  final String avg; // display avg per deal
  final bool active;
  final String? desc;
  final List<ProductNote> notes;

  const Product({
    required this.id,
    required this.name,
    required this.kind,
    required this.cat,
    required this.hsn,
    required this.unit,
    required this.price,
    required this.gst,
    required this.gstAmt,
    required this.gross,
    required this.deals,
    required this.revenue,
    required this.revNum,
    required this.avg,
    required this.active,
    this.desc,
    this.notes = const [],
  });

  bool get isPackage => kind == 'package';

  @override
  List<Object?> get props => [id];
}
