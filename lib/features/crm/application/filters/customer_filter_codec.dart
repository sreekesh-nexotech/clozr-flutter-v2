import '../../../../core/filters/filter_models.dart';
import '../../domain/entities/crm_catalog.dart';

/// Translates the Customers drawer's [FilterValues] to and from the backend's
/// `CustomerFilter` **query-param dict** — the shape `/crm/saved-filters/`
/// persists in `filter_definition`, and the same shape the list endpoint takes
/// as query params.
///
/// Params per `docs-backend/customer-filters.md` Part 2. The same two contract
/// constraints as the Leads codec drive the design:
///
/// * **Keys must be real `CustomerFilter` param names.** The server validates
///   every key against the module's FilterSet and 400s on an unknown one, so
///   the drawer's own field ids (`statuses`, `owners`, …) can never be stored.
/// * **Values are server ids**, while drawer option ids are display values.
///   The catalogs supply that mapping.
///
/// An empty catalog **passes the value through unchanged**, which is what keeps
/// mock mode working: there the option ids already are the values customers
/// carry, so a view round-trips with no backend at all.
class CustomerFilterCodec {
  const CustomerFilterCodec({
    this.statuses = const [],
    this.sources = const [],
    this.products = const [],
    this.currentUserId,
  });

  /// The org's own customer statuses (`/crm/customer-statuses/`).
  final List<CatalogOption> statuses;

  /// Lead sources — a customer inherits its source from the lead it converted
  /// from, which is why the param walks the relation.
  final List<CatalogOption> sources;

  final List<CatalogOption> products;

  /// The signed-in user's uuid, so the drawer's `'me'` sentinel can be written
  /// out as a real id and recognised again on the way back.
  final String? currentUserId;

  /// Lakhs → rupees. The panel shows lakhs; `revenue__min/max` are raw rupees.
  static const int _lakh = 100000;

  /// The source filter walks `source_lead → lead_source`, so its param is not
  /// the plain field name the others use.
  static const String _sourceParam = 'source_lead__lead_source';

  // ── encode: FilterValues → filter_definition ──

  Map<String, dynamic> encode(FilterValues v) {
    final out = <String, dynamic>{};

    _encodeChoice(out, v.choice('statuses'), 'status', statuses);
    _encodeChoice(out, v.choice('sources'), _sourceParam, sources);
    _encodeChoice(out, v.choice('products'), 'products', products);
    // Companies are free text on the customer, not a catalog — the param takes
    // the names themselves.
    _encodeChoice(out, v.choice('companies'), 'organization_name', const []);
    _encodeChoice(out, v.choice('owners'), 'assigned_to', const [], toUser: true);

    final value = v.range('value');
    if (value != null && value.isActive) {
      if (value.min != null) out['revenue__min'] = (value.min! * _lakh).round();
      if (value.max != null) out['revenue__max'] = (value.max! * _lakh).round();
    }

    final since = v.date('since');
    if (since != null && since.isActive) {
      // A quick chip resolves to the concrete range it means *now*. The stored
      // filter is therefore absolute, not relative — same lossiness the Leads
      // codec documents, and forced by the same thing: `filter_definition` has
      // no key for a chip.
      final (from, to) = since.chip != null
          ? FilterMatch.chipRange(since.chip!)
          : (since.from, since.to);
      if (from != null) out['created_at__after'] = _ymd(from);
      if (to != null) out['created_at__before'] = _ymd(to);
    }

    return out;
  }

  void _encodeChoice(
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
    // Every selected option failed to resolve — omit the key rather than send
    // an empty value, which would filter to nothing server-side.
    if (ids.isEmpty) return;
    out['$param${value.isNot ? '__not' : '__in'}'] = ids.join(',');
  }

  /// Drawer option id → server id, matching on the catalog id or the
  /// case-folded name. Null when the catalog has loaded and does not know the
  /// value: sending a stale name where a uuid belongs is a 400.
  String? _serverId(List<CatalogOption> catalog, String value) {
    if (catalog.isEmpty) return value; // mock: option ids are the values
    final needle = value.toLowerCase().trim();
    for (final o in catalog) {
      if (o.id == value || o.key == needle) return o.id;
    }
    return null;
  }

  String? _userId(String id) => id == 'me' ? currentUserId : id;

  // ── decode: filter_definition → FilterValues ──

  FilterValues decode(Map<String, dynamic> def, FilterSpec spec) {
    final v = spec.defaults();

    _decodeChoice(def, v, 'statuses', 'status', (id) => _keyOf(statuses, id));
    _decodeChoice(def, v, 'sources', _sourceParam, (id) => _nameOf(sources, id));
    _decodeChoice(def, v, 'products', 'products', (id) => _nameOf(products, id));
    _decodeChoice(def, v, 'companies', 'organization_name', (id) => id);
    _decodeChoice(def, v, 'owners', 'assigned_to',
        (id) => id == currentUserId ? 'me' : id);

    final min = _int(def['revenue__min']);
    final max = _int(def['revenue__max']);
    if (min != null || max != null) {
      v['value'] = RangeValue(
        min: min == null ? null : min / _lakh,
        max: max == null ? null : max / _lakh,
      );
    }

    final after = _date(def['created_at__after']);
    final before = _date(def['created_at__before']);
    if (after != null || before != null) {
      v['since'] = DateValue(from: after, to: before);
    }

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
          def['$param${isNot ? '__not' : '__in'}'] ?? (isNot ? null : def[param]);
      final ids = _idList(raw);
      if (ids.isEmpty) continue;
      final mapped = <String>{};
      for (final id in ids) {
        final o = toOptionId(id);
        if (o != null && o.isNotEmpty) mapped.add(o);
      }
      if (mapped.isNotEmpty) out[fieldId] = ChoiceValue(ids: mapped, isNot: isNot);
    }
  }

  /// Server id → the drawer's option id, which for statuses is the folded key
  /// the customer rows carry.
  String? _keyOf(List<CatalogOption> catalog, String id) {
    for (final o in catalog) {
      if (o.id == id) return o.id;
    }
    return catalog.isEmpty ? id : null;
  }

  String? _nameOf(List<CatalogOption> catalog, String id) {
    for (final o in catalog) {
      if (o.id == id) return o.name;
    }
    return catalog.isEmpty ? id : null;
  }

  static List<String> _idList(Object? raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return [for (final e in raw) '$e'.trim()]..removeWhere((e) => e.isEmpty);
    }
    return '$raw'.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  static int? _int(Object? raw) {
    if (raw is num) return raw.round();
    return raw == null ? null : int.tryParse('$raw');
  }

  static DateTime? _date(Object? raw) =>
      raw == null ? null : DateTime.tryParse('$raw');

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
