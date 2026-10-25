import 'package:intl/intl.dart';

import '../../../core/network/app_error.dart';
import '../../../core/utils/relative_time.dart';
import '../domain/entities/view_schema.dart';

// Pure rules for the customer detail page — the webapp's
// `customerInfoFields.tsx`, `customerLostImpact.ts`, `customerDelete.ts`,
// `customerReference.ts` and the header facts of `CustomerDetailScreen.tsx`,
// ported so the mobile screen behaves the same and the rules can be tested
// without pumping a widget.

// ── Formatting ──

final NumberFormat _inrWhole = NumberFormat.currency(locale: 'en_IN', symbol: '', decimalDigits: 0);
final NumberFormat _inrPaise = NumberFormat.currency(locale: 'en_IN', symbol: '', decimalDigits: 2);

/// Webapp `money()`: `₹3,50,000` for whole rupees, `₹3,50,000.50` with paise,
/// `—` when unknown.
String webMoney(num? n) {
  if (n == null || !n.isFinite) return '—';
  final paise = (n.abs() * 100).round();
  final text = paise % 100 == 0 ? _inrWhole.format(paise ~/ 100) : _inrPaise.format(paise / 100);
  return '${n < 0 && paise > 0 ? '-₹' : '₹'}${text.trim()}';
}

/// Webapp `Intl.NumberFormat('en-IN', {style: 'currency', currency: 'INR',
/// maximumFractionDigits: 2})` as used by the Lost dialog — INR keeps two
/// decimals: `₹11,800.00`.
String lostMoney(num n) => '${n < 0 ? '-' : ''}₹${_inrPaise.format(n.abs()).trim()}';

/// A number off the wire (`350000.00`, `7`, `"12.5"`), or null.
num? numOf(Object? v) {
  if (v is num) return v.isFinite ? v : null;
  if (v is String && v.trim().isNotEmpty) return num.tryParse(v.trim());
  return null;
}

String strOf(Object? v) => v is String ? v : v == null ? '' : '$v';

String? _text(Object? v) {
  if (v is String && v.trim().isNotEmpty) return v.trim();
  if (v is num) return '$v';
  return null;
}

/// `7` for `7.0`, `12.5` otherwise — counts in labels never show `.0`.
String _n(num n) => n == n.roundToDouble() ? '${n.toInt()}' : '$n';

// ── Header ──

/// Webapp `customerCode`: the server's `reference` ("CUST-0065"), else the
/// short UUID head.
String customerCode(Map<String, dynamic>? row) {
  final ref = row?['reference'];
  if (ref is String && ref.trim().isNotEmpty) return ref.trim();
  final id = row?['customer_id'];
  return id is String && id.isNotEmpty ? '#${id.substring(0, id.length < 8 ? id.length : 8)}' : '';
}

/// Webapp `fmtDate`: "22 Oct 2026" (no zero padding), '' when unknown.
String customerSinceText(Object? statusEnteredAt) {
  final at = parseApiDate(statusEnteredAt);
  if (at == null) return '';
  return DateFormat('d MMM yyyy').format(at.toLocal());
}

/// The facts the detail header reads off the record.
class CustomerHeaderFacts {
  const CustomerHeaderFacts({
    required this.code,
    required this.organisation,
    required this.since,
    required this.dealValue,
    required this.received,
    required this.isConverted,
    required this.isUpsell,
    required this.isLost,
    required this.lostReason,
    required this.score,
  });

  factory CustomerHeaderFacts.fromRow(Map<String, dynamic>? row) {
    final leads = row?['linked_leads'];
    final linked = [for (final l in (leads is List ? leads : const [])) if (l is Map) l];
    return CustomerHeaderFacts(
      code: customerCode(row),
      organisation: strOf(row?['organization_name']).trim(),
      since: customerSinceText(row?['status_entered_at']),
      // Round 5: value = Σ converted deals (before GST); a directly-created
      // customer keeps its typed revenue as its value.
      dealValue: numOf(row?['deal_value']) ?? numOf(row?['revenue']),
      received: numOf(row?['revenue_received']),
      isConverted: linked.any((l) => l['is_converted'] == true),
      isUpsell: linked.any((l) => l['is_upsell'] == true),
      isLost: row?['status_type'] == 'lost',
      lostReason: describeLostReason(row?['lost_reason_name'], row?['lost_reason_note']),
      score: numOf(row?['score'])?.toInt(),
    );
  }

  final String code;
  final String organisation;
  final String since;
  final num? dealValue;
  final num? received;
  final bool isConverted;
  final bool isUpsell;
  final bool isLost;
  final String lostReason;
  final int? score;

  /// "CUST-0006 · Kerala Agro".
  String get subtitle => [if (code.isNotEmpty) code, if (organisation.isNotEmpty) organisation].join(' · ');
}

/// Webapp `describeLostReason`: "Budget cut — Q4 freeze", either alone, or
/// "No reason recorded".
String describeLostReason(Object? name, Object? note) {
  final n = _text(name);
  final t = _text(note);
  if (n != null && t != null) return '$n — $t';
  return n ?? t ?? 'No reason recorded';
}

const String convertedBannerLead = 'Converted to customer.';
const String convertedBannerBody =
    ' The originating lead stays pinned to Won; account details below can still be updated.';

// ── Lost impact ──

class CustomerOpenInvoice {
  const CustomerOpenInvoice({required this.id, required this.number, this.date, required this.amountDue, this.leadName});
  final String id;
  final String number;
  final String? date;
  final num amountDue;
  final String? leadName;
}

class CustomerLostImpact {
  const CustomerLostImpact({
    this.customerId = '',
    this.customerName,
    this.openInvoices = const [],
    this.amountDue = 0,
    this.canCredit = false,
    this.openInstalments = const [],
    this.draftInvoices = const [],
    this.moneyReceived = 0,
    this.paymentCount = 0,
    this.customerCredit,
    this.upsellLeads = const [],
    this.legacyQuotes = const [],
  });

  final String customerId;
  final String? customerName;
  final List<CustomerOpenInvoice> openInvoices;
  final num amountDue;
  final bool canCredit;

  /// `(amount, invoiced)` per open instalment.
  final List<({num amount, bool invoiced})> openInstalments;
  final List<String> draftInvoices;
  final num moneyReceived;
  final num paymentCount;
  final num? customerCredit;
  final List<String> upsellLeads;
  final List<String> legacyQuotes;

  bool get hasOpenInvoices => openInvoices.isNotEmpty;

  /// Webapp `toCustomerLostImpact` — the GET body, a 409 `cause`, or one
  /// `cause.customers[]` row. Null for anything that is not an object.
  static CustomerLostImpact? fromJson(Object? raw) {
    if (raw is! Map) return null;
    List<Map> rows(Object? v) => [for (final x in (v is List ? v : const [])) if (x is Map) x];
    num n0(Object? v) => numOf(v) ?? 0;
    final invoices = [
      for (final (i, x) in rows(raw['open_invoices']).indexed)
        CustomerOpenInvoice(
          id: _text(x['document_id']) ?? 'invoice-$i',
          number: _text(x['number']) ?? 'Invoice',
          date: _text(x['date']),
          amountDue: n0(x['amount_due']),
          leadName: _text(x['lead_name']),
        ),
    ];
    final money = raw['money_received'] is Map ? raw['money_received'] as Map : const {};
    return CustomerLostImpact(
      customerId: _text(raw['customer_id']) ?? '',
      customerName: _text(raw['customer_name']) ?? _text(raw['name']),
      openInvoices: invoices,
      amountDue: raw.containsKey('open_amount_due')
          ? n0(raw['open_amount_due'])
          : invoices.fold<num>(0, (s, x) => s + x.amountDue),
      canCredit: raw['can_credit'] == true,
      openInstalments: [
        for (final x in rows(raw['open_instalments'])) (amount: n0(x['amount_expected']), invoiced: x['invoiced'] == true),
      ],
      draftInvoices: [for (final x in rows(raw['draft_invoices'])) _text(x['number']) ?? 'Draft invoice'],
      moneyReceived: n0(money['amount']),
      paymentCount: n0(money['payment_count']),
      customerCredit: money['customer_credit'] == null ? null : n0(money['customer_credit']),
      upsellLeads: [for (final x in rows(raw['upsell_leads'])) _text(x['lead_name']) ?? 'Upsell lead'],
      legacyQuotes: [for (final x in rows(raw['legacy_quotes'])) _text(x['quotation_number']) ?? 'Quote'],
    );
  }
}

/// Webapp `customerLostImpactsFromCause` — the customers a 409
/// `LOST_HAS_OPEN_INVOICES` reports, only those with open invoices.
List<CustomerLostImpact> customerLostImpactsFromCause(Map<String, dynamic>? cause) {
  if (cause == null || cause.isEmpty) return const [];
  final list = cause['customers'];
  if (list is List) {
    return [
      for (final c in list)
        if (CustomerLostImpact.fromJson(c) case final i? when i.hasOpenInvoices) i,
    ];
  }
  final one = CustomerLostImpact.fromJson(cause);
  return one != null && one.hasOpenInvoices ? [one] : const [];
}

const String lostHasOpenInvoicesCode = 'LOST_HAS_OPEN_INVOICES';

/// Webapp `DealClosureSummary` lines, in order. Empty → no summary block.
List<String> lostSummaryLines(CustomerLostImpact impact) {
  final instalments = impact.openInstalments.where((r) => !r.invoiced).toList();
  final out = <String>[];
  if (instalments.isNotEmpty) {
    final total = instalments.fold<num>(0, (s, r) => s + r.amount);
    out.add('${instalments.length} open instalment${instalments.length == 1 ? '' : 's'} '
        '(${lostMoney(total)}) and their follow-up tasks are cancelled');
  }
  final d = impact.draftInvoices.length;
  if (d > 0) out.add('$d draft invoice${d == 1 ? ' is' : 's are'} voided');
  final q = impact.legacyQuotes.length;
  if (q > 0) {
    out.add('$q other quote${q == 1 ? '' : 's'} of this customer ${q == 1 ? 'is' : 'are'} closed the same way: '
        '${impact.legacyQuotes.join(', ')}');
  }
  final u = impact.upsellLeads.length;
  if (u > 0) {
    out.add('$u open upsell lead${u == 1 ? '' : 's'} move${u == 1 ? 's' : ''} to Lost with the same reason: '
        '${impact.upsellLeads.join(', ')}');
  }
  return out;
}

const String lostSummaryHeading = 'Marking this customer Lost closes its open deals:';

/// Webapp `describeMoneyReceived`; null when nothing was received and there is
/// no credit. The dialog appends "Next step: Refund via Accounts — only if the
/// customer asks for the money back."
String? describeMoneyReceived(CustomerLostImpact impact) {
  final credit = impact.customerCredit;
  if (impact.moneyReceived <= 0 && !(credit != null && credit > 0)) return null;
  final creditText = credit != null && credit > 0 ? ' (unapplied credit now ${lostMoney(credit)})' : '';
  return '${lostMoney(impact.moneyReceived)} already received stays with the customer as credit$creditText. '
      'Nothing is refunded automatically.';
}

/// Webapp `describeOpenInvoices`.
String describeOpenInvoices(int count, num amountDue) {
  final plural = count != 1;
  return '$count invoice${plural ? 's' : ''} (${lostMoney(amountDue)}) ${plural ? 'are' : 'is'} issued but unpaid '
      '— issuing credit notes will cancel ${plural ? 'them' : 'it'}.';
}

const String noLostReasonsCopy =
    'A lost reason is required. Ask an administrator to add lost reasons in Settings → Leads.';

// ── Delete ──

const String partyHasBooksCode = 'PARTY_HAS_BOOKS';
const String customerHasBooksCopy =
    'This customer can’t be deleted because accounting records (invoices, receipts or payments) reference it. '
    'Keep the customer and change its status instead.';
const String customerNotDeletableCopy = 'This customer can’t be deleted. Archive it instead.';
const String deleteForbiddenCopy = 'You don’t have permission to delete this customer. Ask a workspace admin.';
const String deleteNotFoundCopy = 'This customer no longer exists — it may already have been deleted.';
const String deleteNoPermissionCopy = "You don't have permission to delete records here. Ask a workspace admin.";

/// Webapp `customerDeleteGate`: `can_delete` + `delete_blocked_reason.message`.
/// An older server sends neither → allowed.
({bool allowed, String? reason}) customerDeleteGate(Map<String, dynamic>? row) {
  if (row == null || row['can_delete'] != false) return (allowed: true, reason: null);
  final raw = row['delete_blocked_reason'];
  final msg = raw is Map ? raw['message'] : null;
  return (allowed: false, reason: msg is String && msg.trim().isNotEmpty ? msg.trim() : customerNotDeletableCopy);
}

/// The Delete control: hidden for a read-only role; disabled with a reason
/// without `delete` or when the server refuses; enabled otherwise.
({bool visible, bool enabled, String? reason}) customerDeleteControl({
  required bool readOnly,
  required bool canDelete,
  required Map<String, dynamic>? row,
}) {
  if (readOnly) return (visible: false, enabled: false, reason: null);
  if (!canDelete) return (visible: true, enabled: false, reason: deleteNoPermissionCopy);
  final gate = customerDeleteGate(row);
  return (visible: true, enabled: gate.allowed, reason: gate.reason);
}

/// Webapp `customerDeleteErrorCopy`.
String customerDeleteErrorCopy(AppError e) {
  if (e.code == partyHasBooksCode) return customerHasBooksCopy;
  if (e.type == AppErrorType.forbidden) return deleteForbiddenCopy;
  if (e.type == AppErrorType.notFound) return deleteNotFoundCopy;
  return e.message.isNotEmpty ? e.bareMessage : 'Could not delete the customer.';
}

// ── Products ──

const String customerQuantityError = 'Quantities on a customer are whole numbers (1, 2, 3 …).';

/// Webapp `customerProductsPatch`: blank → 1; anything but a whole number ≥ 1
/// is refused.
({List<Map<String, dynamic>>? value, String? error}) customerProductsPatch(
    List<({String productId, String quantity})> items) {
  final out = <Map<String, dynamic>>[];
  for (final item in items) {
    final q = item.quantity.trim().isEmpty ? '1' : item.quantity.trim();
    if (!RegExp(r'^\d+(\.0+)?$').hasMatch(q) || num.parse(q) < 1) {
      return (value: null, error: customerQuantityError);
    }
    out.add({'product_id': item.productId, 'quantity': num.parse(q).toInt()});
  }
  return (value: out, error: null);
}

/// Webapp `customerProductRows`: the dialog's starting rows.
List<({String id, String label, String quantity})> customerProductRows(Object? v) {
  if (v is! List) return const [];
  return [
    for (final p in v)
      if (p is Map && p['product_id'] is String && (p['product_id'] as String).isNotEmpty)
        (
          id: p['product_id'] as String,
          label: _text(p['product_name']) ?? 'Product',
          quantity: _n(numOf(p['quantity']) ?? 1),
        ),
  ];
}

/// Webapp `productsText`: "Widget ×3, Gadget", "+n more" past three.
String productsText(Object? v) {
  if (v is! List || v.isEmpty) return '—';
  final parts = [
    for (final p in v)
      () {
        final m = p is Map ? p : const {};
        final name = _text(m['product_name']) ?? _text(m['product_code']) ?? 'Product';
        final q = numOf(m['quantity']);
        return q != null && q != 1 ? '$name ×${_n(q)}' : name;
      }(),
  ];
  return parts.length > 3 ? '${parts.take(3).join(', ')} +${parts.length - 3} more' : parts.join(', ');
}

// ── Assignees ──

/// `(user_id, full name)` per embedded assignee (a bare id has no name).
List<({String id, String name})> customerAssignees(Map<String, dynamic>? row) {
  final raw = row?['assignees'];
  if (raw is! List) return const [];
  final out = <({String id, String name})>[];
  for (final a in raw) {
    if (a is String && a.isNotEmpty) {
      out.add((id: a, name: ''));
    } else if (a is Map && a['user_id'] is String) {
      final full = _text(a['full_name']) ?? _text(a['username']) ?? _text(a['email']) ?? '';
      out.add((id: a['user_id'] as String, name: full));
    }
  }
  return out;
}

/// The picker's choices: assignable users not already assigned.
List<T> assignableNotAssigned<T>(List<T> users, String Function(T) idOf, Iterable<String> assigned) {
  final taken = assigned.toSet();
  return [for (final u in users) if (!taken.contains(idOf(u))) u];
}

// ── Info fields ──

const String slaPatchField = '__sla_patch__';

/// Webapp SLA option sets (§3b).
const List<int> slaHourCounts = [1, 2, 3, 4, 6, 8, 12, 24, 48];
const List<int> slaDayCounts = [1, 2, 3, 5, 7, 14, 30, 60, 90];
const List<int> slaMinuteCounts = [5, 10, 15, 30, 45];
const List<(String, String)> slaModes = [
  ('policy', 'Tenant SLA policy'),
  ('custom', 'Custom terms for this customer'),
];

/// `(value, label)` — values are `"<n>|<unit>"`.
List<(String, String)> slaOptions({bool withMinutes = false}) => [
      if (withMinutes) for (final n in slaMinuteCounts) ('$n|minutes', '$n minutes'),
      for (final n in slaHourCounts) ('$n|hours', '$n ${n == 1 ? 'hour' : 'hours'}'),
      for (final n in slaDayCounts) ('$n|days', '$n ${n == 1 ? 'day' : 'days'}'),
    ];

/// "Resolve within 3 days" — `—` when the pair is incomplete.
String slaText(Object? value, Object? unit, String verb) {
  final n = numOf(value);
  final u = strOf(unit);
  if (n == null || u.isEmpty) return '—';
  return '$verb ${_n(n)} ${n == 1 ? u.substring(0, u.length - 1) : u}'.trim();
}

/// Webapp `gstinWireValue`: no spaces, upper case; blank → null.
String? gstinWireValue(String raw) {
  final t = raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  return t.isEmpty ? null : t;
}

const String gstinPlaceholder = 'e.g. 32ABCDE1234F1Z5';
const String sourceHint =
    'Where the lead this customer was converted from came from. It stays with that lead, so it is read-only here.';

enum InfoEditKind { none, text, multiline, email, phone, number, date, boolean, select, products }

class CustomerInfoField {
  const CustomerInfoField({
    required this.name,
    required this.label,
    required this.value,
    this.kind = InfoEditKind.none,
    this.editValue = '',
    this.options = const [],
    this.placeholder,
    this.hint,
  });

  /// The schema name, or a synthetic one (`__sla_resolve`, `__sla_respond`,
  /// `__sla_mode`) for the composed SLA rows.
  final String name;
  final String label;
  final String value;
  final InfoEditKind kind;
  final String editValue;
  final List<(String, String)> options;
  final String? placeholder;

  /// Read-only explanation (Source).
  final String? hint;

  bool get editable => kind != InfoEditKind.none;
}

/// Fields rendered elsewhere on the page or composed (webapp `SKIP`).
const Set<String> _skip = {
  'name', 'status', 'assigned_to', 'assignees', 'assigned_team',
  'sla_mode', 'sla_value', 'sla_unit', 'first_response_value', 'first_response_unit',
};

const List<String> _addressParts = ['address_line1', 'address_line2', 'city', 'state_code', 'pincode', 'country'];

/// Webapp `ADDRESS_GSTIN_FIELD_NAMES` (+ the lead-only deal fields, which a
/// customer layout never has but must never render as plain rows either).
final Set<String> billingFieldNames = {
  for (final p in _addressParts) 'billing_$p',
  for (final p in _addressParts) 'delivery_$p',
  'gstin',
};

bool _present(Map<String, dynamic> row, ViewColumn c) {
  if (c.isCustom) {
    final cf = row['custom_fields'];
    return cf is Map && cf.containsKey(c.customKey);
  }
  return row.containsKey(c.name);
}

Object? _raw(Map<String, dynamic> row, ViewColumn c) {
  if (c.isCustom) {
    final cf = row['custom_fields'];
    return cf is Map ? cf[c.customKey] : null;
  }
  return row[c.name];
}

const _numericTypes = {'decimal', 'integer', 'number', 'float'};

String _display(Object? value, String type) {
  if (value == null || (value is String && value.trim().isEmpty)) return '—';
  if (type == 'boolean') return value == true ? 'Yes' : 'No';
  if (type == 'date' || type == 'datetime') {
    final d = parseApiDate(value);
    if (d != null) return DateFormat('d MMM yyyy').format(d.toLocal());
  }
  if (value is Map) return _text(value['name']) ?? _text(value['full_name']) ?? '—';
  if (value is List) {
    final parts = [for (final v in value) if (v is Map) _text(v['name']) ?? '' else '$v'];
    final s = parts.where((p) => p.isNotEmpty).join(', ');
    return s.isEmpty ? '—' : s;
  }
  if (value is num) return _n(value);
  return '$value'.trim();
}

/// "₹3,50,000 · Solar panels" — the read-only Value / Need row.
String valueNeedText(Object? v) {
  if (v is! Map) return '—';
  final revenue = numOf(v['value']);
  final need = strOf(v['need']).trim();
  final parts = [if (revenue != null) webMoney(revenue), if (need.isNotEmpty) need];
  return parts.isEmpty ? '—' : parts.join(' · ');
}

/// Webapp `buildCustomerInfoFields` + the "Billing & delivery" rows: the
/// Customer information list, in the org's order.
///
/// [industryOptions] / [hasProductsEditor] mirror the webapp's optional
/// arguments: absent → that row stays read-only.
({List<CustomerInfoField> info, List<CustomerInfoField> billing}) buildCustomerInfoFields({
  required Map<String, dynamic> row,
  required List<ViewColumn> columns,
  required bool editable,
  List<(String, String)>? industryOptions,
  bool hasProductsEditor = false,
}) {
  final info = <CustomerInfoField>[];
  final billing = <CustomerInfoField>[];
  final sorted = [...columns]..sort((a, b) => a.order.compareTo(b.order));

  for (final c in sorted) {
    if (_skip.contains(c.name) || !_present(row, c)) continue;
    final value = _raw(row, c);
    if (billingFieldNames.contains(c.name)) {
      final shown = strOf(value).trim();
      billing.add(c.name == 'gstin'
          ? CustomerInfoField(
              name: 'gstin',
              label: c.label,
              value: shown.isEmpty ? '—' : shown,
              kind: editable ? InfoEditKind.text : InfoEditKind.none,
              editValue: shown,
              placeholder: gstinPlaceholder,
            )
          : CustomerInfoField(
              name: c.name,
              label: c.label,
              value: shown.isEmpty ? '—' : shown,
              kind: editable ? InfoEditKind.text : InfoEditKind.none,
              editValue: shown,
            ));
      continue;
    }
    switch (c.name) {
      case 'source':
        info.add(CustomerInfoField(
            name: c.name, label: c.label, value: _text(value) ?? '—', hint: _text(value) == null ? null : sourceHint));
        continue;
      case 'value_need':
        info.add(CustomerInfoField(name: c.name, label: c.label, value: valueNeedText(value)));
        continue;
      case 'score':
        info.add(CustomerInfoField(name: c.name, label: c.label, value: value == null ? '—' : '${_n(numOf(value) ?? 0)} / 100'));
        continue;
      case 'industry':
        final canEdit = editable && industryOptions != null;
        info.add(CustomerInfoField(
          name: c.name,
          label: c.label,
          value: _text(row['industry_name']) ?? '—',
          kind: canEdit ? InfoEditKind.select : InfoEditKind.none,
          editValue: strOf(value),
          options: canEdit ? [('', 'No industry'), ...industryOptions] : const [],
        ));
        continue;
      case 'last_followup_at':
        final type = _text(row['last_followup_type']);
        info.add(CustomerInfoField(name: c.name, label: c.label, value: type ?? _display(value, 'datetime')));
        continue;
      case 'products':
        info.add(CustomerInfoField(
          name: c.name,
          label: c.label,
          value: productsText(value),
          kind: editable && hasProductsEditor ? InfoEditKind.products : InfoEditKind.none,
        ));
        continue;
      case 'revenue':
        final n = numOf(value);
        info.add(CustomerInfoField(
          name: c.name,
          label: c.label,
          value: n == null ? '—' : webMoney(n),
          kind: editable ? InfoEditKind.number : InfoEditKind.none,
          editValue: n == null ? '' : _n(n),
        ));
        continue;
      case 'email':
        info.add(CustomerInfoField(
            name: c.name, label: c.label, value: _display(value, c.type),
            kind: editable ? InfoEditKind.email : InfoEditKind.none, editValue: strOf(value)));
        continue;
      case 'phone':
      case 'mobile_no':
      case 'whatsapp_no':
        info.add(CustomerInfoField(
            name: c.name, label: c.label, value: _display(value, c.type),
            kind: editable ? InfoEditKind.phone : InfoEditKind.none, editValue: strOf(value)));
        continue;
    }
    final type = c.type;
    final kind = !editable
        ? InfoEditKind.none
        : c.hasChoices
            ? InfoEditKind.select
            : _numericTypes.contains(type)
                ? InfoEditKind.number
                : type == 'boolean'
                    ? InfoEditKind.boolean
                    : type == 'date'
                        ? InfoEditKind.date
                        : type == 'string'
                            ? InfoEditKind.text
                            : type == 'text'
                                ? InfoEditKind.multiline
                                : InfoEditKind.none; // FK / m2m / unknown → read-only
    var shown = _display(value, type);
    if (c.hasChoices && value != null) {
      for (final (v, l) in c.choices) {
        if (v == '$value') shown = l;
      }
    }
    info.add(CustomerInfoField(
      name: c.name,
      label: c.label,
      value: shown,
      kind: kind,
      editValue: type == 'boolean' ? (value == true ? 'true' : 'false') : strOf(value),
      options: c.hasChoices ? [('', '—'), ...c.choices] : const [],
    ));
  }

  // The name is edited here (the header only shows it).
  final name = strOf(row['name']);
  info.insert(
      0,
      CustomerInfoField(
        name: 'name',
        label: 'Name',
        value: name.isEmpty ? '—' : name,
        kind: editable ? InfoEditKind.text : InfoEditKind.none,
        editValue: name,
      ));

  // The GSTIN, unless the org shows the whole billing block.
  if (!columns.any((c) => c.name == 'gstin') && row.containsKey('gstin')) {
    final g = strOf(row['gstin']);
    info.add(CustomerInfoField(
      name: 'gstin',
      label: 'GSTIN',
      value: g.isEmpty ? '—' : g,
      kind: editable ? InfoEditKind.text : InfoEditKind.none,
      editValue: g,
      placeholder: gstinPlaceholder,
    ));
  }

  info.addAll(_slaFields(row, columns, editable));
  return (info: info, billing: billing);
}

List<CustomerInfoField> _slaFields(Map<String, dynamic> row, List<ViewColumn> columns, bool editable) {
  bool visible(String n) => columns.any((c) => c.name == n);
  final out = <CustomerInfoField>[];
  if (visible('sla_mode') && row.containsKey('sla_mode')) {
    final mode = strOf(row['sla_mode']).isEmpty ? 'custom' : strOf(row['sla_mode']);
    final label = slaModes.where((m) => m.$1 == mode).map((m) => m.$2).firstOrNull ?? mode;
    out.add(CustomerInfoField(
      name: '__sla_mode',
      label: 'SLA source',
      value: label,
      kind: editable ? InfoEditKind.select : InfoEditKind.none,
      editValue: mode,
      options: slaModes,
    ));
  }
  if (visible('sla_value') && row.containsKey('sla_value')) {
    final v = row['sla_value'];
    final u = row['sla_unit'];
    out.add(CustomerInfoField(
      name: '__sla_resolve',
      label: 'SLA',
      value: slaText(v, u, 'Resolve within'),
      kind: editable ? InfoEditKind.select : InfoEditKind.none,
      editValue: '${_n(numOf(v) ?? 7)}|${strOf(u).isEmpty ? 'days' : strOf(u)}',
      options: slaOptions(),
    ));
  }
  if (visible('first_response_value') && row.containsKey('first_response_value')) {
    final v = row['first_response_value'];
    final u = row['first_response_unit'];
    final set = numOf(v) != null && strOf(u).isNotEmpty;
    if (set || editable) {
      final current = set ? '${_n(numOf(v)!)}|${strOf(u)}' : '';
      final opts = [('', 'Not set'), ...slaOptions(withMinutes: true)];
      out.add(CustomerInfoField(
        name: '__sla_respond',
        label: 'Respond by',
        value: set ? slaText(v, u, 'Respond within') : 'Not set',
        kind: editable ? InfoEditKind.select : InfoEditKind.none,
        editValue: current,
        options: current.isEmpty || opts.any((o) => o.$1 == current)
            ? opts
            : [(current, slaText(v, u, '')), ...opts],
      ));
    }
  }
  return out;
}

/// The PATCH body for one edited field, or null when nothing should be sent
/// (unchanged, or a blank name). [input] is the editor's string value.
Map<String, dynamic>? customerFieldPatch(CustomerInfoField f, String input) {
  final v = input.trim();
  switch (f.name) {
    case 'name':
      return v.isEmpty || v == f.editValue.trim() ? null : {'name': v};
    case 'gstin':
      return {'gstin': gstinWireValue(input)};
    case 'industry':
      return {'industry': v.isEmpty ? null : v};
    case '__sla_mode':
      return {'sla_mode': v};
    case '__sla_resolve':
      final parts = v.split('|');
      return {'sla_value': num.parse(parts[0]).toInt(), 'sla_unit': parts[1]};
    case '__sla_respond':
      if (v.isEmpty) return {'first_response_value': null, 'first_response_unit': null};
      final parts = v.split('|');
      return {'first_response_value': num.parse(parts[0]).toInt(), 'first_response_unit': parts[1]};
  }
  final Object? value = switch (f.kind) {
    InfoEditKind.number => v.isEmpty ? null : num.tryParse(v.replaceAll(RegExp(r'[,\s]'), '')),
    InfoEditKind.boolean => v == 'true',
    InfoEditKind.date => v.isEmpty ? null : v,
    InfoEditKind.select => v.isEmpty ? null : v,
    _ => v,
  };
  if (f.name.startsWith('custom_fields.')) {
    return {
      'custom_fields': {f.name.substring('custom_fields.'.length): value},
    };
  }
  return {f.name: value};
}

/// Client-side check before a round trip (webapp `NOT_A_NUMBER`): null when OK.
String? customerFieldInputError(CustomerInfoField f, String input) {
  if (f.kind == InfoEditKind.number) {
    final t = input.trim().replaceAll(RegExp(r'[,\s]'), '');
    if (t.isNotEmpty && num.tryParse(t) == null) return 'Enter a number, e.g. 500000 or 12.5.';
  }
  if (f.name == 'name' && input.trim().isEmpty) return 'Enter a name.';
  return null;
}

/// The message an edit failure shows under the field — never `field: msg`.
/// A 412 reads "Changed elsewhere — …" and the editor offers Reload.
({String message, bool stale}) customerWriteError(AppError e) {
  if (e.statusCode == 412 || e.code == 'STALE_RECORD') {
    return (message: 'Changed elsewhere — ${e.message}', stale: true);
  }
  return (message: e.bareMessage, stale: false);
}

/// Webapp `isReadOnlyOnModule`: the module is granted but no write verb is.
bool isReadOnlyRole({required bool read, required bool create, required bool update, required bool delete}) =>
    read && !create && !update && !delete;
