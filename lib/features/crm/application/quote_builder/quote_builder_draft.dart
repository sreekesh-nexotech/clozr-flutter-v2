import 'quote_lines.dart';
import 'quote_tax.dart';
import 'quote_template_parts.dart';

/// The quote builder's form state and its two write mappers — a port of the
/// webapp's `builder/builderDraft.ts`:
/// * [toNewQuoteJson] — the `POST /quotations/quotations/` body. Title and
///   validity **are** sent (the old mobile form dropped both);
/// * [toQuoteUpdateJson] — the `PATCH` body carrying **only what changed**, so
///   a saved quote is never re-sent wholesale (untouched lines are not
///   re-priced, a locked or org-hidden field is never echoed).
///
/// Pure, no Flutter.

String _s(Object? v) => v == null ? '' : (v is String ? v : v.toString());
int? _i(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);

/// Who the quote is for. Lead mode picks an UNCONVERTED lead; a converted lead
/// is quoted from its customer, so customer mode sends only the customer and
/// the server resolves the lead (its source lead, else its newest upsell lead).
enum QuoteFor { lead, customer }

/// `payment_type` options, labelled as the web builder labels them.
const payTypeOptions = <(String, String)>[
  ('lumpsum', 'Lump sum'),
  ('installment_even', 'Installments – even split'),
  ('subscription', 'Subscription'),
  ('installment_custom', 'Milestone-based'),
];

String payTypeLabel(String value) {
  for (final o in payTypeOptions) {
    if (o.$1 == value) return o.$2;
  }
  return value;
}

/// Which payment-type dependent boxes show.
({bool installments, bool billing}) paymentFlags(String payType) => (
      installments: payType == 'installment_even',
      billing: payType == 'subscription' || payType.startsWith('installment'),
    );

/// `discount approval` state of a quote above the creator's limit.
const approvalPending = 'PENDING';

/// Human names of the builder fields an org's quote field settings can hide.
const hideableFieldLabels = <String, String>{
  'quotation_title': 'Quote title',
  'line_items': 'Line items',
  'notes': 'Notes',
  'terms_and_conditions': 'Terms & conditions',
  'field_values': 'Template fields',
  'valid_until': 'Valid until',
  'due_date': 'Due date',
  'contract_ref': 'Contract reference',
};

/// Detail keys the builder edits; any of them may be trimmed away by the org's
/// quote field settings.
const _builderKeys = [
  'template',
  'quotation_title',
  'line_items',
  'notes',
  'terms_and_conditions',
  'field_values',
  'valid_until',
  'due_date',
  'contract_ref',
  'num_installments',
  'billing_period_days',
];

/// A saved quote as the builder reads it (`GET /quotations/quotations/{id}/`).
class SavedQuote {
  const SavedQuote({
    required this.id,
    this.number = '',
    this.title = '',
    this.templateId = '',
    this.templateName = '',
    this.leadId = '',
    this.leadName = '',
    this.customerId = '',
    this.customerName = '',
    this.lines = const [],
    this.paymentType = '',
    this.numInstallments,
    this.billingPeriodDays,
    this.validUntil = '',
    this.dueDate = '',
    this.notes = '',
    this.terms = '',
    this.amountsAre = '',
    this.placeOfSupply = '',
    this.contractRef = '',
    this.fieldValues = const {},
    this.fieldValuesWarnings = const [],
    this.clauses = const [],
    this.sections = const [],
    this.isLocked = false,
    this.approvalStatus = '',
    this.discountPct = '',
    this.taxSummary,
    this.chargeSummary,
    this.missingKeys = const [],
    this.raw = const {},
  });

  factory SavedQuote.fromJson(Map<String, dynamic> j) {
    String fk(Object? v, String idKey) => v is Map ? _s(v[idKey]) : _s(v);
    List<Map<String, dynamic>> maps(Object? v) =>
        v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];
    final amounts = _s(j['amounts_are']);
    return SavedQuote(
      id: _s(j['quotation_id']),
      number: _s(j['quotation_number']),
      title: _s(j['quotation_title']),
      templateId: j['template'] is String ? j['template'] as String : '',
      templateName: _s(j['template_name']),
      leadId: fk(j['lead'], 'lead_id'),
      leadName: _s(j['lead_name']),
      customerId: fk(j['customer'], 'customer_id'),
      customerName: _s(j['customer_name']),
      lines: maps(j['line_items']),
      paymentType: _s(j['payment_type']),
      numInstallments: _i(j['num_installments']),
      billingPeriodDays: _i(j['billing_period_days']),
      validUntil: _s(j['valid_until']),
      dueDate: _s(j['due_date']),
      notes: _s(j['notes']),
      terms: _s(j['terms_and_conditions']),
      amountsAre: amounts == 'EXCLUSIVE' || amounts == 'INCLUSIVE' ? amounts : '',
      placeOfSupply: _s(j['place_of_supply_state_code']),
      contractRef: _s(j['contract_ref']),
      fieldValues: j['field_values'] is Map ? Map<String, dynamic>.from(j['field_values'] as Map) : const {},
      fieldValuesWarnings: [
        for (final w in maps(j['field_values_warnings']))
          if (_s(w['message']).isNotEmpty) _s(w['message']),
      ],
      clauses: maps(j['clauses']),
      sections: [
        for (final s in maps(j['sections'])) SectionPick(_s(s['heading_id']), _s(s['content_id'])),
      ],
      isLocked: j['is_locked'] == true,
      approvalStatus: _s(j['approval_status']),
      discountPct: _s(j['discount_pct']),
      taxSummary: TaxSummary.fromJson(j['tax_summary']),
      chargeSummary: ChargeSummary.fromJson(j['charge_summary']),
      missingKeys: [for (final k in _builderKeys) if (!j.containsKey(k)) k],
      raw: j,
    );
  }

  final String id;
  final String number;
  final String title;
  final String templateId;
  final String templateName;
  final String leadId;
  final String leadName;
  final String customerId;
  final String customerName;
  final List<Map<String, dynamic>> lines;
  final String paymentType;
  final int? numInstallments;
  final int? billingPeriodDays;
  final String validUntil;
  final String dueDate;
  final String notes;
  final String terms;
  final String amountsAre;
  final String placeOfSupply;
  final String contractRef;
  final Map<String, dynamic> fieldValues;
  final List<String> fieldValuesWarnings;
  final List<Map<String, dynamic>> clauses;
  final List<SectionPick> sections;
  final bool isLocked;
  final String approvalStatus;
  final String discountPct;
  final TaxSummary? taxSummary;
  final ChargeSummary? chargeSummary;

  /// Builder keys the response did not include (org-hidden).
  final List<String> missingKeys;

  /// The whole response — handed back to whoever opened the builder.
  final Map<String, dynamic> raw;

  bool get approvalIsPending => approvalStatus == approvalPending;
}

/// The hideable fields this quote's response did not include — shown
/// read-only and never written.
Set<String> hiddenFields(SavedQuote? q) =>
    {for (final k in q?.missingKeys ?? const <String>[]) if (hideableFieldLabels.containsKey(k)) k};

/// "Not included in your workspace's quote fields, so not editable here: …"
String hiddenFieldsNotice(Set<String> hidden) =>
    'Not included in your workspace’s quote fields, so not editable here: '
    '${hidden.map((k) => hideableFieldLabels[k]).join(', ')}.';

const Object _unset = Object();

/// The form state. Immutable; the screen swaps it on every change.
class BuilderDraft {
  const BuilderDraft({
    this.title = '',
    this.templateChoice,
    this.quoteFor = QuoteFor.lead,
    this.leadId = '',
    this.customerId = '',
    this.items = const [],
    this.linesDirty = false,
    this.payType = 'lumpsum',
    this.installments = '',
    this.billing = '',
    this.validUntil = '',
    this.dueDate = '',
    this.notes = '',
    this.terms = '',
    this.amountsAreChoice,
    this.serverFlip,
    this.placeOfSupply = '',
    this.contractRef = '',
    this.fieldEdits = const {},
    this.clauseRows,
    this.sectionPicks,
    this.spotValues = const {},
  });

  final String title;

  /// Picked template; null = the org's default quote template.
  final String? templateChoice;
  final QuoteFor quoteFor;
  final String leadId;
  final String customerId;
  final List<QuoteFormItem> items;

  /// Edit: a line was added / removed / changed (else the saved lines stay).
  final bool linesDirty;
  final String payType;
  final String installments;
  final String billing;

  /// `YYYY-MM-DD` or ''.
  final String validUntil;
  final String dueDate;
  final String notes;

  /// Free-text T&C — only for a quote with no clause rows (legacy mode).
  final String terms;

  /// Picked "Amounts are"; null = the tenant default.
  final String? amountsAreChoice;

  /// Edit, lines untouched: the flip the SERVER applies to its saved prices.
  final String? serverFlip;
  final String placeOfSupply;
  final String contractRef;

  /// Template field values the user changed (String, or bool for a checkbox).
  final Map<String, Object> fieldEdits;

  /// The clause list once changed; null = untouched (defaults / saved rows).
  final List<ClauseRow>? clauseRows;

  /// Section picks once changed; null = untouched.
  final List<SectionPick>? sectionPicks;

  /// "Quote details" values typed in the popup, saved into `field_values`.
  final Map<String, String> spotValues;

  factory BuilderDraft.empty({String leadId = '', String customerId = ''}) => BuilderDraft(
        leadId: leadId,
        customerId: customerId,
        quoteFor: customerId.isNotEmpty && leadId.isEmpty ? QuoteFor.customer : QuoteFor.lead,
        items: [QuoteFormItem.blank()],
      );

  /// The form for editing a saved quote.
  factory BuilderDraft.fromQuote(SavedQuote q) => BuilderDraft(
        title: q.title,
        templateChoice: q.templateId.isEmpty ? null : q.templateId,
        quoteFor: q.leadId.isNotEmpty ? QuoteFor.lead : QuoteFor.customer,
        leadId: q.leadId,
        customerId: q.customerId,
        items: itemsFromSavedLines(q.lines),
        payType: q.paymentType.isEmpty ? 'lumpsum' : q.paymentType,
        installments: q.numInstallments?.toString() ?? '',
        billing: q.billingPeriodDays?.toString() ?? '',
        validUntil: q.validUntil,
        dueDate: q.dueDate,
        notes: q.notes,
        terms: q.terms,
        amountsAreChoice: q.amountsAre.isEmpty ? null : q.amountsAre,
        placeOfSupply: q.placeOfSupply,
        contractRef: q.contractRef,
      );

  BuilderDraft copyWith({
    String? title,
    Object? templateChoice = _unset,
    QuoteFor? quoteFor,
    String? leadId,
    String? customerId,
    List<QuoteFormItem>? items,
    bool? linesDirty,
    String? payType,
    String? installments,
    String? billing,
    String? validUntil,
    String? dueDate,
    String? notes,
    String? terms,
    Object? amountsAreChoice = _unset,
    Object? serverFlip = _unset,
    String? placeOfSupply,
    String? contractRef,
    Map<String, Object>? fieldEdits,
    Object? clauseRows = _unset,
    Object? sectionPicks = _unset,
    Map<String, String>? spotValues,
  }) =>
      BuilderDraft(
        title: title ?? this.title,
        templateChoice: templateChoice == _unset ? this.templateChoice : templateChoice as String?,
        quoteFor: quoteFor ?? this.quoteFor,
        leadId: leadId ?? this.leadId,
        customerId: customerId ?? this.customerId,
        items: items ?? this.items,
        linesDirty: linesDirty ?? this.linesDirty,
        payType: payType ?? this.payType,
        installments: installments ?? this.installments,
        billing: billing ?? this.billing,
        validUntil: validUntil ?? this.validUntil,
        dueDate: dueDate ?? this.dueDate,
        notes: notes ?? this.notes,
        terms: terms ?? this.terms,
        amountsAreChoice: amountsAreChoice == _unset ? this.amountsAreChoice : amountsAreChoice as String?,
        serverFlip: serverFlip == _unset ? this.serverFlip : serverFlip as String?,
        placeOfSupply: placeOfSupply ?? this.placeOfSupply,
        contractRef: contractRef ?? this.contractRef,
        fieldEdits: fieldEdits ?? this.fieldEdits,
        clauseRows: clauseRows == _unset ? this.clauseRows : clauseRows as List<ClauseRow>?,
        sectionPicks: sectionPicks == _unset ? this.sectionPicks : sectionPicks as List<SectionPick>?,
        spotValues: spotValues ?? this.spotValues,
      );
}

/// Every quote expires: a new or changed validity date is not before
/// [today]. An unchanged saved date (an old draft's) is left alone.
bool validUntilInPast(String validUntil, String savedValidUntil, String today) {
  if (validUntil.isEmpty || validUntil == savedValidUntil) return false;
  return validUntil.compareTo(today) < 0;
}

int? _positiveInt(String raw) => raw.trim().isEmpty ? null : int.tryParse(raw.trim());

/// What the write mappers need besides the draft.
class BuilderWriteContext {
  const BuilderWriteContext({
    required this.templateId,
    required this.amountsAre,
    this.fields = const [],
    this.legacyTerms = false,
    this.savedTemplateId = '',
    this.statusId,
  });

  final String templateId;
  final String amountsAre;

  /// The selected template's (editable) field definitions.
  final List<TemplateField> fields;

  /// Legacy mode: the free-text T&C box is shown (no clause rows).
  final bool legacyTerms;
  final String savedTemplateId;

  /// The org's default active status (create only).
  final String? statusId;
}

/// The create body. Untouched catalog lines carry no unit price; an untouched
/// clause list / section picks are omitted (the server preloads its defaults).
Map<String, dynamic> toNewQuoteJson(BuilderDraft d, BuilderWriteContext ctx) {
  final flags = paymentFlags(d.payType);
  final lines = toLineRows(d.items);
  final fieldValues = {
    ...toFieldValuesPayload(ctx.fields, d.fieldEdits, const {}, true),
    ...trimmedSpotValues(d.spotValues),
  };
  final installments = flags.installments ? _positiveInt(d.installments) : null;
  final billing = flags.billing ? _positiveInt(d.billing) : null;
  return {
    // '' = templates could not be listed: the server applies the org default.
    if (ctx.templateId.isNotEmpty) 'template': ctx.templateId,
    if (d.quoteFor == QuoteFor.lead) 'lead': d.leadId else 'customer': d.customerId,
    if (ctx.statusId != null) 'status_id': ctx.statusId,
    if (d.title.isNotEmpty) 'quotation_title': d.title,
    'payment_type': d.payType,
    if (installments != null) 'num_installments': installments,
    if (billing != null) 'billing_period_days': billing,
    if (d.validUntil.isNotEmpty) 'valid_until': d.validUntil,
    if (d.dueDate.isNotEmpty) 'due_date': d.dueDate,
    if (d.notes.isNotEmpty) 'notes': d.notes,
    if (ctx.legacyTerms && d.terms.trim().isNotEmpty) 'terms_and_conditions': d.terms,
    if (ctx.amountsAre.isNotEmpty) 'amounts_are': ctx.amountsAre,
    if (d.placeOfSupply.isNotEmpty) 'place_of_supply_state_code': d.placeOfSupply,
    if (d.contractRef.isNotEmpty) 'contract_ref': d.contractRef,
    if (lines.isNotEmpty) 'line_items': lines,
    if (fieldValues.isNotEmpty) 'field_values': fieldValues,
    if (d.clauseRows != null) 'clauses': toClauseWrites(d.clauseRows!),
    if (d.sectionPicks != null) 'sections': [for (final p in d.sectionPicks!) p.toJson()],
  };
}

/// An edit: only the keys that differ from the saved quote. Empty = nothing
/// to save (the Save button stays disabled).
Map<String, dynamic> toQuoteUpdateJson(BuilderDraft d, SavedQuote q, BuilderWriteContext ctx) {
  final patch = <String, dynamic>{};
  final flags = paymentFlags(d.payType);
  final hidden = hiddenFields(q);
  bool shown(String k) => !hidden.contains(k);

  if (shown('quotation_title') && d.title != q.title) patch['quotation_title'] = d.title;
  final savedTemplate = q.templateId.isNotEmpty ? q.templateId : ctx.savedTemplateId;
  if (d.templateChoice != null && d.templateChoice!.isNotEmpty && d.templateChoice != savedTemplate) {
    patch['template'] = d.templateChoice;
  }
  if (d.payType != q.paymentType) patch['payment_type'] = d.payType;
  final installments = flags.installments ? _positiveInt(d.installments) : null;
  if (installments != null && installments != q.numInstallments) patch['num_installments'] = installments;
  final billing = flags.billing ? _positiveInt(d.billing) : null;
  if (billing != null && billing != q.billingPeriodDays) patch['billing_period_days'] = billing;
  // A date can be changed here, not cleared (the API takes a date, not a blank).
  if (shown('valid_until') && d.validUntil.isNotEmpty && d.validUntil != q.validUntil) {
    patch['valid_until'] = d.validUntil;
  }
  if (shown('due_date') && d.dueDate.isNotEmpty && d.dueDate != q.dueDate) patch['due_date'] = d.dueDate;
  if (shown('notes') && d.notes != q.notes) patch['notes'] = d.notes;
  if (shown('terms_and_conditions') && ctx.legacyTerms && d.terms != q.terms) {
    patch['terms_and_conditions'] = d.terms;
  }
  if (d.placeOfSupply != q.placeOfSupply) {
    patch['place_of_supply_state_code'] = d.placeOfSupply.isEmpty ? null : d.placeOfSupply;
  }
  if (shown('contract_ref') && d.contractRef != q.contractRef) patch['contract_ref'] = d.contractRef;
  if (ctx.amountsAre.isNotEmpty && ctx.amountsAre != q.amountsAre) {
    patch['amounts_are'] = ctx.amountsAre;
    // Lines untouched: the server converts its own saved prices.
    if (d.serverFlip != null) patch['price_conversion'] = d.serverFlip;
  }
  if (shown('line_items') && d.linesDirty) patch['line_items'] = toLineRows(d.items);
  if (shown('field_values') && (d.fieldEdits.isNotEmpty || d.spotValues.isNotEmpty)) {
    final payload = toFieldValuesPayload(ctx.fields, d.fieldEdits, q.fieldValues, false);
    // A typed spot value replaces the stored one; a blanked one clears it.
    for (final e in d.spotValues.entries) {
      payload[e.key] = e.value.trim();
    }
    if (fieldValuesChanged(payload, q.fieldValues)) patch['field_values'] = payload;
  }
  if (d.clauseRows != null) patch['clauses'] = toClauseWrites(d.clauseRows!);
  if (d.sectionPicks != null && sectionPicksChanged(d.sectionPicks!, q.sections)) {
    patch['sections'] = [for (final p in d.sectionPicks!) p.toJson()];
  }
  return patch;
}

// ── Footer hints (the disabled-button reasons, web wording) ────────────────

/// Muted "nothing chosen yet" reasons, in order.
String incompleteReason({required bool hasTemplate, required bool partyChosen, required bool hasNoLines}) {
  if (!hasTemplate) return 'Choose a template.';
  if (!partyChosen) return 'Choose who the quote is for.';
  if (hasNoLines) return 'Add at least one line item.';
  return '';
}

/// Red "fix this" reasons, in the web builder's priority.
String blockReason({
  required List<QuoteFormItem> items,
  required bool validityInPast,
  required bool recurringWithSubscription,
  required bool hasAmountsAre,
  required bool attemptedSave,
  required bool missingTemplateField,
}) {
  final problems = items.map(lineProblem).toSet();
  if (problems.contains(LineProblem.qty)) return 'Enter a quantity (at most 1,00,00,000) for every line.';
  if (problems.contains(LineProblem.price)) {
    return 'Enter a unit price (up to 6 decimals, at most ₹100 crore) for every typed line.';
  }
  if (problems.contains(LineProblem.description)) {
    return 'Describe every typed line — a line without a product needs a description.';
  }
  if (problems.contains(LineProblem.tax)) {
    return 'Check the typed lines’ tax: HSN/SAC is 4 to 8 digits, GST rate 0–100%.';
  }
  if (validityInPast) return 'The validity date can’t be in the past.';
  if (problems.contains(LineProblem.charge)) return 'Complete the billing period of every recurring line.';
  if (recurringWithSubscription) {
    return 'Recurring lines bill on their own schedule: choose lump sum or instalments for the one-time part.';
  }
  if (!hasAmountsAre) return 'Choose whether amounts include GST.';
  if (attemptedSave && missingTemplateField) return 'Fill the required template fields.';
  return '';
}

// ── Notices ────────────────────────────────────────────────────────────────

const lockedCopy =
    'This quote has been sent, so its prices, lines and terms are locked. Changes go through a revision.';

const paymentLockedCopy =
    'This quote has been sent, so its payment terms (plan type, instalments, billing period) are locked. '
    'The number of instalments, the interval and the first due date of a lump-sum or instalment plan are set '
    'in the Accept dialog (and can be re-split on the payment plan until something is paid or invoiced). '
    'To change anything else, revise the quote — the revision is sent again before it is accepted.';

const approvalCopy = 'Discount above your limit — needs approval before it can be sent.';
const approvalCopyNeutral = 'Discount above the approval limit — needs approval before it can be sent.';

const leadModeHint = 'Converted leads are quoted from their customer.';
const customerModeHint =
    'The quote is linked to the customer’s lead (its source lead, or its latest upsell lead).';
const customerNoLeadCopy =
    'This customer has no lead to quote against. Create an upsell lead for the customer first.';

const estimateNote = 'GST shown is an estimate; the tax invoice from Accounting carries the final figures.';

/// `"20"` → "20.00%".
String pct2(String raw) => '${(double.tryParse(raw) ?? 0).toStringAsFixed(2)}%';
