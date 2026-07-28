import 'package:equatable/equatable.dart';

/// A single line item on a quote (product/service, qty, rate, amount).
class QuoteItem extends Equatable {
  final String name;
  final int qty;
  final String rate; // display, e.g. "₹9L"
  final String amt; // display, e.g. "₹9L"

  const QuoteItem({required this.name, required this.qty, required this.rate, required this.amt});

  @override
  List<Object?> get props => [name, qty, rate, amt];
}

/// A CRM quote. Fields mirror the prototype's `quotes` seed 1:1 so the mock data
/// source maps directly and the shape is API-ready.
class Quote extends Equatable {
  final String id;
  final String? custId;
  final String? leadId;
  final String status; // key into StatusMeta$.quote
  final String amount; // display, e.g. "₹9L"
  final int amountNum; // sortable
  final String issued;
  final String valid;
  final String template;
  final String payType;
  final String currency;
  final String dueDate;
  final String owner; // user id
  final List<QuoteItem> items;
  final String? note;

  const Quote({
    required this.id,
    required this.custId,
    required this.leadId,
    required this.status,
    required this.amount,
    required this.amountNum,
    required this.issued,
    required this.valid,
    required this.template,
    required this.payType,
    required this.currency,
    required this.dueDate,
    required this.owner,
    required this.items,
    this.note,
  });

  @override
  List<Object?> get props => [id];
}
