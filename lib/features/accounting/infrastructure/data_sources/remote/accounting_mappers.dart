import '../../../domain/entities/acc_document.dart';
import '../../../domain/entities/acc_ledger.dart';
import '../../../domain/entities/acc_masters.dart';
import '../../../domain/entities/acc_periods.dart';
import '../../../domain/entities/acc_reports.dart';
import '../../../domain/entities/acc_settlement.dart';
import '../../../domain/entities/acc_setup.dart';

/// JSON → accounting entities. Every read is defensive: a missing or oddly
/// typed field falls back rather than throwing, and a row with no id is
/// skipped by the list mappers.
///
/// Money stays a string throughout — the server's own two-decimal text — so
/// nothing between the API and the screen can lose paise.

String? _s(Object? v) {
  if (v == null) return null;
  final s = '$v';
  return s.isEmpty ? null : s;
}

/// Money: accepts a string or a number, returns the server's string form.
String _m(Object? v, [String fallback = '0']) {
  if (v == null) return fallback;
  if (v is num) return v.toStringAsFixed(2);
  final s = '$v'.trim();
  return s.isEmpty ? fallback : s;
}

String? _mOpt(Object? v) => v == null ? null : _m(v);

bool _b(Object? v) => v == true || v == 'true';

int? _i(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const {};

List<Map<String, dynamic>> _rows(Object? v) => [
      if (v is List)
        for (final e in v)
          if (e is Map) Map<String, dynamic>.from(e),
    ];

/// Warnings arrive as objects (`{code, …context}`) or, on older rows, bare
/// strings. Both become a [DocWarning].
List<DocWarning> mapWarnings(Object? v) => [
      if (v is List)
        for (final w in v)
          if (w is Map)
            DocWarning(_s(w['code']) ?? 'UNKNOWN', Map<String, dynamic>.from(w))
          else if (w is String && w.isNotEmpty)
            DocWarning(w),
    ];

// ── Documents ──

AccDocumentLine mapDocumentLine(Map<String, dynamic> j) => AccDocumentLine(
      lineNo: _i(j['line_no']) ?? 0,
      productId: _s(j['product']),
      description: _s(j['description']) ?? '',
      hsnSac: _s(j['hsn_sac']),
      supplyNature: _s(j['supply_nature']),
      qty: _s(j['qty']) ?? '1',
      unit: _s(j['unit']),
      unitPrice: _m(j['unit_price']),
      lineDiscount: _mOpt(j['line_discount']),
      taxable: _mOpt(j['taxable']),
      taxTreatment: _s(j['tax_treatment']),
      ratePct: _s(j['rate_pct']),
      cessPct: _s(j['cess_pct']),
      rateVariantKey: _s(j['rate_variant_key']),
      rateMatchLevel: _s(j['rate_match_level']),
      taxCgst: _mOpt(j['tax_cgst']),
      taxSgst: _mOpt(j['tax_sgst']),
      taxIgst: _mOpt(j['tax_igst']),
      taxCess: _mOpt(j['tax_cess']),
    );

AccTaxLine mapTaxLine(Map<String, dynamic> j) => AccTaxLine(
      head: _s(j['head']) ?? '—',
      direction: _s(j['direction']),
      amount: _m(j['amount']),
      ratePct: _s(j['rate_pct']),
      itcStatus: _s(j['itc_status']),
    );

/// One document row. Null when it carries no `document_id`.
AccDocument? mapDocument(Map<String, dynamic> j) {
  final id = _s(j['document_id']);
  if (id == null) return null;
  final draftRows = j['config_draft_rows'];
  return AccDocument(
    id: id,
    docType: _s(j['doc_type']) ?? 'TAX_INVOICE',
    direction: _s(j['direction']) ?? 'OUTWARD',
    number: _s(j['number']),
    documentDate: _s(j['document_date']),
    supplyDate: _s(j['supply_date']),
    tosDate: _s(j['tos_date']),
    postingDate: _s(j['posting_date']),
    dueDate: _s(j['due_date']),
    customerId: _s(j['customer']),
    vendorId: _s(j['vendor']),
    vendorInvoiceNo: _s(j['vendor_invoice_no']),
    rcmApplies: _b(j['rcm_applies']),
    tdsAmount: _mOpt(j['tds_amount']),
    payable: _mOpt(j['payable']),
    paidAmount: _mOpt(j['paid_amount']),
    placeOfSupply: _s(j['place_of_supply_state_code']),
    supply: _s(j['supply']),
    transactionClass: _s(j['transaction_class']),
    amountsAre: _s(j['amounts_are']),
    currency: _s(j['currency']) ?? 'INR',
    taxableTotal: _m(j['taxable_total']),
    taxCgst: _m(j['tax_cgst']),
    taxSgst: _m(j['tax_sgst']),
    taxIgst: _m(j['tax_igst']),
    taxCess: _m(j['tax_cess']),
    roundOff: _m(j['round_off']),
    grandTotal: _m(j['grand_total']),
    status: _s(j['status']) ?? 'DRAFT',
    issuedAt: _s(j['issued_at']),
    cancelledAt: _s(j['cancelled_at']),
    cancelReason: _s(j['cancel_reason']),
    paymentState: _s(j['payment_state']) ?? 'NA',
    openBalance: _mOpt(j['open_balance']),
    settledBy: _s(j['settled_by']),
    referencesDocument: _s(j['references_document']),
    reasonCode: _s(j['reason_code']),
    withGst: j['with_gst'] is bool ? j['with_gst'] as bool : null,
    sourceType: _s(j['source_type']),
    sourceId: _s(j['source_id']),
    quotationId: _s(j['quotation_id']),
    paymentPlanId: _s(j['payment_plan_id']),
    paymentRecordId: _s(j['payment_record_id']),
    projectId: _s(j['project']),
    narration: _s(j['narration']),
    terms: _s(j['terms']),
    notes: _s(j['notes']),
    warnings: mapWarnings(j['warnings']),
    configDraftRows: draftRows is List ? draftRows.length : (_i(draftRows) ?? 0),
    partySnapshot: _map(j['party_snapshot']),
    lines: [for (final l in _rows(j['lines'])) mapDocumentLine(l)]
      ..sort((a, b) => a.lineNo.compareTo(b.lineNo)),
    taxLines: [for (final t in _rows(j['tax_lines'])) mapTaxLine(t)],
  );
}

List<AccDocument> mapDocuments(Object? rows) => [
      for (final r in _rows(rows))
        if (mapDocument(r) case final x?) x,
    ];

TaxPreview mapTaxPreview(Map<String, dynamic> j) {
  final totals = _map(j['totals']);
  return TaxPreview(
    supply: _s(j['supply']),
    transactionClass: _s(j['transaction_class']),
    amountsAre: _s(j['amounts_are']),
    lines: [
      for (final l in _rows(j['lines']))
        TaxPreviewLine(
          lineNo: _i(l['line_no']) ?? 0,
          hsnSac: _s(l['hsn_sac']),
          taxable: _mOpt(l['taxable']),
          ratePct: _s(l['rate_pct']),
          variantKey: _s(l['variant_key']),
          matchLevel: _s(l['match_level']),
          treatment: _s(l['treatment']) ?? _s(l['tax_treatment']),
        ),
    ],
    totals: {for (final e in totals.entries) e.key: _m(e.value)},
    configRows: [
      for (final c in _rows(j['config_rows']))
        ConfigRow(
          hsnSac: _s(c['hsn_sac']),
          ratePct: _s(c['rate_pct']),
          verificationStatus: _s(c['verification_status']),
        ),
    ],
    warnings: mapWarnings(j['warnings']),
  );
}

RateVariant? mapRateVariant(Map<String, dynamic> j) {
  final key = _s(j['variant_key']) ?? _s(j['rate_variant_key']);
  if (key == null) return null;
  return RateVariant(
    variantKey: key,
    hsnSac: _s(j['hsn_sac']),
    ratePct: _s(j['rate_pct']),
    description: _s(j['description']),
    isDefault: _b(j['is_default_variant']),
  );
}

List<RateVariant> mapRateVariants(Object? rows) => [
      for (final r in _rows(rows))
        if (mapRateVariant(r) case final x?) x,
    ];

// ── Masters ──

Vendor? mapVendor(Map<String, dynamic> j) {
  final id = _s(j['vendor_id']);
  if (id == null) return null;
  return Vendor(
    id: id,
    name: _s(j['name']) ?? '—',
    legalName: _s(j['legal_name']),
    email: _s(j['email']),
    phone: _s(j['phone']),
    address: _s(j['address']),
    stateCode: _s(j['state_code']),
    bankAccountNoMasked: _s(j['bank_account_no_masked']),
    ifsc: _s(j['ifsc']),
    isBodyCorporate: _b(j['is_body_corporate']),
    isGtaFcmOpted: _b(j['is_gta_fcm_opted']),
    isSmallTransporterDeclared: _b(j['is_small_transporter_declared']),
    isActive: j['is_active'] != false,
    notes: _s(j['notes']),
  );
}

List<Vendor> mapVendors(Object? rows) => [
      for (final r in _rows(rows))
        if (mapVendor(r) case final x?) x,
    ];

/// The current value of one effective-dated party attribute, unwrapped from
/// its JSON envelope (§7.5) — older rows hold a bare scalar.
String? _partyAttr(List<Map<String, dynamic>> attrs, String name, String key) {
  Map<String, dynamic>? current;
  for (final a in attrs) {
    if (_s(a['attribute']) != name) continue;
    if (a['effective_to'] == null) {
      current = a;
      break;
    }
    current ??= a;
  }
  if (current == null) return null;
  final v = current['value'];
  if (v is Map) return _s(v[key]);
  return _s(v);
}

PartyTaxProfile mapPartyTaxProfile(Map<String, dynamic> j) {
  final attrs = _rows(j['attributes']);
  return PartyTaxProfile(
    registrationType: _s(j['registration_type']) ??
        _partyAttr(attrs, 'REGISTRATION_TYPE', 'type'),
    gstin: _s(j['gstin']) ?? _partyAttr(attrs, 'GSTIN', 'gstin'),
    stateCode: _s(j['state_code']) ?? _partyAttr(attrs, 'STATE', 'state_code'),
    pan: _s(j['pan']),
    entityKind: _s(j['entity_kind']),
    tdsApplicable: _b(j['tds_applicable']),
    isBodyCorporate: _b(j['is_body_corporate']),
    currency: _s(j['currency']),
    tdsNatureDefault: _s(j['tds_nature_default']),
  );
}

ProductTaxProfile mapProductTaxProfile(Map<String, dynamic> j) => ProductTaxProfile(
      taxTreatmentDefault: _s(j['tax_treatment_default']),
      rateVariantKey: _s(j['rate_variant_key']),
      isRcmOutward: _b(j['is_rcm_outward']),
      cessApplicable: _b(j['cess_applicable']),
    );

BankAccount? mapBankAccount(Map<String, dynamic> j) {
  final id = _s(j['bank_account_id']);
  if (id == null) return null;
  return BankAccount(
    id: id,
    name: _s(j['name']) ?? '—',
    kind: _s(j['kind']) ?? 'BANK',
    accountNoMasked: _s(j['account_no_masked']),
    provider: _s(j['provider']),
    isDefault: _b(j['is_default']),
    isActive: j['is_active'] != false,
  );
}

List<BankAccount> mapBankAccounts(Object? rows) => [
      for (final r in _rows(rows))
        if (mapBankAccount(r) case final x?) x,
    ];

List<GstState> mapStates(Object? rows) => [
      for (final r in _rows(rows))
        if (_s(r['code']) != null)
          GstState(code: _s(r['code'])!, name: _s(r['name']) ?? '', alpha: _s(r['alpha']) ?? ''),
    ];

// ── Settlement ──

List<Allocation> _allocations(Object? rows) => [
      for (final a in _rows(rows))
        if (_s(a['document_id']) != null)
          Allocation(
            documentId: _s(a['document_id'])!,
            amountApplied: _m(a['amount_applied']),
            tdsApplied: _mOpt(a['tds_applied']),
            status: _s(a['status']),
          ),
    ];

AccReceipt? mapReceipt(Map<String, dynamic> j) {
  final id = _s(j['receipt_id']);
  if (id == null) return null;
  return AccReceipt(
    id: id,
    customerId: _s(j['customer_id']),
    date: _s(j['receipt_date']),
    amount: _m(j['amount']),
    method: _s(j['method']),
    sourceAccountKind: _s(j['source_account_kind']),
    reference: _s(j['reference']),
    tdsDeducted: _mOpt(j['tds_deducted']),
    unallocated: _mOpt(j['unallocated']),
    treatAs: _s(j['treat_as']),
    kind: _s(j['kind']),
    status: _s(j['status']) ?? 'POSTED',
    journalEntryId: _s(j['journal_entry_id']),
    allocations: _allocations(j['allocations']),
  );
}

List<AccReceipt> mapReceipts(Object? rows) => [
      for (final r in _rows(rows))
        if (mapReceipt(r) case final x?) x,
    ];

AccAdvance? mapAdvance(Map<String, dynamic> j) {
  final id = _s(j['advance_id']);
  if (id == null) return null;
  return AccAdvance(
    id: id,
    customerId: _s(j['customer_id']),
    supplyNature: _s(j['supply_nature']),
    supply: _s(j['supply']),
    ratePct: _s(j['rate_pct']),
    taxable: _mOpt(j['taxable']),
    remainingTaxable: _mOpt(j['remaining_taxable']),
    status: _s(j['status']) ?? 'OPEN',
    receiptId: _s(j['receipt_id']),
  );
}

List<AccAdvance> mapAdvances(Object? rows) => [
      for (final r in _rows(rows))
        if (mapAdvance(r) case final x?) x,
    ];

AccCustomerCredit? mapCustomerCredit(Map<String, dynamic> j) {
  final id = _s(j['credit_id']);
  if (id == null) return null;
  return AccCustomerCredit(
    id: id,
    customerId: _s(j['customer_id']),
    source: _s(j['source']),
    amount: _m(j['amount']),
    remaining: _mOpt(j['remaining']),
    status: _s(j['status']) ?? 'OPEN',
  );
}

List<AccCustomerCredit> mapCustomerCredits(Object? rows) => [
      for (final r in _rows(rows))
        if (mapCustomerCredit(r) case final x?) x,
    ];

AccVendorPayment? mapVendorPayment(Map<String, dynamic> j) {
  final id = _s(j['payment_id']);
  if (id == null) return null;
  return AccVendorPayment(
    id: id,
    vendorId: _s(j['vendor_id']),
    date: _s(j['payment_date']),
    amount: _m(j['amount']),
    tdsNow: _mOpt(j['tds_now']),
    sourceAccountKind: _s(j['source_account_kind']),
    reference: _s(j['reference']),
    kind: _s(j['kind']),
    status: _s(j['status']) ?? 'POSTED',
    journalEntryId: _s(j['journal_entry_id']),
    allocations: _allocations(j['allocations']),
  );
}

List<AccVendorPayment> mapVendorPayments(Object? rows) => [
      for (final r in _rows(rows))
        if (mapVendorPayment(r) case final x?) x,
    ];

AccVendorAdvance? mapVendorAdvance(Map<String, dynamic> j) {
  final id = _s(j['advance_id']) ?? _s(j['vendor_advance_id']);
  if (id == null) return null;
  return AccVendorAdvance(
    id: id,
    vendorId: _s(j['vendor_id']),
    amount: _m(j['amount']),
    tdsDeducted: _mOpt(j['tds_deducted']),
    remaining: _mOpt(j['remaining']),
    status: _s(j['status']) ?? 'ACTIVE',
  );
}

List<AccVendorAdvance> mapVendorAdvances(Object? rows) => [
      for (final r in _rows(rows))
        if (mapVendorAdvance(r) case final x?) x,
    ];

// ── Journal ──

JournalEntry? mapJournalEntry(Map<String, dynamic> j) {
  final id = _s(j['entry_id']);
  if (id == null) return null;
  return JournalEntry(
    id: id,
    entryNo: _s(j['entry_no']),
    eventType: _s(j['event_type']),
    postingDate: _s(j['posting_date']),
    narration: _s(j['narration']),
    totalDebit: _m(j['total_debit']),
    totalCredit: _m(j['total_credit']),
    reversesEntryId: _s(j['reverses_entry_id']),
    reversedByEntryId: _s(j['reversed_by_entry_id']),
    lines: [
      for (final l in _rows(j['lines']))
        JournalLine(
          lineNo: _i(l['line_no']) ?? 0,
          accountCode: _s(l['account_code']),
          role: _s(l['role']),
          debit: _m(l['debit']),
          credit: _m(l['credit']),
          memo: _s(l['memo']),
        ),
    ],
  );
}

List<JournalEntry> mapJournalEntries(Object? rows) => [
      for (final r in _rows(rows))
        if (mapJournalEntry(r) case final x?) x,
    ];

LedgerEvent? mapLedgerEvent(Map<String, dynamic> j) {
  final id = _s(j['event_id']);
  if (id == null) return null;
  return LedgerEvent(
    id: id,
    eventType: _s(j['event_type']),
    status: _s(j['status']) ?? 'RECEIVED',
    error: j['error'] is Map ? (_s((j['error'] as Map)['detail']) ?? '${j['error']}') : _s(j['error']),
    skipReason: _s(j['skip_reason']),
    receivedAt: _s(j['received_at']),
  );
}

List<LedgerEvent> mapLedgerEvents(Object? rows) => [
      for (final r in _rows(rows))
        if (mapLedgerEvent(r) case final x?) x,
    ];

// ── Periods ──

PeriodRegister mapPeriodRegister(Map<String, dynamic> j) => PeriodRegister(
      fiscalYearId: _s(j['fiscal_year_id']),
      fyLabel: _s(j['fy_label']),
      status: _s(j['status']),
      bookPeriods: [
        for (final p in _rows(j['book_periods']))
          if (_s(p['book_period_id']) != null)
            BookPeriod(
              id: _s(p['book_period_id'])!,
              periodNo: _i(p['period_no']),
              startDate: _s(p['start_date']),
              endDate: _s(p['end_date']),
              status: _s(p['status']) ?? 'OPEN',
            ),
      ],
      gstPeriods: [
        for (final p in _rows(j['gst_periods']))
          if (_s(p['gst_period_id']) != null)
            GstPeriod(
              id: _s(p['gst_period_id'])!,
              gstin: _s(p['gstin']),
              startDate: _s(p['start_date']),
              endDate: _s(p['end_date']),
              gstr1Status: _s(p['gstr1_status']) ?? 'OPEN',
              gstr3bStatus: _s(p['gstr3b_status']) ?? 'OPEN',
              settled: _b(p['settled']),
            ),
      ],
      tdsPeriods: [
        for (final p in _rows(j['tds_periods']))
          if (_s(p['tds_period_id']) != null)
            TdsPeriod(
              id: _s(p['tds_period_id'])!,
              quarter: _i(p['quarter']),
              startDate: _s(p['start_date']),
              endDate: _s(p['end_date']),
              status: _s(p['status']) ?? 'OPEN',
            ),
      ],
    );

PeriodChecklist mapChecklist(Map<String, dynamic> j) => PeriodChecklist(
      items: [
        for (final i in _rows(j['items']))
          ChecklistItem(
            code: _s(i['code']) ?? '—',
            label: _s(i['label']),
            severity: _s(i['severity']) ?? 'INFO',
            status: _s(i['status']) ?? 'PASS',
            detail: _s(i['detail']),
          ),
      ],
      blocking: [
        if (j['blocking'] is List)
          for (final b in j['blocking'] as List)
            if (b is String) b else if (b is Map && _s(b['code']) != null) _s(b['code'])!,
      ],
      canSettle: _b(j['can_settle']) || _b(j['can_close']),
    );

// ── Setup ──

TenantProfile mapTenantProfile(Map<String, dynamic> j) => TenantProfile(
      activationStatus: _s(j['activation_status']) ?? 'INACTIVE',
      entityType: _s(j['entity_type']),
      legalName: _s(j['legal_name']),
      pan: _s(j['pan']),
      tan: _s(j['tan']),
      stateCode: _s(j['state_code']),
      ledgerStartDate: _s(j['ledger_start_date']),
      defaultAmountsAre: _s(j['default_amounts_are']),
      defaultBillingMode: _s(j['default_billing_mode']),
      returnFrequency: _s(j['return_frequency']),
      activatedAt: _s(j['activated_at']),
    );

List<TenantAttribute> mapTenantAttributes(Object? rows) => [
      for (final r in _rows(rows))
        if (_s(r['attribute']) != null)
          TenantAttribute(
            attribute: _s(r['attribute'])!,
            value: r['value'],
            effectiveFrom: _s(r['effective_from']),
            effectiveTo: _s(r['effective_to']),
          ),
    ];

GatesReport mapGates(Map<String, dynamic> j) => GatesReport(
      gates: [
        for (final g in _rows(j['gates']))
          GateResult(gate: _s(g['gate']) ?? '—', passed: _b(g['passed']), detail: _s(g['detail'])),
      ],
      canActivate: _b(j['can_activate']),
      activationStatus: _s(j['activation_status']),
    );

// ── Reports ──

AgingReport mapAging(Map<String, dynamic> j, {required bool vendor}) {
  final idKey = vendor ? 'vendor_id' : 'customer_id';
  final nameKey = vendor ? 'vendor_name' : 'customer_name';
  final totals = _map(j['totals']);
  return AgingReport(
    asOf: _s(j['as_of']),
    rows: [
      for (final r in _rows(j['rows']))
        if (_s(r[idKey]) != null)
          AgingRow(
            partyId: _s(r[idKey])!,
            partyName: _s(r[nameKey]),
            buckets: {for (final b in agingBuckets) b: _m(r[b])},
            total: _m(r['total']),
          ),
    ],
    totals: {for (final e in totals.entries) e.key: _m(e.value)},
  );
}

PartyStatement mapStatement(Map<String, dynamic> j) => PartyStatement(
      dateFrom: _s(j['date_from']),
      dateTo: _s(j['date_to']),
      openingBalance: _m(j['opening_balance']),
      closingBalance: _m(j['closing_balance']),
      totalDebit: _m(j['total_debit']),
      totalCredit: _m(j['total_credit']),
      lines: [
        for (final l in _rows(j['lines']))
          StatementLine(
            date: _s(l['date']),
            kind: _s(l['kind']),
            docType: _s(l['doc_type']),
            reference: _s(l['reference']),
            refId: _s(l['ref_id']),
            debit: _m(l['debit']),
            credit: _m(l['credit']),
            balance: _m(l['balance']),
          ),
      ],
    );

List<ReportAccount> _accounts(Object? rows) => [
      for (final a in _rows(rows))
        ReportAccount(code: _s(a['code']), name: _s(a['name']) ?? '—', amount: _m(a['amount'])),
    ];

PnlReport mapPnl(Map<String, dynamic> j) => PnlReport(
      asOf: _s(j['as_of']),
      income: _accounts(j['income']),
      expense: _accounts(j['expense']),
      totalIncome: _m(j['total_income']),
      totalExpense: _m(j['total_expense']),
      netProfit: _m(j['net_profit']),
    );

BalanceSheetReport mapBalanceSheet(Map<String, dynamic> j) => BalanceSheetReport(
      asOf: _s(j['as_of']),
      assets: _accounts(j['assets']),
      liabilities: _accounts(j['liabilities']),
      equity: _accounts(j['equity']),
      netProfit: _m(j['net_profit']),
      totalAssets: _m(j['total_assets']),
      totalLiabilities: _m(j['total_liabilities']),
      totalEquity: _m(j['total_equity']),
      liabilitiesAndEquity: _m(j['liabilities_and_equity']),
      balanced: _b(j['balanced']),
    );

TrialBalanceReport mapTrialBalance(Map<String, dynamic> j) => TrialBalanceReport(
      asOf: _s(j['as_of']),
      groups: [
        for (final g in _rows(j['groups']))
          TrialBalanceGroup(
            bucket: _s(g['bucket']) ?? '—',
            debit: _m(g['debit']),
            credit: _m(g['credit']),
            accounts: [
              for (final a in _rows(g['accounts']))
                TrialBalanceAccount(
                  code: _s(a['code']),
                  name: _s(a['name']) ?? '—',
                  closingDebit: _m(a['closing_debit']),
                  closingCredit: _m(a['closing_credit']),
                ),
            ],
          ),
      ],
      totalDebit: _m(j['total_debit']),
      totalCredit: _m(j['total_credit']),
      balanced: _b(j['balanced']),
    );

TdsSummary mapTdsSummary(Map<String, dynamic> j) {
  final totals = _map(j['totals']);
  return TdsSummary(
    rows: [
      for (final r in _rows(j['rows']))
        TdsSummaryRow(
          natureKey: _s(r['nature_key']) ?? '—',
          quarter: _i(r['quarter']),
          base: _m(r['base']),
          deducted: _m(r['deducted']),
          deposited: _m(r['deposited']),
          pending: _m(r['pending']),
          count: _i(r['count']) ?? 0,
        ),
    ],
    totals: {
      for (final e in totals.entries)
        e.key: e.key == 'count' ? '${_i(e.value) ?? 0}' : _m(e.value),
    },
  );
}

GstSummary mapGstSummary(Map<String, dynamic> j) {
  final grand = _map(j['grand_totals']);
  return GstSummary(grandTotals: {
    for (final e in grand.entries)
      if (e.value is Map)
        e.key: {
          for (final h in (e.value as Map).entries)
            if (h.value is num || h.value is String) '${h.key}': _m(h.value),
        },
  });
}

ProjectFinancials? mapProjectFinancials(Object? v) {
  if (v is! Map) return null;
  final j = Map<String, dynamic>.from(v);
  return ProjectFinancials(
    billedTaxable: _m(j['billed_taxable']),
    billedGross: _m(j['billed_gross']),
    creditNotesTaxable: _m(j['credit_notes_taxable']),
    collected: _m(j['collected']),
    openAr: _m(j['open_ar']),
    purchaseTaxable: _m(j['purchase_taxable']),
    expenseTaxable: _m(j['expense_taxable']),
    vendorOpenAp: _m(j['vendor_open_ap']),
    grossMargin: _m(j['gross_margin']),
    asOfEntryNo: _s(j['as_of_entry_no']),
    updatedAt: _s(j['updated_at']),
  );
}
