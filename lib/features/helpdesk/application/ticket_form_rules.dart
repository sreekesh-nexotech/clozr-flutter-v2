import '../../crm/domain/entities/crm_catalog.dart';

/// The ticket form's rules and copy, kept pure so every branch is testable —
/// the webapp's `issueInput.ts`, `issueType.ts`, `ticketFormCopy.ts` and
/// `ticketBillingDefaults.ts`.

/// `reported_for` values: a customer's ticket, or an internal one.
const kReportedForClient = 'client';
const kReportedForInternal = 'self';

/// The webapp's three channels, as `(code, label)`.
const kTicketChannels = [('phone', 'Phone'), ('email', 'Email'), ('whatsapp', 'WhatsApp')];

/// What a ticket gets when nothing sets a priority — the model's own default.
const kDefaultTicketPriority = 'Medium';

const kTicketSubjectRequired = 'Give the ticket a subject.';

/// A customer ticket needs a customer; the copy points at the internal escape hatch.
const kTicketCustomerRequired =
    'Pick a customer — SLA is not applied to a ticket without one. For an internal ticket, set Reported for to Internal.';

/// Mirrors the server's `_validate_billing`.
const kBillableNeedsBasis = 'A billable ticket needs a billable amount or a billable product.';

/// Client-side checks before anything is sent (webapp `validateIssueInput`).
List<String> validateTicketInput({
  required String subject,
  required String? customerId,
  required String reportedFor,
  required bool billable,
  required bool hasAmount,
  required bool hasBillableProduct,
}) {
  final errors = <String>[];
  if (subject.trim().isEmpty) errors.add(kTicketSubjectRequired);
  if ((customerId == null || customerId.isEmpty) && reportedFor != kReportedForInternal) {
    errors.add(kTicketCustomerRequired);
  }
  if (billable && !hasAmount && !hasBillableProduct) errors.add(kBillableNeedsBasis);
  return errors;
}

/// The category's default priority in the org vocabulary, or null when the
/// category has none (or nothing is picked).
String? categoryDefaultPriority(List<CatalogOption> types, String? typeId) {
  if (typeId == null || typeId.isEmpty) return null;
  final raw = types.where((t) => t.id == typeId).firstOrNull?.defaultPriority?.trim() ?? '';
  for (final p in const ['Critical', 'High', 'Medium', 'Low']) {
    if (p.toLowerCase() == raw.toLowerCase()) return p;
  }
  return null;
}

/// The priority after the category changes: the new category's default (or
/// the plain default when it has none), unless the user already chose one.
String priorityAfterCategoryChange({
  required List<CatalogOption> types,
  required String? typeId,
  required String current,
  required bool pickedByUser,
}) {
  if (pickedByUser) return current;
  return categoryDefaultPriority(types, typeId) ?? kDefaultTicketPriority;
}

/// "Default for Inquiry" under the priority while it still follows the
/// category; null once the user picked one.
String? priorityHint({
  required List<CatalogOption> types,
  required String? typeId,
  required String priority,
  required bool pickedByUser,
}) {
  if (pickedByUser) return null;
  final def = categoryDefaultPriority(types, typeId);
  if (def == null || def != priority) return null;
  final name = types.where((t) => t.id == typeId).firstOrNull?.name ?? 'this category';
  return 'Default for $name';
}

// ── Customer picker ──

/// Why the customer list cannot be shown, or null to show it.
String? customerPickerNotice({
  required bool loading,
  required bool forbidden,
  required bool failed,
  String query = '',
}) {
  if (forbidden) return "You don't have permission to view customers.";
  if (failed) return "Couldn't load customers. Try again.";
  if (loading) return query.trim().isNotEmpty ? 'Searching customers…' : 'Loading customers…';
  return null;
}

String customerNoMatchText(String query) {
  final q = query.trim();
  return q.isNotEmpty ? 'No customers match “$q”' : 'No customers found';
}

/// Under the results when the server has more than one page.
String? customerResultsFooter(int shown, int total, String search) {
  if (total <= shown) return null;
  return search.trim().isNotEmpty
      ? 'Showing $shown of $total matches — keep typing to narrow them down.'
      : 'Showing $shown of $total customers — type to search them all.';
}

/// The line under the Customer field; null for none.
String? customerFieldHelper({required bool forbidden, required bool internal}) {
  if (forbidden) {
    return internal
        ? "You don't have permission to view customers."
        : "You don't have permission to view customers — ask your admin, or raise this as an internal ticket.";
  }
  if (internal) return 'Optional for internal tickets.';
  return null;
}

// ── SLA box ──

/// A customer's SLA terms (`sla_value` + `sla_unit`).
typedef CustomerSla = ({num value, String unit});

/// `GET customers/{id}/` → the SLA, or null unless it carries a usable,
/// non-negative size AND a unit.
CustomerSla? customerSlaFrom(Map<String, dynamic> json) {
  final raw = json['sla_value'];
  final value = raw is num ? raw : (raw is String && raw.trim().isNotEmpty ? num.tryParse(raw.trim()) : null);
  final unit = (json['sla_unit'] ?? '').toString().trim().toLowerCase();
  if (value == null || value < 0 || unit.isEmpty) return null;
  return (value: value, unit: unit);
}

/// "24 hours", "1 hour", "1 day" — or "No SLA" when unknown.
String formatSlaTarget(num? value, String? unit) {
  final u = (unit ?? '').trim().toLowerCase();
  if (value == null || u.isEmpty) return 'No SLA';
  final singular = u.endsWith('s') ? u.substring(0, u.length - 1) : u;
  final shown = value == value.roundToDouble() ? value.toInt().toString() : value.toString();
  return '$shown ${value == 1 ? singular : '${singular}s'}';
}

/// The deadline a ticket created at [start] gets — the backend's `sla_delta`
/// ("days unless told hours", calendar time).
DateTime slaDeadlineFrom(DateTime start, CustomerSla sla) {
  final ms = (sla.value * (sla.unit == 'hours' ? 3600000 : 86400000)).round();
  return start.add(Duration(milliseconds: ms));
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Tue 21 Oct, 07:45" (year added only when it differs from [now]'s).
String formatResolveBy(DateTime deadline, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final year = deadline.year == now.year ? '' : ' ${deadline.year}';
  return '${_weekdays[deadline.weekday - 1]} ${deadline.day} ${_months[deadline.month - 1]}$year, '
      '${two(deadline.hour)}:${two(deadline.minute)}';
}

/// The SLA box: an optional bold [headline] over the [detail] line.
typedef SlaPreview = ({String? headline, String detail});

const kSlaFollowsCustomer = "Follows the selected customer's configured SLA. Not editable per ticket.";

/// A "Resolve by" line appears only for a NEW ticket whose picked customer's
/// SLA could be read. Editing states the recalculation rule instead.
SlaPreview slaPreviewCopy({
  required bool isEditing,
  required String? customerId,
  required bool internal,
  required CustomerSla? customerSla,
  required DateTime now,
  bool customerChanged = false,
  bool resolved = false,
}) {
  final hasCustomer = customerId != null && customerId.isNotEmpty;
  if (isEditing) {
    if (!customerChanged) return (headline: null, detail: kSlaFollowsCustomer);
    if (resolved) return (headline: null, detail: 'A resolved ticket keeps the SLA it was resolved under.');
    if (!hasCustomer) {
      return (headline: null, detail: 'Saving without a customer removes the SLA — the ticket will have no deadline.');
    }
    return (
      headline: 'SLA recalculated on save',
      detail: customerSla != null
          ? '${formatSlaTarget(customerSla.value, customerSla.unit)} from this customer, counted from when the ticket was opened.'
          : "From the selected customer's SLA, counted from when the ticket was opened.",
    );
  }
  if (!hasCustomer) {
    return internal
        ? (headline: null, detail: 'No SLA applies — an internal ticket without a customer has no deadline.')
        : (headline: null, detail: kSlaFollowsCustomer);
  }
  if (customerSla == null) return (headline: null, detail: kSlaFollowsCustomer);
  return (
    headline: 'Resolve by ${formatResolveBy(slaDeadlineFrom(now, customerSla), now)}',
    detail: '${formatSlaTarget(customerSla.value, customerSla.unit)} customer SLA, counted from when the ticket is created. Not editable per ticket.',
  );
}

// ── Billing ──

/// `GET issues/billing-defaults/`: the tenant's GST basis for the amount and
/// the default SAC / rate an amount-only ticket is invoiced under.
typedef TicketBillingDefaults = ({bool inclusive, String? defaultSac, num? defaultGstRatePct});

TicketBillingDefaults? ticketBillingDefaultsFrom(Object? json) {
  if (json is! Map) return null;
  final basis = (json['amounts_are'] ?? '').toString().toUpperCase();
  if (basis != 'EXCLUSIVE' && basis != 'INCLUSIVE') return null;
  final sac = (json['default_sac'] ?? '').toString().trim();
  final rate = json['default_gst_rate_pct'];
  return (
    inclusive: basis == 'INCLUSIVE',
    defaultSac: sac.isEmpty ? null : sac,
    defaultGstRatePct: rate is num ? rate : (rate is String ? num.tryParse(rate) : null),
  );
}

/// "Billable amount (₹, excl. GST)" — the neutral label while the basis is unknown.
String billableAmountLabel(TicketBillingDefaults? d) =>
    d == null ? 'Billable amount (₹)' : 'Billable amount (₹, ${d.inclusive ? 'incl.' : 'excl.'} GST)';

/// The amount's hint: what it becomes on the invoice.
String billableAmountHint(TicketBillingDefaults? d, {required bool hasProduct}) {
  const base = 'An amount, a product, or both.';
  if (d == null) return base;
  final gst = d.inclusive ? 'GST is included in this amount' : 'GST is added on top of this amount';
  if (hasProduct) return '$base $gst.';
  if (d.defaultSac != null) {
    final rate = d.defaultGstRatePct != null ? ' at ${d.defaultGstRatePct}% GST' : '';
    return '$base Invoiced under SAC ${d.defaultSac}$rate; $gst.';
  }
  return '$base $gst. No default SAC for ticket charges yet — set one in Settings → Accounting, or pick a billable product.';
}

/// The server's billing-basis refusal — shown inline, like the client check.
bool isBillableBasisRefusal({Map<String, List<String>>? fieldErrors, required String message}) {
  if (fieldErrors?.containsKey('billable') ?? false) return true;
  return RegExp(r'billable.*(amount|product)', caseSensitive: false).hasMatch(message);
}
