/// The template-driven parts of the quote builder, ported from the webapp:
/// the template's own fields (`templateFields.ts`), the Item Quote layout's
/// section headings (`QuoteSectionsEditor.tsx`) and "Quote details" spot
/// inputs (`QuoteSpotInputsModal.tsx`), and the clause list (`clauseList.ts`).
///
/// Pure — no Flutter, so the write rules are unit-testable.
library;

String _s(Object? v) => v == null ? '' : (v is String ? v : v.toString());

// ── Template fields (`field_values`) ──────────────────────────────────────

enum TemplateFieldType { text, textarea, number, date, email, boolean, select }

class TemplateField {
  const TemplateField({
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    this.defaultValue = '',
    this.options = const [],
  });

  final String key;
  final String label;
  final TemplateFieldType type;
  final bool required;
  final String defaultValue;
  final List<String> options;
}

/// Template `field_type` (free text on the server) → the input to render.
TemplateFieldType templateFieldType(String? raw, bool hasOptions) {
  final t = (raw ?? '').trim().toLowerCase();
  if (hasOptions && const ['select', 'dropdown', 'choice', 'choices', 'radio'].contains(t)) {
    return TemplateFieldType.select;
  }
  if (const ['number', 'decimal', 'currency', 'integer', 'int', 'float', 'amount'].contains(t)) {
    return TemplateFieldType.number;
  }
  if (const ['boolean', 'checkbox', 'bool', 'toggle'].contains(t)) return TemplateFieldType.boolean;
  if (t == 'date') return TemplateFieldType.date;
  if (t == 'email') return TemplateFieldType.email;
  if (const ['textarea', 'longtext', 'long_text', 'multiline', 'rich_text'].contains(t)) {
    return TemplateFieldType.textarea;
  }
  return TemplateFieldType.text;
}

/// `GET quotations/templates/{id}/` → its `field_definitions`. Malformed
/// definitions are skipped; a duplicated key keeps the first.
List<TemplateField> templateFieldsFromDetail(Map<String, dynamic>? detail) {
  final defs = detail?['field_definitions'];
  if (defs is! List) return const [];
  final seen = <String>{};
  final out = <TemplateField>[];
  for (final d in defs) {
    if (d is! Map) continue;
    final key = _s(d['field_key']).trim();
    if (key.isEmpty || !seen.add(key)) continue;
    final opts = (d['options'] ?? d['choices']);
    final options = opts is List ? [for (final o in opts) _s(o)] : <String>[];
    out.add(TemplateField(
      key: key,
      label: _s(d['field_label']).trim().isEmpty ? key : _s(d['field_label']).trim(),
      type: templateFieldType(_s(d['field_type']), options.isNotEmpty),
      required: d['is_required'] == true,
      defaultValue: _s(d['default_value']),
      options: options,
    ));
  }
  return out;
}

/// Keys the quote PDF always fills from the quote itself — an input for them
/// could never print what is typed, so the builder offers none.
const _serverFilledKeys = <String>{
  'notes',
  'terms_and_conditions',
  'valid_until',
  'quotation_number',
  'quotation_date',
  'total_amount',
  'currency',
  'lead_name',
  'lead_email',
  'lead_phone',
  'customer_address',
  'customer_company_name',
};

List<TemplateField> editableTemplateFields(List<TemplateField> fields) =>
    [for (final f in fields) if (!_serverFilledKeys.contains(f.key)) f];

const _trueWords = {'true', '1', 'yes', 'on'};
bool _toBool(Object? v) => v is bool ? v : _trueWords.contains(_s(v).trim().toLowerCase());

/// The value a field opens with: the stored one; on a new quote, the
/// template's default (an existing quote is never back-filled). A `bool` for a
/// checkbox, a `String` otherwise.
Object initialFieldValue(TemplateField f, Object? stored, bool isNew) {
  final has = stored != null && stored != '';
  if (f.type == TemplateFieldType.boolean) return has ? _toBool(stored) : (isNew ? _toBool(f.defaultValue) : false);
  if (has) return _s(stored);
  return isNew ? f.defaultValue : '';
}

/// The value shown now: an edit wins over the initial value.
Object fieldValueOf(TemplateField f, Map<String, Object> edits, Map<String, dynamic> stored, bool isNew) =>
    edits.containsKey(f.key) ? edits[f.key]! : initialFieldValue(f, stored[f.key], isNew);

/// A required field left blank (a checkbox is never "missing").
bool isFieldMissing(TemplateField f, Object value) =>
    f.required && f.type != TemplateFieldType.boolean && _s(value).trim().isEmpty;

/// The `field_values` to write. Keys the quote stores that this template does
/// not define are kept verbatim (`field_values` is replaced whole). A blank
/// clears a stored value; on a new quote blanks are left out.
Map<String, dynamic> toFieldValuesPayload(
  List<TemplateField> fields,
  Map<String, Object> edits,
  Map<String, dynamic> stored,
  bool isNew,
) {
  final out = <String, dynamic>{...stored};
  for (final f in fields) {
    final v = fieldValueOf(f, edits, stored, isNew);
    if (v is bool) {
      out[f.key] = v;
      continue;
    }
    final text = _s(v).trim();
    if (text.isNotEmpty) {
      out[f.key] = text;
    } else if (stored.containsKey(f.key)) {
      out[f.key] = '';
    }
  }
  return out;
}

bool fieldValuesChanged(Map<String, dynamic> payload, Map<String, dynamic> stored) {
  for (final k in {...payload.keys, ...stored.keys}) {
    if (payload[k] != stored[k]) return true;
  }
  return false;
}

// ── Item Quote layout: section headings + spot inputs ─────────────────────

class SectionOption {
  const SectionOption({required this.id, required this.title, this.isDefault = false, this.productTypeIds = const []});
  final String id;
  final String title;
  final bool isDefault;
  final List<String> productTypeIds;
}

class SectionHeading {
  const SectionHeading({required this.id, required this.label, this.isMandatory = false, this.options = const []});
  final String id;
  final String label;
  final bool isMandatory;
  final List<SectionOption> options;
}

/// One section pick (`{heading_id, content_id}`).
class SectionPick {
  const SectionPick(this.headingId, this.contentId);
  final String headingId;
  final String contentId;

  Map<String, dynamic> toJson() => {'heading_id': headingId, 'content_id': contentId};
}

/// `GET quotations/templates/{id}/config/` — what the builder reads of it.
class TemplateLayoutConfig {
  const TemplateLayoutConfig({this.needsConfiguration = false, this.headings = const [], this.sectionDefaults = const {}});

  factory TemplateLayoutConfig.fromJson(Map<String, dynamic> j) {
    final defaults = <String, String>{};
    final rawDefaults = j['section_defaults'];
    if (rawDefaults is Map) {
      rawDefaults.forEach((k, v) {
        if (_s(v).isNotEmpty) defaults[_s(k)] = _s(v);
      });
    }
    return TemplateLayoutConfig(
      needsConfiguration: j['needs_configuration'] == true,
      sectionDefaults: defaults,
      headings: [
        for (final h in (j['headings'] is List ? j['headings'] as List : const []))
          if (h is Map)
            SectionHeading(
              id: _s(h['section_heading_id']),
              label: _s(h['label']),
              isMandatory: h['is_mandatory'] == true,
              options: [
                for (final o in (h['options'] is List ? h['options'] as List : const []))
                  if (o is Map)
                    SectionOption(
                      id: _s(o['section_content_id']),
                      title: _s(o['title']),
                      isDefault: o['is_default'] == true,
                      productTypeIds: [for (final t in (o['product_type_ids'] is List ? o['product_type_ids'] as List : const [])) _s(t)],
                    ),
              ],
            ),
      ],
    );
  }

  /// The Item Quote layout (sections + spot inputs) applies to this template.
  final bool needsConfiguration;
  final List<SectionHeading> headings;
  final Map<String, String> sectionDefaults;
}

String pickFor(List<SectionPick> picks, String headingId) {
  for (final p in picks) {
    if (p.headingId == headingId) return p.contentId;
  }
  return '';
}

List<SectionPick> withPick(List<SectionPick> picks, String headingId, String contentId) => [
      for (final p in picks)
        if (p.headingId != headingId) p,
      if (contentId.isNotEmpty) SectionPick(headingId, contentId),
    ];

/// The picks a new quote starts with — the server's own preload rules: a
/// product-category match, else the admin's default, else a mandatory
/// heading's default option.
List<SectionPick> defaultSectionPicks(List<SectionHeading> headings, Map<String, String> defaults, Set<String> productTypeIds) {
  final out = <SectionPick>[];
  for (final h in headings) {
    SectionOption? chosen;
    for (final o in h.options) {
      if (o.productTypeIds.any(productTypeIds.contains)) {
        chosen = o;
        break;
      }
    }
    if (chosen == null && defaults[h.id] != null) {
      for (final o in h.options) {
        if (o.id == defaults[h.id]) chosen = o;
      }
    }
    if (chosen == null && h.isMandatory) {
      for (final o in h.options) {
        if (o.isDefault) {
          chosen = o;
          break;
        }
      }
    }
    if (chosen != null) out.add(SectionPick(h.id, chosen.id));
  }
  return out;
}

List<SectionHeading> missingMandatoryHeadings(List<SectionHeading> headings, List<SectionPick> picks) =>
    [for (final h in headings) if (h.isMandatory && pickFor(picks, h.id).isEmpty) h];

bool sectionPicksChanged(List<SectionPick> a, List<SectionPick> b) {
  String key(List<SectionPick> p) => ([for (final x in p) '${x.headingId}:${x.contentId}']..sort()).join('|');
  return key(a) != key(b);
}

/// The mandatory-heading notice (web wording).
String mandatoryHeadingsNotice(List<SectionHeading> missing) {
  final names = missing.map((h) => '“${h.label}”').join(', ');
  return '$names ${missing.length == 1 ? 'is a mandatory heading' : 'are mandatory headings'}'
      ' — choose an option before the quote is sent.';
}

/// `GET quotations/templates/{id}/spot-inputs/` row.
class SpotInputField {
  const SpotInputField({
    required this.key,
    required this.label,
    this.hint = '',
    this.multiline = false,
    this.source = 'spot',
    this.path = '',
    this.required = false,
    this.modelValue = '',
    this.spotValue = '',
    this.needsInput = false,
  });

  factory SpotInputField.fromJson(Map<String, dynamic> j) => SpotInputField(
        key: _s(j['key']),
        label: _s(j['label']),
        hint: _s(j['hint']),
        multiline: j['multiline'] == true,
        source: _s(j['source']).toLowerCase() == 'model' ? 'model' : _s(j['source']).toLowerCase() == 'api' ? 'api' : 'spot',
        path: _s(j['path']),
        required: j['required'] == true,
        modelValue: _s(j['model_value']),
        spotValue: _s(j['spot_value']),
        needsInput: j['needs_input'] == true,
      );

  final String key;
  final String label;
  final String hint;
  final bool multiline;
  final String source;
  final String path;
  final bool required;
  final String modelValue;
  final String spotValue;
  final bool needsInput;

  /// The hint the popup shows under the box.
  String get boxHint => source == 'model'
      ? 'The record\'s “${path.split('.').last.replaceAll('_', ' ')}” is empty — type a value for this quote.'
      : hint;
}

List<SpotInputField> fieldsNeedingInput(List<SpotInputField> fields) => [for (final f in fields) if (f.needsInput) f];

List<SpotInputField> missingRequiredSpot(List<SpotInputField> fields, Map<String, String> values) => [
      for (final f in fields)
        if (f.required && f.modelValue.isEmpty && (values[f.key] ?? f.spotValue).trim().isEmpty) f,
    ];

/// Typed spot values worth sending on a new quote (blanks left out).
Map<String, String> trimmedSpotValues(Map<String, String> values) => {
      for (final e in values.entries)
        if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
    };

// ── Clauses (`clauses`) ───────────────────────────────────────────────────

class LibraryClause {
  const LibraryClause({
    required this.id,
    required this.title,
    this.bodyHtml = '',
    this.isMandatory = false,
    this.isActive = true,
    this.effectiveDate = '',
    this.position = 0,
    this.defaultFamilies = const [],
    this.defaultProductTypeIds = const [],
  });

  factory LibraryClause.fromJson(Map<String, dynamic> j, int index) => LibraryClause(
        id: _s(j['clause_id']),
        title: _s(j['title']),
        bodyHtml: _s(j['body_html']),
        isMandatory: j['is_mandatory'] == true,
        isActive: j['is_active'] != false,
        effectiveDate: _s(j['effective_date']),
        position: j['position'] is num ? (j['position'] as num).toInt() : index,
        defaultFamilies: [for (final f in (j['default_families'] is List ? j['default_families'] as List : const [])) _s(f)],
        defaultProductTypeIds: [
          for (final f in (j['default_product_type_ids'] is List ? j['default_product_type_ids'] as List : const [])) _s(f)
        ],
      );

  final String id;
  final String title;
  final String bodyHtml;
  final bool isMandatory;
  final bool isActive;
  final String effectiveDate;
  final int position;
  final List<String> defaultFamilies;
  final List<String> defaultProductTypeIds;

  bool isEffective(String today) => isActive && (effectiveDate.isEmpty || effectiveDate.compareTo(today) <= 0);
}

enum ClauseOrigin { saved, defaulted, added }

class ClauseRow {
  const ClauseRow({
    required this.key,
    required this.title,
    this.quotationClauseId = '',
    this.clauseId = '',
    this.bodyHtml = '',
    this.isMandatory = false,
    this.origin = ClauseOrigin.added,
  });

  final String key;

  /// `quotation_clause_id` of a saved row; '' otherwise.
  final String quotationClauseId;

  /// Library `clause_id`; '' for an ad-hoc row.
  final String clauseId;
  final String title;
  final String bodyHtml;
  final bool isMandatory;
  final ClauseOrigin origin;
}

/// The defaults the server preloads on a new quote: in-effect clauses marked
/// for the quote family, those tied to a product category on the lines, and
/// every unscoped mandatory clause.
List<ClauseRow> defaultClauseRows(List<LibraryClause> library, Set<String> productTypeIds, String today) {
  final picked = [
    for (final c in library)
      if (c.isEffective(today) &&
          (c.defaultFamilies.contains('quote') ||
              c.defaultProductTypeIds.any(productTypeIds.contains) ||
              (c.isMandatory && c.defaultFamilies.isEmpty && c.defaultProductTypeIds.isEmpty)))
        c,
  ]..sort((a, b) => a.position != b.position ? a.position.compareTo(b.position) : a.title.compareTo(b.title));
  return [
    for (final c in picked)
      ClauseRow(
        key: 'default:${c.id}',
        clauseId: c.id,
        title: c.title,
        bodyHtml: c.bodyHtml,
        isMandatory: c.isMandatory,
        origin: ClauseOrigin.defaulted,
      ),
  ];
}

/// A saved quote's `clauses[]`, in order.
List<ClauseRow> savedClauseRows(List<Map<String, dynamic>> clauses) {
  final sorted = [...clauses]
    ..sort((a, b) => ((a['position'] as num?) ?? 0).compareTo((b['position'] as num?) ?? 0));
  return [
    for (final c in sorted)
      ClauseRow(
        key: 'saved:${_s(c['quotation_clause_id'])}',
        quotationClauseId: _s(c['quotation_clause_id']),
        clauseId: _s(c['clause_id']),
        title: _s(c['title']),
        bodyHtml: _s(c['body_html']),
        isMandatory: c['is_mandatory'] == true,
        origin: ClauseOrigin.saved,
      ),
  ];
}

/// A mandatory clause on the quote (saved) or preloaded cannot be removed; one
/// added in this session can be taken back off.
bool canRemoveClause(ClauseRow r) => !r.isMandatory || r.origin == ClauseOrigin.added;

List<ClauseRow> removeClause(List<ClauseRow> rows, String key) {
  final i = rows.indexWhere((r) => r.key == key);
  if (i < 0 || !canRemoveClause(rows[i])) return [...rows];
  return [...rows]..removeAt(i);
}

List<ClauseRow> moveClause(List<ClauseRow> rows, String key, int delta) {
  final from = rows.indexWhere((r) => r.key == key);
  final to = from + delta;
  if (from < 0 || to < 0 || to >= rows.length) return [...rows];
  final next = [...rows];
  final tmp = next[from];
  next[from] = next[to];
  next[to] = tmp;
  return next;
}

List<LibraryClause> addableClauses(List<LibraryClause> library, List<ClauseRow> rows, String today) {
  final present = {for (final r in rows) if (r.clauseId.isNotEmpty) r.clauseId};
  return [for (final c in library) if (c.isEffective(today) && !present.contains(c.id)) c];
}

List<ClauseRow> addLibraryClause(List<ClauseRow> rows, LibraryClause c) {
  if (rows.any((r) => r.clauseId == c.id)) return [...rows];
  return [
    ...rows,
    ClauseRow(
      key: 'added:${c.id}',
      clauseId: c.id,
      title: c.title,
      bodyHtml: c.bodyHtml,
      isMandatory: c.isMandatory,
      origin: ClauseOrigin.added,
    ),
  ];
}

/// The ordered `clauses` write: saved rows by id, the rest by library clause.
List<Map<String, dynamic>> toClauseWrites(List<ClauseRow> rows) => [
      for (final r in rows)
        r.quotationClauseId.isNotEmpty ? {'quotation_clause_id': r.quotationClauseId} : {'clause_id': r.clauseId},
    ];

const _entities = {
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#39;': "'",
  '&#x27;': "'",
  '&nbsp;': ' ',
};

/// A clause body as plain text (the HTML is never rendered raw).
String clauseText(String html) => html
    .replaceAll(RegExp(r'<\s*br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</\s*(p|div|li|h[1-6])\s*>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAllMapped(RegExp(r'&(amp|lt|gt|quot|nbsp|#39|#x27);'), (m) => _entities[m[0]] ?? m[0]!)
    .replaceAll(RegExp(r'[ \t]+\n'), '\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();
