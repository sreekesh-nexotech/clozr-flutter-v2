import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/app_error.dart';
import '../../../application/quote_builder/quote_builder_draft.dart';
import '../../../application/quote_builder/quote_tax.dart';
import '../../../application/quote_builder/quote_template_parts.dart';

/// The endpoints behind the quote builder (TAX / QUOTE / TPL handovers), the
/// same calls the web builder makes. HTTP + JSON mapping only.
class QuoteBuilderRemoteDataSource {
  const QuoteBuilderRemoteDataSource(this._api);

  final ApiService _api;

  static const _previewTax = '${ApiEndpoints.quotations}preview-tax/';
  static const _taxDefaults = '${ApiEndpoints.quotations}tax-defaults/';
  static const _clauses = '/quotations/clauses/';
  static const _hsnSearch = '/crm/products/hsn-search/';

  static List<Map<String, dynamic>> _rows(Object? body) {
    final raw = body is Map ? body['results'] : body;
    return raw is List ? [for (final r in raw) if (r is Map) Map<String, dynamic>.from(r)] : const [];
  }

  static String _s(Object? v) => v == null ? '' : (v is String ? v : v.toString());

  /// `GET /quotations/quotations/{id}/`.
  Future<SavedQuote> fetchQuote(String id) async {
    final body = await _api.get(ApiEndpoints.quotation(id));
    if (body is! Map) throw const AppError(type: AppErrorType.unknown, message: 'Could not load the quote.');
    return SavedQuote.fromJson(Map<String, dynamic>.from(body));
  }

  /// The template picker: `family=quote` is the server's allow-list (no
  /// invoice / receipt layouts) and `is_active=true` keeps retired ones out.
  Future<List<QuoteTemplateOption>> templates() async {
    final body = await _api.get(ApiEndpoints.quotationTemplates,
        query: {'family': 'quote', 'is_active': 'true', 'page_size': 100}, quiet: true);
    return [
      for (final r in _rows(body))
        if (_s(r['template_id'] ?? r['id']).isNotEmpty)
          QuoteTemplateOption(
            id: _s(r['template_id'] ?? r['id']),
            name: _s(r['template_name'] ?? r['name']),
            isDefault: r['is_default'] == true,
            isActive: r['is_active'] != false,
            category: _s(r['category']),
          ),
    ];
  }

  /// The template's own `field_definitions`.
  Future<List<TemplateField>> templateFields(String templateId) async {
    final body = await _api.get('${ApiEndpoints.quotationTemplates}$templateId/', quiet: true);
    return templateFieldsFromDetail(body is Map ? Map<String, dynamic>.from(body) : null);
  }

  /// The Item Quote layout config (headings, section defaults). A template
  /// with nothing to configure reads as an empty config.
  Future<TemplateLayoutConfig> templateConfig(String templateId) async {
    final body = await _api.get('${ApiEndpoints.quotationTemplates}$templateId/config/', quiet: true);
    return body is Map ? TemplateLayoutConfig.fromJson(Map<String, dynamic>.from(body)) : const TemplateLayoutConfig();
  }

  /// The "Quote details" fields for this template and party / quote.
  Future<List<SpotInputField>> spotInputs(String templateId, {String? leadId, String? customerId, String? quotationId}) async {
    final body = await _api.get('${ApiEndpoints.quotationTemplates}$templateId/spot-inputs/', query: {
      if (leadId != null && leadId.isNotEmpty) 'lead': leadId,
      if (customerId != null && customerId.isNotEmpty) 'customer': customerId,
      if (quotationId != null && quotationId.isNotEmpty) 'quotation': quotationId,
    }, quiet: true);
    final fields = body is Map ? body['fields'] : null;
    return fields is List
        ? [for (final f in fields) if (f is Map) SpotInputField.fromJson(Map<String, dynamic>.from(f))]
        : const [];
  }

  /// The active clause library.
  Future<List<LibraryClause>> clauseLibrary() async {
    final body = await _api.get(_clauses, query: {'is_active': 'true', 'page_size': 100}, quiet: true);
    final rows = _rows(body);
    return [
      for (var i = 0; i < rows.length; i++) LibraryClause.fromJson(rows[i], i),
    ].where((c) => c.isActive && c.id.isNotEmpty).toList();
  }

  /// `GET quotations/tax-defaults/` — the tenant's "Amounts are" default and
  /// whether recurring billing is on.
  Future<QuoteTaxDefaults> taxDefaults() async {
    final body = await _api.get(_taxDefaults, quiet: true);
    final j = body is Map ? body : const {};
    final a = _s(j['amounts_are']);
    return QuoteTaxDefaults(
      amountsAre: a == 'EXCLUSIVE' || a == 'INCLUSIVE' ? a : '',
      isAccountingTenant: j['is_accounting_tenant'] == true,
      rateSource: _s(j['rate_source']),
      recurringBillingEnabled: j['recurring_billing_enabled'] == true,
    );
  }

  /// The org's default **active** quote status, sent on create (never a
  /// deactivated default — the server refuses that).
  Future<String?> defaultStatusId() async {
    final body = await _api.get(ApiEndpoints.quotationStatuses, query: {'page_size': 100}, quiet: true);
    for (final r in _rows(body)) {
      if (r['is_default'] == true && r['is_active'] != false) return _s(r['quotation_status_id']);
    }
    return null;
  }

  /// `POST quotations/preview-tax/` — nothing is saved.
  Future<TaxPreview> previewTax(Map<String, dynamic> body) async {
    final res = await _api.post(_previewTax, body: body);
    return TaxPreview.fromJson(res is Map ? Map<String, dynamic>.from(res) : const {});
  }

  /// Unconverted leads matching [search] (server-side search, first 20). Rows
  /// flagged converted are dropped here too, in case the filter is ignored.
  Future<List<PartyOption>> searchLeads(String search) async {
    final body = await _api.get(ApiEndpoints.leads, query: {
      'page': 1,
      'page_size': 20,
      'is_converted': 'false',
      if (search.trim().isNotEmpty) 'search': search.trim(),
    });
    return [for (final r in _rows(body)) if (r['is_converted'] != true) leadOption(r)];
  }

  static PartyOption leadOption(Map<String, dynamic> r) {
    var label = '';
    for (final k in const ['lead_name', 'name', 'company', 'company_name', 'title', 'full_name']) {
      if (_s(r[k]).trim().isNotEmpty) {
        label = _s(r[k]);
        break;
      }
    }
    final id = _s(r['lead_id'] ?? r['id']);
    return PartyOption(
      id: id,
      label: '${label.isEmpty ? id : label}${r['is_upsell'] == true ? ' · upsell' : ''}',
      sub: _s(r['reference']),
    );
  }

  Future<List<PartyOption>> searchCustomers(String search) async {
    final body = await _api.get(ApiEndpoints.customers, query: {
      'page': 1,
      'page_size': 20,
      if (search.trim().isNotEmpty) 'search': search.trim(),
    });
    return [for (final r in _rows(body)) customerOption(r)];
  }

  static PartyOption customerOption(Map<String, dynamic> r) {
    var label = '';
    for (final k in const ['name', 'customer_name', 'company', 'company_name', 'contact_name', 'email']) {
      if (_s(r[k]).trim().isNotEmpty) {
        label = _s(r[k]);
        break;
      }
    }
    final id = _s(r['customer_id'] ?? r['id']);
    return PartyOption(id: id, label: label.isEmpty ? id : label, sub: _s(r['reference']));
  }

  /// The label of a preset lead / customer (`?lead=` / `?customer=`).
  Future<PartyOption?> partyById(QuoteFor kind, String id) async {
    try {
      final body = await _api.get(kind == QuoteFor.lead ? ApiEndpoints.lead(id) : ApiEndpoints.customer(id), quiet: true);
      if (body is! Map) return null;
      final row = Map<String, dynamic>.from(body);
      return kind == QuoteFor.lead ? leadOption(row) : customerOption(row);
    } on AppError {
      return null;
    }
  }

  /// Rate-master codes matching [q] (≥ 2 characters).
  Future<List<HsnCode>> hsnSearch(String q) async {
    final body = await _api.get(_hsnSearch, query: {'q': q, 'limit': 20}, quiet: true);
    return [
      for (final r in _rows(body))
        HsnCode(
          code: _s(r['code']),
          supplyNature: _s(r['supply_nature']).isNotEmpty
              ? _s(r['supply_nature'])
              : (_s(r['code']).startsWith('99') ? 'SERVICE' : 'GOODS'),
          defaultVariantKey: _s(r['default_variant_key']),
          needsVariantChoice: r['needs_variant_choice'] == true,
          rates: [
            for (final v in (r['rates'] is List ? r['rates'] as List : const []))
              if (v is Map && _s(v['variant_key']).isNotEmpty)
                HsnRate(variantKey: _s(v['variant_key']), ratePct: _s(v['rate_pct']), condition: _s(v['description'])),
          ],
        ),
    ];
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async {
    final res = await _api.post(ApiEndpoints.quotations, body: body);
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  Future<Map<String, dynamic>> update(String id, Map<String, dynamic> body) async {
    final res = await _api.patch(ApiEndpoints.quotation(id), body: body);
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }
}

/// A row of the template picker.
class QuoteTemplateOption {
  const QuoteTemplateOption({
    required this.id,
    required this.name,
    this.isDefault = false,
    this.isActive = true,
    this.category = '',
  });

  final String id;
  final String name;
  final bool isDefault;
  final bool isActive;

  /// '' = the quote family.
  final String category;
}

class QuoteTaxDefaults {
  const QuoteTaxDefaults({
    this.amountsAre = '',
    this.isAccountingTenant = false,
    this.rateSource = '',
    this.recurringBillingEnabled = false,
  });

  final String amountsAre;
  final bool isAccountingTenant;
  final String rateSource;
  final bool recurringBillingEnabled;

  /// A typed line's GST rate follows its HSN/SAC (the rate master).
  bool get rateMaster => isAccountingTenant || rateSource == 'RATE_MASTER';
}

/// A lead or customer row in the "Quote for" picker.
class PartyOption {
  const PartyOption({required this.id, required this.label, this.sub = ''});
  final String id;
  final String label;

  /// The LD / CUST reference — never the raw uuid.
  final String sub;
}

class HsnRate {
  const HsnRate({required this.variantKey, required this.ratePct, this.condition = ''});
  final String variantKey;
  final String ratePct;
  final String condition;
}

class HsnCode {
  const HsnCode({
    required this.code,
    required this.supplyNature,
    this.defaultVariantKey = '',
    this.needsVariantChoice = false,
    this.rates = const [],
  });

  final String code;
  final String supplyNature;
  final String defaultVariantKey;
  final bool needsVariantChoice;
  final List<HsnRate> rates;
}

/// The rate master's longest-prefix ladder: goods 8 → 6 → 4 → 2 digits,
/// services 6 → 4. Null when [code] does not resolve.
HsnCode? resolveHsn(List<HsnCode> results, String code) {
  final c = code.trim();
  final nature = c.startsWith('99') ? 'SERVICE' : 'GOODS';
  final lengths = nature == 'GOODS' ? const [8, 6, 4, 2] : const [6, 4];
  for (final n in lengths) {
    if (c.length < n) continue;
    final prefix = c.substring(0, n);
    for (final r in results) {
      if (r.code == prefix && r.supplyNature == nature) return r;
    }
  }
  return null;
}
