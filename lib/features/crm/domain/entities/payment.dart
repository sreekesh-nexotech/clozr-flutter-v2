import 'package:equatable/equatable.dart';

/// A CRM payment / installment. Fields mirror the prototype's `payments` seed
/// 1:1 so the mock data source maps directly and the shape is API-ready.
class Payment extends Equatable {
  final String id;
  final String? custId;
  final String? invId;
  final String label; // e.g. "Advance (40%)"
  final String amount; // display, e.g. "₹18L"
  final int amountNum;
  final String method; // "Bank transfer", "UPI", "—" …
  final String status; // key into StatusMeta$.payment
  final String date; // "05 May 2026" or "Overdue 24 Jun 2026"
  final String owner; // user id

  const Payment({
    required this.id,
    required this.custId,
    required this.invId,
    required this.label,
    required this.amount,
    required this.amountNum,
    required this.method,
    required this.status,
    required this.date,
    required this.owner,
  });

  @override
  List<Object?> get props => [id];
}
