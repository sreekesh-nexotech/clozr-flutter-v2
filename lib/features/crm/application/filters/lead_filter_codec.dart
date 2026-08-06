import '../../../../core/filters/filter_models.dart';
import '../../domain/entities/crm_catalog.dart';

/// Translates the Leads drawer's [FilterValues] to and from the backend's
/// `LeadFilter` **query-param dict** — the exact shape `/crm/saved-filters/`
/// persists in `filter_definition`, and the same shape the list endpoint takes
/// as query params.
///
/// Two constraints from the API contract drive the design:
///
/// * **Keys must be real `LeadFilter` param names.** The server validates every
///   key against the module's FilterSet catalog and rejects unknown ones with a
///   400, so the drawer's own field ids (`sources`, `stages`, …) can never be
///   stored directly.
/// * **Values are server ids**, while drawer option ids are display values (a
///   source name, a case-folded stage name). The catalogs supply that mapping.
///
/// When a catalog is empty the value is **passed through unchanged**. That is
/// what makes mock mode work: there the drawer's option ids already *are* the
/// values leads carry, so a view round-trips locally with no backend at all.
class LeadFilterCodec {
  const LeadFilterCodec({
    this.statuses = const [],
    this.sources = const [],
    this.products = const [],
    this.teams = const [],
    this.currentUserId,
  });

  final List<CatalogOption> statuses;
  final List<CatalogOption> sources;
  final List<CatalogOption> products;
  final List<CatalogOption> teams;

  /// The signed-in user's uuid, so the `'me'` sentinel the drawer uses can be
  /// written out as a real id and recognised again on the way back.
  final String? currentUserId;

  /// Lakhs → rupees. The panel shows lakhs; the params are raw rupees.
  static const int _lakh = 100000;

  // ── encode: FilterValues → filter_definition ──

  /// The param dict for [v]. Only active fields appear; an all-default
  /// [FilterValues] encodes to `{}`, which the API rejects on save — callers
  /// should refuse to save an empty filter rather than surface that 400.
  Map<String, dynamic> encode(FilterValues v) {
    final out = <String, dynamic>{};

    _encodeChoice(out, v.choice('sources'), 'lead_source', sources);
    _encodeChoice(out, v.choice('products'), 'product', products);
    _encodeChoice(out, v.choice('stages'), 'status', statuses);
    _encodeChoice(out, v.choice('teams'), 'assigned_team', teams);
    _encodeChoice(out, v.choice('owners'), 'assignees', const [], toUser: true);

    final aging = v.radio('aging');
    if (aging != null && aging.isActive) {
      final days = int.tryParse(aging.id);
      if (days != null) out['stale_days'] = days;
    }

    final owner = v.radio('ownerMode');
    if (owner != null && owner.isActive) {
      out['owner_mode'] = owner.id == 'none' ? 'unassigned' : owner.id;
    }

    final created = v.date('created');
    if (created != null && created.isActive) {
      // A quick chip is resolved to the concrete range it means *now*. The
      // stored filter is therefore absolute, not relative — re-opening a saved
      // "Last 7 days" shows the dates it covered when it was saved. That is
      // forced by the contract: `filter_definition` has no key for a chip.
      final (from, to) = created.chip != null
          ? FilterMatch.chipRange(created.chip!)
          : (created.from, created.to);
      if (from != null) out['created_at_after'] = _ymd(from);
      if (to != null) out['created_at_before'] = _ymd(to);
    }

    final value = v.range('value');
    if (value != null && value.isActive) {
      if (value.min != null) out['lead_value_min'] = (value.min! * _lakh).round();
      if (value.max != null) out['lead_value_max'] = (value.max! * _lakh).round();
    }

    final score = v.radio('score');
    if (score != null && score.isActive) {
      switch (score.id) {
        case 'hot':
          out['lead_score_min'] = 75;
        case 'warm':
          out['lead_score_min'] = 45;
          out['lead_score_max'] = 74;
        case 'cold':
          out['lead_score_max'] = 44;
      }
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

  /// Drawer option id → server id. Matches on either the catalog id or the
  /// case-folded name, since different sections key their options differently.
  /// Returns null when the catalog has loaded and does not know the value —
  /// sending a stale name where a uuid belongs would be a 400.
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

  /// Rebuilds drawer state from a stored definition, on top of [spec]'s
  /// defaults so untouched fields keep their blank values.
  ///
  /// Lossy in two documented places: a `created` quick chip comes back as the
  /// absolute range it encoded to, and a `lead_score` range that is not one of
  /// the three buckets cannot be shown by the radio and is dropped.
  FilterValues decode(Map<String, dynamic> def, FilterSpec spec) {
    final v = spec.defaults();

    _decodeChoice(def, v, 'sources', 'lead_source', (id) => _nameOf(sources, id));
    _decodeChoice(def, v, 'products', 'product', (id) => _nameOf(products, id));
    _decodeChoice(def, v, 'stages', 'status', (id) => _keyOf(statuses, id));
    _decodeChoice(def, v, 'teams', 'assigned_team', (id) => _teamOption(id));
    _decodeChoice(def, v, 'owners', 'assignees', (id) => id == currentUserId ? 'me' : id);

    final stale = _int(def['stale_days']);
    if (stale != null) _setRadio(v, spec, 'aging', '$stale');

    final mode = def['owner_mode']?.toString();
    if (mode != null && mode.isNotEmpty) {
      _setRadio(v, spec, 'ownerMode', mode == 'unassigned' ? 'none' : mode);
    }

    final after = _date(def['created_at_after']);
    final before = _date(def['created_at_before']);
    if (after != null || before != null) {
      v['created'] = DateValue(from: after, to: before);
    }

    final min = _int(def['lead_value_min']);
    final max = _int(def['lead_value_max']);
    if (min != null || max != null) {
      v['value'] = RangeValue(
        min: min == null ? null : min / _lakh,
        max: max == null ? null : max / _lakh,
      );
    }

    final scoreMin = _int(def['lead_score_min']);
    final scoreMax = _int(def['lead_score_max']);
    final bucket = _scoreBucket(scoreMin, scoreMax);
    if (bucket != null) _setRadio(v, spec, 'score', bucket);

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
      final raw = def['$param${isNot ? '__not' : '__in'}'] ?? (isNot ? null : def[param]);
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

  /// Accepts both documented forms: `"a,b"` and `["a","b"]`.
  List<String> _idList(Object? raw) {
    if (raw == null) return const [];
    final parts = raw is List
        ? raw.map((e) => e.toString())
        : raw.toString().split(',');
    return [for (final p in parts) p.trim(), ].where((s) => s.isNotEmpty).toList();
  }

  String? _nameOf(List<CatalogOption> catalog, String id) {
    if (catalog.isEmpty) return id;
    for (final o in catalog) {
      if (o.id == id) return o.name;
    }
    return null;
  }

  String? _keyOf(List<CatalogOption> catalog, String id) {
    if (catalog.isEmpty) return id;
    for (final o in catalog) {
      if (o.id == id) return o.key;
    }
    return null;
  }

  /// Team options are keyed by `team_id`, so a stored id is already the option
  /// id — but drop one the org no longer has, which would be an inert chip.
  String? _teamOption(String id) {
    if (teams.isEmpty) return id;
    for (final o in teams) {
      if (o.id == id) return o.id;
    }
    return null;
  }

  void _setRadio(FilterValues v, FilterSpec spec, String fieldId, String id) {
    final field = spec.fieldById(fieldId);
    if (field == null) return;
    if (!field.options.any((o) => o.id == id)) return;
    v[fieldId] = RadioValue(id: id, defaultId: field.radioDefaultId);
  }

  static String? _scoreBucket(int? min, int? max) {
    if (min == null && max == null) return null;
    if (min != null && min >= 75) return 'hot';
    if (min == 45 && max == 74) return 'warm';
    if (min == null && max != null && max <= 44) return 'cold';
    return null; // not one of the three buckets — the radio cannot show it
  }

  static int? _int(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static DateTime? _date(Object? v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString().trim());
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
