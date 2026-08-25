import '../domain/entities/view_schema.dart';

/// The New quote form's state, and the `POST /quotations/quotations/` body it
/// becomes.
///
/// Kept apart from the widget so the request shape is testable without pumping
/// a screen — the payload contract is the part that must not drift.

/// One line item on a draft quote.
class QuoteDraftLine {
  const QuoteDraftLine({
    required this.description,
    required this.quantity,
    required this.unitPrice,
  });

  final String description;
  final int quantity;

  /// Rupees. Sent as a string because the API takes decimals as strings, and
  /// round-tripping through a double loses paise.
  final String unitPrice;

  Map<String, dynamic> toJson() => {
        'description': description,
        'quantity': quantity,
        'unit_price': unitPrice,
      };
}

/// The API's `payment_type` values, with the labels the form shows.
///
/// The enum is the contract — the old form sent display strings like
/// "Lump sum", which the server would have rejected.
enum QuotePaymentType {
  lumpsum('lumpsum', 'Lump sum'),
  subscription('subscription', 'Subscription'),
  installmentEven('installment_even', 'Installments – even split'),
  installmentCustom('installment_custom', 'Installments – custom amounts');

  const QuotePaymentType(this.value, this.label);

  final String value;
  final String label;

  /// Whether `num_installments` is required — the API demands it (>= 2) for an
  /// even split only.
  bool get needsInstallmentCount => this == QuotePaymentType.installmentEven;
}

/// A quote being composed.
class QuoteDraft {
  const QuoteDraft({
    required this.leadId,
    this.templateId,
    this.title = '',
    this.validUntil,
    this.paymentType = QuotePaymentType.lumpsum,
    this.numInstallments = 2,
    this.billingPeriodDays,
    this.notes = '',
    this.terms = '',
    this.currency = 'INR',
    this.lines = const [],
  });

  /// The only required field on create.
  final String leadId;

  /// Null lets the server apply the org's default template.
  final String? templateId;
  final String title;
  final DateTime? validUntil;
  final QuotePaymentType paymentType;
  final int numInstallments;
  final int? billingPeriodDays;
  final String notes;
  final String terms;
  final String currency;
  final List<QuoteDraftLine> lines;

  /// Whether this draft can be submitted at all: the API requires a lead, and a
  /// quote with no line items has no amount.
  bool get isSubmittable => leadId.isNotEmpty && lines.isNotEmpty;

  /// The create body.
  ///
  /// Only meaningful values are sent — the API treats an absent optional field
  /// as "use the org default", which an empty string would override with a
  /// blank. [schema] narrows this further: a field the org has configured away
  /// is not sent at all.
  ///
  /// `owner` and `customer` are deliberately never included. The server stamps
  /// the owner as the creating user regardless of what is sent, and a quote
  /// gains a customer only when its lead converts.
  Map<String, dynamic> toCreateJson({ViewSchema schema = ViewSchema.empty}) {
    bool wants(String column) => schema.shows(column);

    return {
      'lead': leadId,
      'currency': currency,
      if (templateId != null && templateId!.isNotEmpty) 'template': templateId,
      if (wants('quotation_title') && title.trim().isNotEmpty)
        'quotation_title': title.trim(),
      if (wants('valid_until') && validUntil != null)
        'valid_until': _isoDate(validUntil!),
      if (wants('payment_type')) 'payment_type': paymentType.value,
      if (wants('payment_type') && paymentType.needsInstallmentCount)
        'num_installments': numInstallments,
      if (wants('billing_period_days') &&
          paymentType == QuotePaymentType.subscription &&
          billingPeriodDays != null)
        'billing_period_days': billingPeriodDays,
      if (wants('notes') && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (wants('terms_and_conditions') && terms.trim().isNotEmpty)
        'terms_and_conditions': terms.trim(),
      'line_items': [for (final l in lines) l.toJson()],
    };
  }

  /// `YYYY-MM-DD`, the date form the API takes.
  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Columns the New quote form renders with widgets of its own, so the
/// schema-driven section never offers a second, differently-behaved box for the
/// same field.
///
/// Three reasons a name is here:
/// * **picker behaviour the generic form cannot express** — the lead is chosen
///   through a searchable sheet, the template writes an id while showing a
///   name, line items are a repeater with a running total;
/// * **interdependence** — a count applies only to an even split, a billing
///   period only to a subscription;
/// * **server-owned** — the owner is stamped on create, the number and totals
///   are computed, and a quote gains a customer only when its lead converts.
const quoteFormOwnedColumns = <String>{
  'lead',
  'template',
  'line_items',
  'currency',
  'payment_type',
  'num_installments',
  'billing_period_days',
  'owner',
  'customer',
  'quotation_number',
  'status',
  'total_amount',
};

/// The org's Quote layout minus the columns the form owns — the field set the
/// schema-driven section renders.
///
/// Everything else the org has configured visible comes through untouched, in
/// the org's order and under the org's labels, so a field an admin adds
/// tomorrow appears on the form with no code change.
ViewSchema quoteFormSchema(ViewSchema schema) => ViewSchema(
      columns: [
        for (final c in schema.columns)
          if (!quoteFormOwnedColumns.contains(c.name)) c,
      ],
      hasOrgConfig: schema.hasOrgConfig,
    );

/// Folds the schema-driven section's values into the create body.
///
/// Empty values are dropped rather than sent. This is a **create**: there is no
/// stored value to clear, and `""` would override the org's default with a
/// blank — the same rule [QuoteDraft.toCreateJson] applies to the fields it
/// owns. Nulls come from boxes left untouched (an empty date reads as null),
/// and are dropped for the same reason.
Map<String, dynamic> withSchemaFields(
  Map<String, dynamic> base,
  Map<String, dynamic> fields,
) {
  final out = {...base};
  for (final entry in fields.entries) {
    final value = entry.value;
    if (value == null) continue;
    if (value is String && value.trim().isEmpty) continue;
    if (value is Iterable && value.isEmpty) continue;
    out[entry.key] = value;
  }
  return out;
}
