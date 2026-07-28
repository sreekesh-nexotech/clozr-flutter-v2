import 'package:equatable/equatable.dart';

/// A CRM invoice. Fields mirror the prototype's `invoices` seed 1:1 so the mock
/// data source maps directly and the shape is API-ready.
class Invoice extends Equatable {
  final String id;
  final String? custId;
  final String? quoteId;
  final String type; // "Lump sum" | "Installments"
  final String total; // display, e.g. "₹18L"
  final int totalNum;
  final int settled;
  final int of;
  final String balance; // display, e.g. "₹0L"
  final String status; // key into StatusMeta$.invoice

  const Invoice({
    required this.id,
    required this.custId,
    required this.quoteId,
    required this.type,
    required this.total,
    required this.totalNum,
    required this.settled,
    required this.of,
    required this.balance,
    required this.status,
  });

  /// Fraction of installments settled (0..1).
  double get progress => of == 0 ? 0 : settled / of;

  @override
  List<Object?> get props => [id];
}
