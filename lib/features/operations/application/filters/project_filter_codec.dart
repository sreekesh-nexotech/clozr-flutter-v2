import '../../../../core/filters/filter_models.dart';
import '../../../crm/domain/entities/crm_catalog.dart';

/// Translates the Projects drawer's [FilterValues] to the backend's
/// `/projects/projects/` **query params** (`operations.md` §1).
///
/// Only the fields the API documents are encoded. The rest stay local and are
/// listed in [localOnlyFields] so callers can keep matching them client-side
/// rather than silently dropping them.
///
/// Values are server ids where the API wants ids; the catalogs supply that
/// mapping. An empty catalog **passes the value through**, which keeps mock mode
/// working — there the option ids already are the values the rows carry.
class ProjectFilterCodec {
  const ProjectFilterCodec({
    this.statuses = const [],
    this.types = const [],
    this.customers = const [],
    this.currentUserId,
  });

  /// `/projects/project-statuses/` → `project_status_id`.
  final List<CatalogOption> statuses;

  /// `/projects/project-types/` → `project_type_id`.
  final List<CatalogOption> types;

  /// `/crm/customers/` → `customer_id`. The drawer's options are company
  /// **names** (that is what a list row carries), so this maps name → id.
  final List<CatalogOption> customers;

  final String? currentUserId;

  /// Drawer fields with no documented param — matched locally, never encoded.
  ///
  /// * `assignees` — §1 has `manager__in` but nothing for the assignee set.
  /// * `teams` — `my_team=true` is a boolean scope, not a team picker.
  /// * `progress` — no `percent_complete` range param is documented.
  /// * `health` — only its middle option encodes; see [_health] for why the
  ///   other two cannot.
  ///
  /// `cost`, `start` and `end` used to sit here too; §1 documents params for
  /// all three and they work, so they are encoded now.
  static const localOnlyFields = {
    'assignees',
    'teams',
    'progress',
    'health',
  };

  /// The drawer's params. An all-default [FilterValues] encodes to `{}`.
  Map<String, dynamic> encode(FilterValues v) {
    final out = <String, dynamic>{};

    _choice(out, v.choice('statuses'), 'status', statuses);
    _choice(out, v.choice('types'), 'project_type', types);
    // Priority is a static High/Medium/Low set server-side — no catalog, the
    // option ids are already the values.
    _choice(out, v.choice('pri'), 'priority', const []);
    _customer(out, v.choice('customer'));
    _choice(out, v.choice('managers'), 'manager', const [], toUser: true);
    _health(out, v.radio('health'));
    _cost(out, v.range('cost'));
    _dates(out, v.date('end'), 'expected_end_date');
    _dates(out, v.date('start'), 'expected_start_date');

    return out;
  }

  /// Only the middle option is encoded.
  ///
  /// **Due in 14 days** → `due_within_days=14`, verified working.
  ///
  /// **Overdue** and **On track** would be `is_overdue=true|false`, and that
  /// param **500s** on `/projects/projects/` (`AssertionError`, both values,
  /// confirmed against dev on 12 Aug 2026). Sending it would take the whole
  /// list down, so both sides stay with the local matcher until it is fixed.
  void _health(Map<String, dynamic> out, RadioValue? value) {
    if (value == null || !value.isActive) return;
    if (value.id == 'risk') out['due_within_days'] = '14';
  }

  /// The drawer's slider is in ₹ lakhs; `budget_min` / `budget_max` are rupees.
  void _cost(Map<String, dynamic> out, RangeValue? value) {
    if (value == null || !value.isActive) return;
    if (value.min case final min?) out['budget_min'] = _rupees(min);
    if (value.max case final max?) out['budget_max'] = _rupees(max);
  }

  void _dates(Map<String, dynamic> out, DateValue? value, String field) {
    if (value == null || !value.isActive) return;
    // A quick chip ("next30") resolves to the same (from, to) the local matcher
    // uses, so the server and the client agree on what the chip means.
    final (from, to) = value.chip != null
        ? FilterMatch.chipRange(value.chip!)
        : (value.from, value.to);
    if (from != null) out['${field}_after'] = _isoDay(from);
    if (to != null) out['${field}_before'] = _isoDay(to);
  }

  static String _rupees(num lakhs) => (lakhs * 100000).round().toString();

  static String _isoDay(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ── decode: filter_definition → FilterValues ──

  /// Rebuilds drawer state from a stored definition, on top of [spec]'s
  /// defaults so untouched fields keep their blank values.
  ///
  /// Only the keys [encode] writes are read back. The local-only fields were
  /// never stored, so a saved view restores the facets the server ran and
  /// leaves the rest at their defaults — which is exactly what the chip
  /// re-applies.
  FilterValues decode(Map<String, dynamic> def, FilterSpec spec) {
    final v = spec.defaults();

    // Statuses and types are stored as ids and shown as the org's own names.
    _decodeChoice(def, v, 'statuses', 'status', (id) => _nameOf(statuses, id));
    _decodeChoice(def, v, 'types', 'project_type', (id) => _nameOf(types, id));
    _decodeChoice(def, v, 'pri', 'priority', (id) => id);
    _decodeChoice(def, v, 'managers', 'manager',
        (id) => id == currentUserId ? 'me' : id);
    _decodeCustomer(def, v);

    // `due_within_days` is the only health option with a param, so it is the
    // only one that can come back.
    if ('${def['due_within_days'] ?? ''}'.trim() == '14') {
      _setRadio(v, spec, 'health', 'risk');
    }

    _decodeRange(def, v, 'cost', 'budget_min', 'budget_max');
    _decodeDates(def, v, 'end', 'expected_end_date');
    _decodeDates(def, v, 'start', 'expected_start_date');

    return v;
  }

  void _decodeChoice(
    Map<String, dynamic> def,
    FilterValues out,
    String fieldId,
    String param,
    String? Function(String serverId) toOptionId,
  ) {
    for (final isNot in [false, true]) {
      final raw =
          def['$param${isNot ? '__not_in' : '__in'}'] ?? (isNot ? null : def[param]);
      final ids = _idList(raw);
      if (ids.isEmpty) continue;
      final mapped = <String>{};
      for (final id in ids) {
        final o = toOptionId(id);
        if (o != null && o.isNotEmpty) mapped.add(o);
      }
      if (mapped.isNotEmpty) out[fieldId] = ChoiceValue(ids: mapped, isNot: isNot);
      return;
    }
  }

  /// The mirror of [_customer]: `customer_isnull` is the `__internal`
  /// pseudo-option, not an id.
  void _decodeCustomer(Map<String, dynamic> def, FilterValues out) {
    final isNull = '${def['customer_isnull'] ?? ''}'.toLowerCase();
    if (isNull == 'true' || isNull == 'false') {
      out['customer'] =
          ChoiceValue(ids: const {'__internal'}, isNot: isNull == 'false');
      return;
    }
    // Stored as ids; the drawer's options are company names.
    _decodeChoice(def, out, 'customer', 'customer', (id) => _nameOf(customers, id));
  }

  /// Rupees back to the slider's ₹ lakhs.
  void _decodeRange(Map<String, dynamic> def, FilterValues out, String fieldId,
      String minKey, String maxKey) {
    final min = _num(def[minKey]);
    final max = _num(def[maxKey]);
    if (min == null && max == null) return;
    out[fieldId] = RangeValue(
      min: min == null ? null : min / 100000,
      max: max == null ? null : max / 100000,
    );
  }

  /// Always restored as explicit bounds, never as the chip that produced them:
  /// a chip is relative to today, so "next 30 days" saved in June would mean
  /// something different in August. The stored dates are what was filtered on.
  void _decodeDates(
      Map<String, dynamic> def, FilterValues out, String fieldId, String field) {
    final from = DateTime.tryParse('${def['${field}_after'] ?? ''}');
    final to = DateTime.tryParse('${def['${field}_before'] ?? ''}');
    if (from == null && to == null) return;
    out[fieldId] = DateValue(from: from, to: to);
  }

  /// Accepts both stored forms: `"a,b"` and `["a","b"]`.
  List<String> _idList(Object? raw) {
    if (raw == null) return const [];
    final parts =
        raw is List ? raw.map((e) => e.toString()) : raw.toString().split(',');
    return [for (final p in parts) p.trim()].where((s) => s.isNotEmpty).toList();
  }

  /// A stored id back to the option id the drawer uses — its name. Drops one
  /// the org no longer has, which would be an inert checkbox.
  String? _nameOf(List<CatalogOption> catalog, String id) {
    if (catalog.isEmpty) return id;
    for (final o in catalog) {
      if (o.id == id) return o.name;
    }
    return null;
  }

  void _setRadio(FilterValues v, FilterSpec spec, String fieldId, String id) {
    final field = spec.fieldById(fieldId);
    if (field == null) return;
    if (!field.options.any((o) => o.id == id)) return;
    v[fieldId] = RadioValue(id: id, defaultId: field.radioDefaultId);
  }

  static double? _num(Object? raw) =>
      raw == null ? null : double.tryParse(raw.toString().trim());

  /// Customer is two params in one section: the `__internal` pseudo-option means
  /// "no customer", which the API expresses as `customer_isnull`, not as an id.
  void _customer(Map<String, dynamic> out, ChoiceValue? value) {
    if (value == null || value.ids.isEmpty) return;
    final ids = <String>[];
    var internal = false;
    for (final id in value.ids) {
      if (id == '__internal') {
        internal = true;
        continue;
      }
      final resolved = _serverId(customers, id);
      if (resolved != null && resolved.isNotEmpty) ids.add(resolved);
    }
    // Internal on its own is the whole filter; mixed with named customers there
    // is no single param that means "these customers OR none", so the ids win
    // and the local matcher settles the rest.
    if (internal && ids.isEmpty) {
      out['customer_isnull'] = value.isNot ? 'false' : 'true';
      return;
    }
    if (ids.isEmpty) return;
    out['customer${value.isNot ? '__not_in' : '__in'}'] = ids.join(',');
  }

  void _choice(
    Map<String, dynamic> out,
    ChoiceValue? value,
    String param,
    List<CatalogOption> catalog, {
    bool toUser = false,
  }) {
    if (value == null || value.ids.isEmpty) return;
    final ids = <String>[];
    for (final id in value.ids) {
      final resolved = toUser ? _userId(id) : _serverId(catalog, id);
      if (resolved != null && resolved.isNotEmpty) ids.add(resolved);
    }
    // Every option failed to resolve — omit the key rather than send an empty
    // value, which would filter to nothing server-side.
    if (ids.isEmpty) return;
    out['$param${value.isNot ? '__not_in' : '__in'}'] = ids.join(',');
  }

  String? _serverId(List<CatalogOption> catalog, String value) {
    if (catalog.isEmpty) return value; // mock: option ids are the values
    final needle = value.toLowerCase().trim();
    for (final o in catalog) {
      if (o.id == value || o.key == needle) return o.id;
    }
    return null;
  }

  String? _userId(String id) => id == 'me' ? currentUserId : id;
}
