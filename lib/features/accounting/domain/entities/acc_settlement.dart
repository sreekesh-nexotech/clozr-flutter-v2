import 'package:equatable/equatable.dart';

/// How a receipt's or payment's pool was applied to one document.
class Allocation extends Equatable {
  const Allocation({
    required this.documentId,
    this.amountApplied = '0',
    this.tdsApplied,
    this.status,
  });

  final String documentId;
  final String amountApplied;
  final String? tdsApplied;
  final String? status;

  @override
  List<Object?> get props => [documentId, amountApplied, tdsApplied, status];
}

/// Customer money in (`settlement/receipts/`, handover §8.4).
class AccReceipt extends Equatable {
  const AccReceipt({
    required this.id,
    this.customerId,
    this.date,
    this.amount = '0',
    this.method,
    this.sourceAccountKind,
    this.reference,
    this.tdsDeducted,
    this.unallocated,
    this.treatAs,
    this.kind,
    this.status = 'POSTED',
    this.journalEntryId,
    this.allocations = const [],
  });

  final String id;
  final String? customerId;
  final String? date;
  final String amount;
  final String? method;
  final String? sourceAccountKind;
  final String? reference;
  final String? tdsDeducted;

  /// What did not land on an invoice and became a customer credit.
  final String? unallocated;
  final String? treatAs;
  final String? kind;
  final String status; // POSTED | REVERSED
  final String? journalEntryId;

  /// Only present on the detail read.
  final List<Allocation> allocations;

  bool get isPosted => status == 'POSTED';

  @override
  List<Object?> get props => [id, status, amount, unallocated, allocations];
}

/// A customer advance — money received before any invoice.
class AccAdvance extends Equatable {
  const AccAdvance({
    required this.id,
    this.customerId,
    this.supplyNature,
    this.supply,
    this.ratePct,
    this.taxable,
    this.remainingTaxable,
    this.status = 'OPEN',
    this.receiptId,
  });

  final String id;
  final String? customerId;
  final String? supplyNature;
  final String? supply;
  final String? ratePct;
  final String? taxable;
  final String? remainingTaxable;
  final String status;
  final String? receiptId;

  bool get isOpen => status == 'OPEN' || status == 'PARTIALLY_ADJUSTED';

  @override
  List<Object?> get props => [id, status, remainingTaxable];
}

/// A customer credit — created by an over-payment, an unapplied receipt or a
/// credit note hold; never created directly.
class AccCustomerCredit extends Equatable {
  const AccCustomerCredit({
    required this.id,
    this.customerId,
    this.source,
    this.amount = '0',
    this.remaining,
    this.status = 'OPEN',
  });

  final String id;
  final String? customerId;
  final String? source;
  final String amount;
  final String? remaining;
  final String status;

  @override
  List<Object?> get props => [id, status, remaining];
}

/// Vendor money out (`settlement/vendor-payments/`).
class AccVendorPayment extends Equatable {
  const AccVendorPayment({
    required this.id,
    this.vendorId,
    this.date,
    this.amount = '0',
    this.tdsNow,
    this.sourceAccountKind,
    this.reference,
    this.kind,
    this.status = 'POSTED',
    this.journalEntryId,
    this.allocations = const [],
  });

  final String id;
  final String? vendorId;
  final String? date;
  final String amount;
  final String? tdsNow;
  final String? sourceAccountKind;
  final String? reference;
  final String? kind;
  final String status;
  final String? journalEntryId;
  final List<Allocation> allocations;

  bool get isPosted => status == 'POSTED';

  @override
  List<Object?> get props => [id, status, amount, allocations];
}

/// A prepayment to a vendor.
class AccVendorAdvance extends Equatable {
  const AccVendorAdvance({
    required this.id,
    this.vendorId,
    this.amount = '0',
    this.tdsDeducted,
    this.remaining,
    this.status = 'ACTIVE',
  });

  final String id;
  final String? vendorId;
  final String amount;
  final String? tdsDeducted;
  final String? remaining;
  final String status;

  @override
  List<Object?> get props => [id, status, remaining];
}

/// The outcome of a posting write. The backend answers `200 {skipped: true}`
/// for an idempotent replay, a test customer or a date before the ledger
/// start (handover §4 D) — a distinct success, not a failure.
class PostOutcome<T> {
  const PostOutcome.posted(this.value) : skipped = false, skipReason = null;
  const PostOutcome.skipped(this.skipReason) : value = null, skipped = true;

  final T? value;
  final bool skipped;
  final String? skipReason;
}
