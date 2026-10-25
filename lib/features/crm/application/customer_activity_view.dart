import 'package:intl/intl.dart';

import '../../../core/utils/relative_time.dart';

/// Pure view logic for the customer detail's activity tabs — the mobile port
/// of the webapp's `customerActivity.response.ts`, `customerPayments.ts`,
/// `sourceChip.ts` and the Opportunities / Call log rows of
/// `CustomerDetailScreen.tsx`. No Flutter, no Riverpod, so it is unit-tested
/// directly.

// ───────────────────────────── shared helpers ─────────────────────────────

double? _optNum(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }
  return null;
}

double _num(Object? v) => _optNum(v) ?? 0;

String _str(Object? v) => v is String ? v.trim() : (v == null ? '' : '$v'.trim());

final NumberFormat _inrWhole = NumberFormat.currency(locale: 'en_IN', symbol: '', decimalDigits: 0);
final NumberFormat _inrPaise = NumberFormat.currency(locale: 'en_IN', symbol: '', decimalDigits: 2);
final DateFormat _date = DateFormat('d MMM yyyy');

/// Webapp `money`: `₹74,339` for whole rupees, `₹20,999.67` with paise.
String activityMoney(double? n) {
  if (n == null || n.isNaN || n.isInfinite) return '—';
  final paise = (n.abs() * 100).round();
  final text = paise % 100 == 0 ? _inrWhole.format(paise ~/ 100) : _inrPaise.format(paise / 100);
  return '${n < 0 && paise > 0 ? '-₹' : '₹'}${text.trim()}';
}

/// Webapp `fmtDate`: "5 Oct 2026"; an unparsable value passes through.
String activityDate(String? iso) {
  final s = (iso ?? '').trim();
  if (s.isEmpty) return '';
  final d = DateTime.tryParse(s);
  if (d == null) return s;
  // A bare date ("2026-10-05") is a calendar day, not an instant — no shift.
  return _date.format(s.length <= 10 ? d : d.toLocal());
}

/// `UPPER_SNAKE` / `lower_snake` → "Upper snake".
String humanizeEnum(String? value) {
  final words = (value ?? '').replaceAll(RegExp(r'[_\-\s]+'), ' ').trim().toLowerCase();
  return words.isEmpty ? '' : words[0].toUpperCase() + words.substring(1);
}

const _paymentMethodLabels = {
  'upi': 'UPI',
  'neft': 'NEFT',
  'imps': 'IMPS',
  'rtgs': 'RTGS',
  'cash': 'Cash',
  'cheque': 'Cheque',
  'card': 'Card',
  'bank_transfer': 'Bank transfer',
  'gateway': 'Payment gateway',
  'razorpay': 'Razorpay',
  'other': 'Other',
};

const _planTypeLabels = {
  'lumpsum': 'Lump sum',
  'subscription': 'Subscription',
  'installment_even': 'Instalments – even split',
  'installment_custom': 'Milestone-based',
};

String paymentMethodLabel(String? v) {
  final k = (v ?? '').trim();
  if (k.isEmpty) return '';
  return _paymentMethodLabels[k.toLowerCase()] ?? humanizeEnum(k);
}

String planTypeLabel(String? v) {
  final k = (v ?? '').trim();
  if (k.isEmpty) return '';
  return _planTypeLabels[k.toLowerCase()] ?? humanizeEnum(k);
}

// ───────────────────────────── Payments ─────────────────────────────

class CustomerPaymentRecord {
  const CustomerPaymentRecord({
    required this.id,
    required this.invoiceId,
    required this.installmentNumber,
    required this.label,
    required this.amount,
    required this.dueDate,
    required this.method,
    required this.status,
    this.amountInclGst,
    this.amountPaid = 0,
    this.balanceDue,
    this.settlementState = '',
  });

  final String id;
  final String invoiceId;
  final int installmentNumber;

  /// The record's `notes` ("Installment 1 of 3", "Advance · 40%").
  final String label;
  final double amount;
  final String dueDate;
  final String method;

  /// paid | pending | overdue | cancelled.
  final String status;
  final double? amountInclGst;
  final double amountPaid;
  final double? balanceDue;

  /// pending | partly_paid | paid ('' on an older backend).
  final String settlementState;

  factory CustomerPaymentRecord.fromJson(Map<String, dynamic> r) {
    final n = r['installment_number'];
    final number = n is num ? n.toInt() : int.tryParse(_str(n)) ?? 0;
    final notes = _str(r['notes']);
    return CustomerPaymentRecord(
      id: _str(r['record_id']),
      // `payment` is the plan FK; `invoice_id` a deprecated alias.
      invoiceId: _str(r['payment']).isNotEmpty ? _str(r['payment']) : _str(r['invoice_id']),
      installmentNumber: number,
      label: notes.isNotEmpty ? notes : 'Installment ${number == 0 ? '' : number}'.trim(),
      amount: _num(r['amount_expected']),
      dueDate: _str(r['due_date']),
      method: _str(r['payment_method']),
      status: _str(r['status']),
      amountInclGst: _optNum(r['amount_due_incl_gst']),
      amountPaid: _num(r['amount_paid']),
      balanceDue: _optNum(r['balance_due']),
      settlementState: _str(r['settlement_state']),
    );
  }
}

class CustomerPaymentSubscription {
  const CustomerPaymentSubscription({
    required this.periodLabel,
    required this.amountPerPeriodInclGst,
    required this.header,
  });
  final String periodLabel;
  final double amountPerPeriodInclGst;
  final String header;
}

/// One payment plan ("invoice" header) with its instalments.
class CustomerPayment {
  const CustomerPayment({
    required this.id,
    required this.quoteNumber,
    required this.paymentType,
    required this.total,
    required this.paid,
    required this.balance,
    required this.status,
    required this.records,
    this.totalInclGst,
    this.remainingInclGst,
    this.subscription,
    this.unscheduledInclGst,
  });

  final String id;
  final String quoteNumber;
  final String paymentType;
  final double total;
  final double paid;
  final double balance;

  /// active | completed | cancelled.
  final String status;
  final List<CustomerPaymentRecord> records;
  final double? totalInclGst;
  final double? remainingInclGst;
  final CustomerPaymentSubscription? subscription;
  final double? unscheduledInclGst;

  bool get isCancelled => status.toLowerCase() == 'cancelled';
}

/// Webapp `toCustomerPayments`: the two customer-scoped lists
/// (`/quotations/payments/` headers + `/quotations/payment-records/` rows)
/// joined on the plan id, instalments sorted by number.
List<CustomerPayment> customerPaymentsFromRows(
  List<Map<String, dynamic>> payments,
  List<Map<String, dynamic>> records,
) {
  final byPlan = <String, List<CustomerPaymentRecord>>{};
  for (final raw in records) {
    final rec = CustomerPaymentRecord.fromJson(raw);
    if (rec.invoiceId.isEmpty) continue;
    (byPlan[rec.invoiceId] ??= []).add(rec);
  }
  return [
    for (final p in payments)
      if (_str(p['payment_id']).isNotEmpty)
        () {
          final id = _str(p['payment_id']);
          final total = _num(p['total_amount']);
          final paid = _num(p['amount_paid']);
          final sub = p['subscription'];
          final rows = [...?byPlan[id]]..sort((a, b) => a.installmentNumber.compareTo(b.installmentNumber));
          return CustomerPayment(
            id: id,
            quoteNumber: _str(p['quotation_number']),
            paymentType: _str(p['payment_type']),
            total: total,
            paid: paid,
            balance: p['amount_remaining'] != null ? _num(p['amount_remaining']) : total - paid,
            status: _str(p['status']),
            records: rows,
            totalInclGst: _optNum(p['total_incl_gst']),
            remainingInclGst: _optNum(p['amount_remaining_incl_gst']) ?? _optNum(p['amount_due_incl_gst']),
            subscription: sub is Map
                ? CustomerPaymentSubscription(
                    periodLabel: _str(sub['period_label']),
                    amountPerPeriodInclGst: _num(sub['amount_per_period_incl_gst']),
                    header: _str(sub['header']),
                  )
                : null,
            unscheduledInclGst: _optNum(p['unscheduled_incl_gst']),
          );
        }(),
  ];
}

enum StatTone { normal, success, muted }

class PaymentPlanStat {
  const PaymentPlanStat(this.label, this.value, [this.tone = StatTone.normal]);
  final String label;
  final double value;
  final StatTone tone;
}

/// "Payment plan #QTN-00002 (from accepted quote)".
String paymentPlanTitle(CustomerPayment p) =>
    p.quoteNumber.isEmpty ? 'Payment plan' : 'Payment plan #${p.quoteNumber} (from accepted quote)';

/// The header pill: Paid / Cancelled / Due.
({String label, bool done}) paymentPlanPill(CustomerPayment p) {
  final s = p.status.toLowerCase();
  if (s == 'completed') return (label: 'Paid', done: true);
  if (s == 'cancelled') return (label: 'Cancelled', done: false);
  return (label: 'Due', done: false);
}

/// The plan's headline figures, on one basis (incl. GST).
List<PaymentPlanStat> paymentPlanStats(CustomerPayment p) {
  final paid = PaymentPlanStat('Paid', p.paid, StatTone.success);
  final totalIncl = p.totalInclGst;
  if (totalIncl == null) {
    return [PaymentPlanStat('Plan total', p.total), paid, PaymentPlanStat('Balance due', p.balance)];
  }
  final remainingRaw = p.remainingInclGst ?? (totalIncl - p.paid);
  final remaining = remainingRaw < 0 ? 0.0 : remainingRaw;
  final due = p.isCancelled && remaining > 0.005
      ? PaymentPlanStat('Not collected (incl. GST)', remaining, StatTone.muted)
      : PaymentPlanStat('Balance due (incl. GST)', remaining);
  final sub = p.subscription;
  if (sub != null) {
    final period = sub.periodLabel.isEmpty ? 'period' : sub.periodLabel;
    return [PaymentPlanStat('Per $period (incl. GST)', sub.amountPerPeriodInclGst), paid, due];
  }
  return [PaymentPlanStat('Total (incl. GST)', totalIncl), paid, due];
}

class PaymentRowView {
  const PaymentRowView({
    required this.id,
    required this.record,
    required this.title,
    required this.amount,
    required this.statusLabel,
    required this.done,
    required this.cancelled,
    required this.note,
  });
  final String id;
  final CustomerPaymentRecord record;

  /// "Installment 1 of 3 · 33%".
  final String title;
  final double amount;

  /// Paid / Partly paid / Overdue / Due / Cancelled.
  final String statusLabel;
  final bool done;
  final bool cancelled;

  /// "₹20,999.67 paid · ₹3,780.33 due" on a part-paid instalment.
  final String note;
}

({String label, bool done}) _recordStatus(CustomerPaymentRecord r) {
  final status = r.status.toLowerCase();
  if (status == 'cancelled') return (label: 'Cancelled', done: false);
  if (r.settlementState == 'paid' || (status == 'paid' && r.settlementState != 'partly_paid')) {
    return (label: 'Paid', done: true);
  }
  if (r.settlementState == 'partly_paid') return (label: 'Partly paid', done: false);
  if (status == 'overdue') return (label: 'Overdue', done: false);
  return (label: 'Due', done: false);
}

/// Every instalment (cancelled included) with its share of the whole schedule.
List<PaymentRowView> paymentPlanRows(CustomerPayment p) {
  final all = p.totalInclGst == null
      ? p.records.where((r) => r.status.toLowerCase() != 'cancelled').toList()
      : p.records;
  double amountOf(CustomerPaymentRecord r) => r.amountInclGst ?? r.amount;
  final sum = all.fold<double>(0, (acc, r) => acc + amountOf(r));
  final owed = p.isCancelled ? 'not collected' : 'due';
  return [
    for (final r in all)
      () {
        final amount = amountOf(r);
        final share = p.subscription == null && sum > 0 ? (amount / sum * 100).round() : 0;
        final status = _recordStatus(r);
        final partly = status.label == 'Partly paid';
        return PaymentRowView(
          id: r.id,
          record: r,
          title: share > 0 && all.length > 1 ? '${r.label} · $share%' : r.label,
          amount: amount,
          statusLabel: status.label,
          done: status.done,
          cancelled: status.label == 'Cancelled',
          note: partly && r.balanceDue != null
              ? '${activityMoney(r.amountPaid)} paid · ${activityMoney(r.balanceDue)} $owed'
              : '',
        );
      }(),
  ];
}

/// The instalment row's meta line: due date · method · plan type · note.
String paymentRowMeta(CustomerPayment p, PaymentRowView row) => [
      activityDate(row.record.dueDate),
      paymentMethodLabel(row.record.method),
      planTypeLabel(p.paymentType),
      row.note,
    ].where((s) => s.isNotEmpty).join(' · ');

/// A subscription's summary, or a milestone plan's unscheduled gap.
String paymentPlanNote(CustomerPayment p) {
  final header = p.subscription?.header ?? '';
  if (header.isNotEmpty) return header;
  final gap = p.unscheduledInclGst;
  if (p.paymentType == 'installment_custom' && gap != null && gap > 0.005 && !p.isCancelled) {
    return p.records.isEmpty
        ? 'No milestones yet — ${activityMoney(gap)} (incl. GST) is not scheduled. Add the milestones on the payment plan.'
        : '${activityMoney(gap)} (incl. GST) of the quote is not scheduled in a milestone yet.';
  }
  return '';
}

// ───────────────────────────── Call log ─────────────────────────────

const callLogNumbersRequired = 'From and To numbers are required.';
const callLogDurationInvalid = 'Duration must be HH:MM:SS — e.g. 00:03:20.';

final _hhmmss = RegExp(r'^\d{1,2}:[0-5]\d:[0-5]\d$');

/// Webapp `AddCustomerCallLogModal` checks: From and To are required; an
/// optional duration must read HH:MM:SS. Null = valid.
String? validateCustomerCallLog({required String from, required String to, String duration = ''}) {
  if (from.trim().isEmpty || to.trim().isEmpty) return callLogNumbersRequired;
  final d = duration.trim();
  if (d.isNotEmpty && !_hhmmss.hasMatch(d)) return callLogDurationInvalid;
  return null;
}

/// `POST /crm/call-logs/` body, linked to the customer.
Map<String, dynamic> customerCallLogBody({
  required String customerId,
  required String from,
  required String to,
  required String direction,
  required String medium,
  String duration = '',
}) =>
    {
      'from_number': from.trim(),
      'to_number': to.trim(),
      'type': direction,
      'telephony_medium': medium,
      if (duration.trim().isNotEmpty) 'duration': duration.trim(),
      'related_to': 'customer',
      'related_to_id': customerId,
    };

/// One call-log row as the webapp's Call log tab shows it.
class CustomerCallRow {
  const CustomerCallRow({
    required this.id,
    required this.direction,
    required this.medium,
    required this.duration,
    required this.startedAt,
    required this.parentModel,
    required this.parentId,
  });

  final String id;

  /// "Outgoing" / "Incoming" (the API `type`).
  final String direction;

  /// "Manual" / "Exotel" / "Twilio" (`telephony_medium`).
  final String medium;

  /// `duration` as sent ("00:05:30").
  final String duration;
  final DateTime? startedAt;
  final String parentModel;
  final String parentId;

  bool get isOutgoing => direction.toLowerCase().startsWith('out');

  factory CustomerCallRow.fromJson(Map<String, dynamic> j) => CustomerCallRow(
        id: _str(j['crm_call_log_id']),
        direction: _str(j['type']),
        medium: _str(j['telephony_medium']),
        duration: _str(j['duration']),
        startedAt: parseApiDate(j['start_time']) ?? parseApiDate(j['created_at']),
        parentModel: _str(j['related_to_model']),
        parentId: _str(j['related_to_object_id']),
      );

  /// "00:05:30 · 2h ago".
  String metaLine({DateTime? now}) =>
      [duration, relativeTime(startedAt, now: now)].where((s) => s.isNotEmpty).join(' · ');
}

// ───────────────────────────── History tags ─────────────────────────────

/// "From lead LD-0021" for a row that is the converted lead's history on its
/// customer, else null (webapp `historyTagFor`, `historyKinds = ['lead']`).
String? leadHistoryTag({
  required String parentModel,
  required String parentId,
  required String customerId,
  String? reference,
  Map<String, String> leadRefs = const {},
}) {
  if (parentModel != 'lead' || parentId.isEmpty || parentId == customerId) return null;
  final name = (reference ?? '').isNotEmpty ? reference : leadRefs[parentId];
  return (name ?? '').isEmpty ? 'From lead' : 'From lead $name';
}

/// A task's / follow-up's parent from its raw `related_to` (an object
/// `{model, id, label, reference}` on the list endpoint).
({String model, String id, String? reference}) relatedParentOf(Map<String, dynamic> raw) {
  final rel = raw['related_to'];
  if (rel is Map) {
    return (
      model: _str(rel['model'] ?? rel['kind']).toLowerCase(),
      id: _str(rel['id']),
      reference: _str(rel['reference']).isEmpty ? null : _str(rel['reference']),
    );
  }
  return (
    model: _str(raw['related_to_model'] ?? rel).toLowerCase(),
    id: _str(raw['related_to_object_id'] ?? raw['related_to_id']),
    reference: null,
  );
}

const _sourceKindLabels = {
  'lead': 'Lead',
  'customer': 'Customer',
  'task': 'Task',
  'followup': 'Follow-up',
  'quotation': 'Quote',
  'call_log': 'Call log',
  'crmcalllog': 'Call log',
  'note': 'Note',
  'issue': 'Ticket',
  'product': 'Product',
  'project': 'Project',
  'project_task': 'Project task',
};

/// How a note on the customer's thread is tagged (webapp `noteSourceTag`): its
/// own notes plain (null); the converted lead's notes "From lead LD-…" and
/// read-only; other rolled-up notes "Task · Call back".
({String text, bool readOnly})? noteSourceTag(Object? source, String customerId) {
  if (source is! Map) return null;
  final id = _str(source['id']);
  if (id.isEmpty || id == customerId) return null;
  final kind = _str(source['kind']).isNotEmpty ? _str(source['kind']) : _str(source['model']);
  final reference = _str(source['reference']);
  final label = _str(source['label']);
  if (kind == 'lead') {
    final name = reference.isNotEmpty ? reference : label;
    return (text: name.isEmpty ? 'From lead' : 'From lead $name', readOnly: true);
  }
  final kindLabel = _sourceKindLabels[kind] ?? 'Record';
  final name = kind == 'customer'
      ? (reference.isNotEmpty ? reference : label)
      : (label.isNotEmpty ? label : reference);
  return (text: name.isEmpty ? kindLabel : '$kindLabel · $name', readOnly: false);
}

// ───────────────────────────── Tasks ─────────────────────────────

/// Webapp `dueBadge`: Done, else Overdue / Today / Upcoming by the due day;
/// null when there is no due date (the row then shows the status pill).
String? taskDueBadge({required DateTime? due, required bool done, DateTime? now}) {
  if (done) return 'Done';
  if (due == null) return null;
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(due.year, due.month, due.day);
  if (day.isBefore(today)) return 'Overdue';
  if (day == today) return 'Today';
  return 'Upcoming';
}

// ───────────────────────────── Opportunities ─────────────────────────────

/// One entry of the customer record's `linked_leads` — its source lead and
/// every upsell lead.
class CustomerLinkedLead {
  const CustomerLinkedLead({
    required this.id,
    required this.name,
    required this.reference,
    required this.relation,
    required this.isConverted,
    required this.statusName,
    required this.statusColor,
    required this.value,
    required this.quotesCount,
    required this.acceptedQuoteNumber,
    required this.acceptedQuoteTotal,
    required this.ownerName,
    required this.createdAt,
    required this.convertedOn,
  });

  final String id;
  final String name;
  final String reference;

  /// `source` (the original deal) or `upsell`.
  final String relation;
  final bool isConverted;
  final String statusName;
  final String statusColor;
  final double? value;
  final int? quotesCount;
  final String acceptedQuoteNumber;

  /// The accepted quote's grand total (incl. GST).
  final double? acceptedQuoteTotal;
  final String ownerName;
  final String createdAt;
  final String convertedOn;

  bool get isSource => relation == 'source';

  static List<CustomerLinkedLead> listFrom(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map && _str(e['lead_id']).isNotEmpty) CustomerLinkedLead.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  factory CustomerLinkedLead.fromJson(Map<String, dynamic> j) {
    final aq = j['accepted_quote'];
    final owner = j['owner'];
    final qc = j['quotes_count'];
    final relation = _str(j['relation']);
    return CustomerLinkedLead(
      id: _str(j['lead_id']),
      name: _str(j['lead_name']).isNotEmpty ? _str(j['lead_name']) : _str(j['reference']),
      reference: _str(j['reference']),
      relation: relation.isNotEmpty ? relation : (j['is_upsell'] == true ? 'upsell' : 'source'),
      isConverted: j['is_converted'] == true,
      statusName: _str(j['status_name']),
      statusColor: _str(j['status_color']),
      value: _optNum(j['lead_value']),
      quotesCount: qc is num ? qc.toInt() : null,
      acceptedQuoteNumber: aq is Map ? _str(aq['quotation_number']) : '',
      acceptedQuoteTotal: aq is Map ? (_optNum(aq['grand_total']) ?? _optNum(aq['taxable_total'])) : null,
      ownerName: owner is Map ? _str(owner['name']) : _str(owner),
      createdAt: _str(j['created_at']),
      convertedOn: _str(j['converted_on']),
    );
  }

  /// "1 quote · QTN-00008 accepted (₹3,94,758 incl. GST)".
  String? get quotesLine {
    final n = quotesCount;
    if (n == null) return null;
    final count = '$n quote${n == 1 ? '' : 's'}';
    if (acceptedQuoteNumber.isEmpty) return count;
    final total = acceptedQuoteTotal == null ? '' : ' (${activityMoney(acceptedQuoteTotal)} incl. GST)';
    return '$count · $acceptedQuoteNumber accepted$total';
  }

  /// "Opened 4 Oct 2026 · Converted 5 Oct 2026".
  String get datesLine => [
        if (createdAt.isNotEmpty) 'Opened ${activityDate(createdAt)}',
        if (convertedOn.isNotEmpty) 'Converted ${activityDate(convertedOn)}',
      ].join(' · ');

  /// Owner · quotes · dates.
  String get metaLine =>
      [ownerName, quotesLine ?? '', datesLine].where((s) => s.isNotEmpty).join(' · ');
}
