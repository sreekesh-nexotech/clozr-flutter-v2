import '../../../../../core/config/api_config.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/inr_format.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../domain/entities/invoice.dart';

/// Raw payment-header endpoints. `/quotations/payments/` rows ARE the UI's
/// invoices (a `Payment` is auto-created when a quote is accepted). HTTP +
/// JSON→entity mapping only — caching lives in the API repository.
class InvoicesRemoteDataSource {
  const InvoicesRemoteDataSource(this._api);

  final ApiService _api;

  /// Raw `/quotations/payments/` rows, following `next` up to 3 pages. The
  /// repository caches these and maps them via [invoicesFromApiRows].
  Future<List<Map<String, dynamic>>> fetchInvoiceRows({
    String? customerId,
  }) async {
    final out = <Map<String, dynamic>>[];
    var page = 1;
    while (page <= 50) {
      final body = await _api.get(ApiEndpoints.payments, query: {
        'page': page,
        'page_size': ApiConfig.defaultPageSize,
        // Payment → Quotation → Customer; the server walks the chain.
        if (customerId != null) 'customer_id': customerId,
      });
      final paged = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m);
      out.addAll(paged.results);
      if (!paged.hasMore) break;
      page++;
    }
    return out;
  }

  /// `PATCH /quotations/payments/{payment_id}/` — the plan's accounting
  /// settings (handover §9.2): `billing_mode`, `auto_issue`, `amounts_are`,
  /// `project`, `contract_ref`. `amounts_are` answers a field-level 400 once
  /// any record is linked or receipted.
  Future<void> updatePlan(String paymentId, Map<String, Object?> fields) =>
      _api.patch(ApiEndpoints.payment(paymentId), body: fields);

  /// `GET /quotations/payments/{payment_id}/summary/` (doc §2b).
  ///
  /// Best-effort: the header row already carries enough to render the invoice,
  /// so a failure here means the screen keeps its own arithmetic rather than
  /// losing the card. Returns null on any failure, which callers read as "no
  /// server figures — use the derived ones".
  Future<InvoiceSummary?> fetchSummary(String paymentId) async {
    if (paymentId.isEmpty) return null;
    try {
      final body = await _api.get(ApiEndpoints.paymentSummary(paymentId));
      return body is Map<String, dynamic> ? summaryFromApi(body) : null;
    } on Object {
      return null;
    }
  }
}

// ── JSON → entity mapping (public so the repository and tests reuse it) ──

/// Maps the `summary` payload. Amounts arrive as decimal **strings**
/// (`"184991.00"`), so they go through the same `parseAmount` as every other
/// money field rather than being read as numbers.
InvoiceSummary summaryFromApi(Map<String, dynamic> row) => InvoiceSummary(
      totalNum: parseAmount(row['total_amount']).round(),
      paidNum: parseAmount(row['amount_paid']).round(),
      remainingNum: parseAmount(row['amount_remaining']).round(),
      currency: _str(row['currency']) ?? 'INR',
      status: _str(row['status']) ?? '',
      nextDue: parseApiDate(row['next_due_date']),
      totalRecords: _int(row['total_records']),
      pendingRecords: _int(row['pending_records']),
      paidRecords: _int(row['paid_records']),
      overdueRecords: _int(row['overdue_records']),
    );

/// A count that may arrive as a number or as a string.
///
/// `int.tryParse` returns null for a decimal string like "3.0", which read as a
/// count of 0 - "0 of 0 settled". The double fallback covers that.
int _int(Object? v) {
  if (v is num) return v.toInt();
  final s = '$v'.trim();
  return int.tryParse(s) ?? double.tryParse(s)?.round() ?? 0;
}

/// Maps a list of raw rows, skipping malformed entries.
///
/// A quote with recurring lines has TWO plans (one-time + recurring) under
/// the same `quotation_number`. [Invoice.id] is that number, and it is what
/// the detail route and the schedule join key on — so both plans resolved to
/// whichever came first. A number that repeats is replaced by each plan's own
/// `payment_id`, which keeps every id unique; [Invoice.quoteId] still carries
/// the number for display.
List<Invoice> invoicesFromApiRows(List<dynamic> rows) {
  final mapped = <Invoice>[];
  for (final r in rows) {
    if (r is Map<String, dynamic>) {
      final iv = invoiceFromApi(r);
      if (iv != null) mapped.add(iv);
    }
  }
  final seen = <String, int>{};
  for (final iv in mapped) {
    seen[iv.id] = (seen[iv.id] ?? 0) + 1;
  }
  return [
    for (final iv in mapped)
      if ((seen[iv.id] ?? 0) > 1 && iv.uuid.isNotEmpty) iv.withId(iv.uuid) else iv,
  ];
}

/// Maps one `/quotations/payments/` row → [Invoice]. Returns null when the row
/// is unusable (no id) — a malformed row is skipped, never fatal.
Invoice? invoiceFromApi(Map<String, dynamic> row) {
  final quotationNumber = _str(row['quotation_number']);
  final id = quotationNumber ?? _str(row['payment_id']);
  if (id == null) return null;
  try {
    final total = parseAmount(row['total_amount']);
    final amountPaid = parseAmount(row['amount_paid']);
    // Absent is not zero. A row that never reported its outstanding balance
    // would otherwise compute `total - 0` and look fully settled.
    final hasRemaining = row.containsKey('amount_remaining');
    final remaining = parseAmount(row['amount_remaining']);
    final balance = hasRemaining ? remaining : total - amountPaid;
    final records =
        row['records'] is List ? (row['records'] as List) : const <dynamic>[];
    var settled = 0;
    var of = 0;
    for (final r in records) {
      if (r is! Map) continue;
      final st = r['status'];
      final statusStr = st is String ? st.toLowerCase() : '';
      // Cancelled records aren't part of the schedule (paymentRecordFromApi
      // drops them too), so they must not inflate "settled X of Y".
      if (statusStr == 'cancelled') continue;
      of++;
      if (statusStr == 'paid') settled++;
    }
    return Invoice(
      id: id,
      uuid: _str(row['payment_id']) ?? '',
      custId: _str(row['customer_id']) ??
          (row['customer'] is Map ? _str((row['customer'] as Map)['customer_id']) : null),
      // The list serializer sends only `customer_name`; the detail nests a
      // `customer` object. Both are read, so a card always has something to
      // show instead of an em dash on every single row.
      custName: _str(row['customer_name']) ??
          (row['customer'] is Map
              ? _str((row['customer'] as Map)['customer_name']) ??
                  _str((row['customer'] as Map)['name'])
              : null),
      quoteId: quotationNumber,
      quoteUuid: _str(row['quotation']),
      type: planTypeLabel(_str(row['payment_type'])),
      total: formatInr(total),
      totalNum: total.round(),
      settled: settled,
      of: of,
      balance: formatInr(remaining),
      // Absent is not the same as zero - see Invoice.remainingNum.
      remainingNum: hasRemaining ? remaining.round() : null,
      paidNum: amountPaid.round(),
      // The webapp's split of the server's `active | completed`: any payment
      // on an active plan is Partial (a subscription with two periods paid
      // read Unpaid while its balance was folded off the cash figure). The
      // balance is `amount_remaining` (total − settled, TDS included), else
      // total − cash.
      status: planStatusKey(
        paid: amountPaid,
        balance: balance,
        total: total,
        backendStatus: _str(row['status']),
      ),
      billingMode: _str(row['billing_mode']),
      autoIssue: row['auto_issue'] == true,
      amountsAre: _str(row['amounts_are']),
      projectId: _str(row['project']) ??
          (row['project'] is Map ? _str((row['project'] as Map)['project_id']) : null),
      contractRef: _str(row['contract_ref']),
      paymentType: _str(row['payment_type']) ?? '',
      backendStatus: _str(row['status']),
      totalExact: total,
      paidExact: amountPaid,
      balanceExact: balance,
      // The incl.-GST figures fall back to the gross roll-ups (the same server
      // values on an older backend), as on web.
      totalInclGst: _dec(row['total_incl_gst']) ?? _dec(row['gross_total']),
      amountDueInclGst:
          _dec(row['amount_due_incl_gst']) ?? _dec(row['balance_due_gross']),
      amountRemainingInclGst: _dec(row['amount_remaining_incl_gst']),
      quotedTotalInclGst: _dec(row['quoted_total_incl_gst']),
      unscheduledInclGst: _dec(row['unscheduled_incl_gst']),
      amountRefunded: _dec(row['amount_refunded']) ?? 0,
      subscription: planSubscriptionFromApi(row['subscription']),
      recurring: planRecurringFromApi(row['recurring']),
      chargeScope: _str(row['charge_scope']),
      nextDue: parseApiDate(row['next_due_date']),
      numInstallments: row['num_installments'] is num
          ? (row['num_installments'] as num).toInt()
          : null,
      billingPeriodDays: row['billing_period_days'] is num
          ? (row['billing_period_days'] as num).toInt()
          : null,
      leadId: row['customer'] is Map
          ? _str((row['customer'] as Map)['lead_id'])
          : null,
    );
  } on Object {
    return null;
  }
}

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

/// A money field that is actually present (not null / blank), parsed; null
/// otherwise — absent is not zero.
double? _dec(Object? v) {
  if (v == null || (v is String && v.trim().isEmpty)) return null;
  return parseAmount(v);
}

int _intOr0(Object? v) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);

/// `subscription` → [PlanSubscription]; null when absent or malformed.
PlanSubscription? planSubscriptionFromApi(Object? v) {
  if (v is! Map) return null;
  return PlanSubscription(
    periodLabel: _str(v['period_label']) ?? '',
    amountPerPeriod: parseAmount(v['amount_per_period']),
    amountPerPeriodInclGst: parseAmount(v['amount_per_period_incl_gst']),
    periodsScheduled: _intOr0(v['periods_scheduled']),
    periodsPaid: _intOr0(v['periods_paid']),
    periodsOpen: _intOr0(v['periods_open']),
    openEnded: v['open_ended'] != false,
    amountScheduledInclGst: parseAmount(v['amount_scheduled_incl_gst']),
    amountDueNowInclGst: parseAmount(v['amount_due_now_incl_gst']),
    nextDue: parseApiDate(v['next_due_date']),
    header: _str(v['header']) ?? '',
  );
}

/// `recurring` → [PlanRecurring]; null when absent or malformed.
PlanRecurring? planRecurringFromApi(Object? v) {
  if (v is! Map) return null;
  int? optInt(Object? x) => x is num ? x.toInt() : null;
  final effective = optInt(v['effective_term_periods']);
  return PlanRecurring(
    periodLabel: _str(v['period_label']) ?? '',
    termPeriods: optInt(v['term_periods']),
    effectiveTermPeriods: effective,
    ongoing: v['ongoing'] is bool ? v['ongoing'] as bool : effective == null,
    amountPerPeriod: parseAmount(v['amount_per_period']),
    amountPerPeriodInclGst: parseAmount(v['amount_per_period_incl_gst']),
    periodsGenerated: _intOr0(v['periods_generated']),
    periodsPaid: _intOr0(v['periods_paid']),
    periodsElapsed: _intOr0(v['periods_elapsed']),
    progressPct: _intOr0(v['progress_pct']).clamp(0, 100),
    nextDue: parseApiDate(v['next_due_date']),
    firstPeriodStart: parseApiDate(v['first_period_start']),
    nextPeriodStart: parseApiDate(v['next_period_start']),
    generationEnded: v['generation_ended'] == true,
    stopFrom: parseApiDate(v['stop_from']),
    canStop: v['can_stop'] == true,
    header: _str(v['header']) ?? '',
  );
}
