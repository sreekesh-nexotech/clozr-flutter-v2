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
