import 'record_payment_logic.dart';

// What the Record payment sheet reads about a plan, parsed straight from
// `/quotations/payments/` (list + detail). Kept apart from the shared
// `Invoice` / `Payment` entities: the sheet needs the gross (incl. GST)
// balances, which those round or omit.

/// One row of the plan picker (`GET /quotations/payments/?search=`).
class PlanOption {
  const PlanOption({
    required this.id,
    required this.quoteNo,
    required this.who,
    required this.totalInclGst,
    required this.amountDueInclGst,
  });

  factory PlanOption.fromJson(Map<String, dynamic> j) => PlanOption(
        id: '${j['payment_id'] ?? ''}',
        quoteNo: _s(j['quotation_number']),
        who: _s(j['customer_name']).isNotEmpty
            ? _s(j['customer_name'])
            : (j['customer'] is Map ? _s((j['customer'] as Map)['name']) : _s(j['lead_name'])),
        totalInclGst: _firstMoney([j['total_incl_gst'], j['gross_total'], j['total_amount']]),
        amountDueInclGst: _firstMoney([j['amount_due_incl_gst'], j['balance_due_gross'], j['amount_remaining']]),
      );

  /// `payment_id` (uuid).
  final String id;
  final String quoteNo;

  /// Company / customer, or the lead's name on a lead-only plan.
  final String who;
  final double totalInclGst;
  final double amountDueInclGst;

  /// "QTN-00041 · UAT Pay Even" (webapp `<quoteNo || id> · <company>`).
  String get label => '${quoteNo.isNotEmpty ? quoteNo : id} · ${who.isNotEmpty ? who : '—'}';

  /// "Due ₹11,800 of ₹11,800 (incl. GST)".
  String get dueLine => 'Due ${rupees(amountDueInclGst)} of ${rupees(totalInclGst)} (incl. GST)';
}

/// One instalment of a plan, with its gross figures.
class PlanRecord {
  const PlanRecord({
    required this.id,
    required this.installmentNumber,
    required this.label,
    required this.status,
    required this.settlementState,
    required this.amountDueGross,
    required this.balanceDue,
    this.adjustmentState,
    this.linkedDocumentId,
  });

  factory PlanRecord.fromJson(Map<String, dynamic> r) {
    final expected = apiMoney(r['amount_expected']);
    final gross = _present(r['amount_due_gross']) ? apiMoney(r['amount_due_gross']) : expected;
    final status = _s(r['status']).toLowerCase();
    final summary = r['record_summary'];
    final adjustments = summary is Map ? summary['adjustments'] : null;
    final n = r['installment_number'];
    return PlanRecord(
      id: _s(r['record_id']),
      installmentNumber: n is num ? n.toInt() : 0,
      label: _s(r['notes']),
      status: status,
      settlementState: _settlementState(r['settlement_state'], status),
      amountDueGross: gross,
      // Webapp `toBalanceDue`: as sent, else gross less what settled on a
      // paid record, else the gross due.
      balanceDue: _present(r['balance_due'])
          ? apiMoney(r['balance_due'])
          : (status == 'paid'
              ? (gross - apiMoney(r['amount_paid']) - apiMoney(r['tds_deducted']) - apiMoney(r['bank_charge']))
                  .clamp(0, double.infinity)
                  .toDouble()
              : gross),
      adjustmentState: adjustments is Map ? _s(adjustments['state']) : null,
      linkedDocumentId: _s(r['linked_document_id']).isEmpty ? null : _s(r['linked_document_id']),
    );
  }

  final String id;
  final int installmentNumber;

  /// The record's `notes` — its display label when set.
  final String label;

  /// `pending` | `paid` | `overdue` | `cancelled`.
  final String status;

  /// `pending` | `partly_paid` | `paid`.
  final String settlementState;
  final double amountDueGross;
  final double balanceDue;
  final String? adjustmentState;
  final String? linkedDocumentId;

  /// Still open for settling (webapp: not paid, not cancelled).
  bool get isOpen => status != 'paid' && status != 'cancelled';

  /// The open balance a settle starts from.
  double get open => openBalance(balanceDue: balanceDue, amountDueGross: amountDueGross);

  String get title => label.isNotEmpty ? label : 'Installment $installmentNumber';

  /// Webapp `settlementStateMeta(...).label`.
  String get stateLabel {
    if (status == 'cancelled') return 'Cancelled';
    switch (adjustmentState) {
      case 'RECEIPT_REVERSED':
        return 'Receipt reversed';
      case 'REFUNDED':
        return 'Refunded';
      case 'PARTLY_REFUNDED':
        return 'Partly refunded';
      case 'CREDITED':
        return 'Credited';
      case 'PARTLY_CREDITED':
        return 'Partly credited';
    }
    switch (settlementState) {
      case 'paid':
        return 'Paid';
      case 'partly_paid':
        return 'Partly paid';
      default:
        return 'Pending';
    }
  }

  /// "Installment 1 · ₹10,000 · Pending".
  String get optionLabel => '$title · ${rupees(amountDueGross)} · $stateLabel';
}

/// A plan as the sheet needs it (`GET /quotations/payments/{id}/`).
class RecordPaymentPlan {
  const RecordPaymentPlan({
    required this.id,
    required this.quoteNo,
    required this.quotationUuid,
    required this.customerName,
    required this.leadName,
    required this.hasCustomer,
    required this.paymentType,
    required this.totalInclGst,
    required this.amountDueInclGst,
    required this.records,
  });

  factory RecordPaymentPlan.fromJson(Map<String, dynamic> j) {
    final rows = [
      for (final r in (j['records'] is List ? j['records'] as List : const []))
        if (r is Map) PlanRecord.fromJson(Map<String, dynamic>.from(r)),
    ]..sort((a, b) => a.installmentNumber.compareTo(b.installmentNumber));
    final rawRows = j['records'] is List ? j['records'] as List : const [];
    String leadName = '';
    for (final r in rawRows) {
      if (r is Map && _s(r['lead_name']).isNotEmpty) {
        leadName = _s(r['lead_name']);
        break;
      }
    }
    final customer = j['customer'];
    final customerName = customer is Map
        ? (_s(customer['name']).isNotEmpty ? _s(customer['name']) : _s(customer['company_name']))
        : _s(j['customer_name']);
    return RecordPaymentPlan(
      id: _s(j['payment_id']),
      quoteNo: _s(j['quotation_number']),
      quotationUuid: _s(j['quotation']),
      customerName: customerName,
      leadName: leadName,
      hasCustomer: customer is Map || customer is String && customer.isNotEmpty,
      paymentType: _s(j['payment_type']),
      totalInclGst: _firstMoney([j['total_incl_gst'], j['gross_total'], j['total_amount']]),
      amountDueInclGst: _firstMoney([j['amount_due_incl_gst'], j['balance_due_gross'], j['amount_remaining']]),
      records: rows,
    );
  }

  final String id;
  final String quoteNo;
  final String quotationUuid;
  final String customerName;
  final String leadName;
  final bool hasCustomer;
  final String paymentType;
  final double totalInclGst;
  final double amountDueInclGst;
  final List<PlanRecord> records;

  String get who => customerName.isNotEmpty ? customerName : (leadName.isNotEmpty ? leadName : '—');

  List<PlanRecord> get openRecords => [for (final r in records) if (r.isOpen) r];

  /// "QTN-00041 · UAT Pay Even · due ₹11,800 of ₹11,800 (incl. GST)".
  String get summary =>
      '${quoteNo.isNotEmpty ? quoteNo : id} · $who · due ${rupees(amountDueInclGst)} of ${rupees(totalInclGst)} (incl. GST)';

  bool get needsCustomer => planNeedsCustomer(hasCustomer: hasCustomer, quotationUuid: quotationUuid);
}

String _s(Object? v) => v == null ? '' : '$v'.trim();

bool _present(Object? v) => v != null && '$v'.trim().isNotEmpty;

double _firstMoney(List<Object?> candidates) {
  for (final c in candidates) {
    if (_present(c)) return apiMoney(c);
  }
  return 0;
}

String _settlementState(Object? v, String status) {
  if (v == 'paid' || v == 'partly_paid' || v == 'pending') return v as String;
  return status == 'paid' ? 'paid' : 'pending';
}
