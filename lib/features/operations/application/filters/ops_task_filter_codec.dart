import '../../../../core/filters/filter_models.dart';
import '../../../crm/domain/entities/crm_catalog.dart';

/// Translates the Operations Tasks drawer's [FilterValues] to the backend's
/// `/projects/tasks/` **query params** (`operations-task.md` §1).
///
/// Only the documented fields are encoded; the rest stay local and are named in
/// [localOnlyFields] so callers keep matching them client-side rather than
/// silently dropping them.
class OpsTaskFilterCodec {
  const OpsTaskFilterCodec({
    this.statuses = const [],
    this.currentUserId,
  });

  /// `/projects/project-task-statuses/` → `project_task_status_id`.
  final List<CatalogOption> statuses;

  final String? currentUserId;

  /// Drawer fields with no documented param — matched locally, never encoded.
  ///
  /// * `depts` — departments are derived from the roster, not a task field.
  /// * `hours` — no estimate/effort param is documented.
  static const localOnlyFields = {'depts', 'hours'};

  Map<String, dynamic> encode(FilterValues v) {
    final out = <String, dynamic>{};

    _choice(out, v.choice('statuses'), 'status', statuses);
    // Projects: the drawer already keys its options by `project_id`.
    _choice(out, v.choice('projects'), 'project', const []);
    // Priority and type are pass-through: priority is a static server-side set,
    // and the type facet's options are already keyed by `task_type_id` (built
    // from the rows, since no task-type catalog endpoint is documented).
    _choice(out, v.choice('pri'), 'priority', const []);
    _choice(out, v.choice('types'), 'type', const []);
    _choice(out, v.choice('assignees'), 'assignees', const [], toUser: true);

    // Only the "milestones only" side has a param. `is_milestone=false` is not
    // documented, so "Exclude milestones" stays local — sending a guess would
    // filter server-side on a key the FilterSet may reject outright.
    final milestone = v.radio('milestone');
    if (milestone != null && milestone.isActive && milestone.id == 'yes') {
      out['is_milestone'] = 'true';
    }

    // "Overdue" is the server's date rule (`is_overdue=true`, the webapp's
    // Overdue tab): past the end date and still open. Matched on the phone it
    // also caught finished tasks whose date had passed.
    final due = v.date('due');
    if (isOverdueChip(due)) {
      out['is_overdue'] = 'true';
    } else if (due != null && due.isActive) {
      // Any other range is the expected-end window, both ends inclusive.
      final (from, to) = due.chip != null ? FilterMatch.chipRange(due.chip!) : (due.from, due.to);
      if (from != null) out['end_date_after'] = _day(from);
      if (to != null) out['end_date_before'] = _day(to);
    }

    // Task group: the lanes are keyed by `task_group_id`.
    final groups = v.choice('groups');
    if (groups != null && groups.ids.isNotEmpty) {
      out['task_group__in'] = groups.ids.join(',');
    }

    // Webapp "Include archived" (archived tasks and tasks of archived projects).
    if (v.choice('archived')?.ids.contains('archived') ?? false) {
      out['include_archived'] = 'true';
    }

    return out;
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The due-date facet set to exactly the "Overdue" quick chip.
  static bool isOverdueChip(DateValue? d) =>
      d != null && d.chip == 'overdue' && d.from == null && d.to == null;

  // ── decode: filter_definition → FilterValues ──

  /// Rebuilds drawer state from a stored definition, on top of [spec]'s
  /// defaults so untouched fields keep their blank values.
  ///
  /// Only the keys [encode] writes are read back. The local-only fields
  /// ([localOnlyFields]) were never stored, so a saved view restores the facets
  /// the server ran and leaves the rest at their defaults — which is exactly
  /// what the chip re-applies.
  FilterValues decode(Map<String, dynamic> def, FilterSpec spec) {
    final v = spec.defaults();

    // Statuses are stored as ids and shown as the org's own names.
    _decodeChoice(def, v, 'statuses', 'status', (id) => _nameOf(statuses, id));
    _decodeChoice(def, v, 'projects', 'project', (id) => id);
    _decodeChoice(def, v, 'pri', 'priority', (id) => id);
    _decodeChoice(def, v, 'types', 'type', (id) => id);
    _decodeChoice(def, v, 'assignees', 'assignees',
        (id) => id == currentUserId ? 'me' : id);

    // Only the "milestones only" side is ever encoded; `is_milestone=false` has
    // no documented param, so "Exclude milestones" cannot come back.
    if ('${def['is_milestone'] ?? ''}'.toLowerCase() == 'true') {
      _setRadio(v, spec, 'milestone', 'yes');
    }
    if ('${def['is_overdue'] ?? ''}'.toLowerCase() == 'true') {
      v['due'] = const DateValue(chip: 'overdue');
    } else if (def['end_date_after'] != null || def['end_date_before'] != null) {
      v['due'] = DateValue(
        from: DateTime.tryParse('${def['end_date_after'] ?? ''}'),
        to: DateTime.tryParse('${def['end_date_before'] ?? ''}'),
      );
    }
    _decodeChoice(def, v, 'groups', 'task_group', (id) => id);
    if ('${def['include_archived'] ?? ''}'.toLowerCase() == 'true') {
      v['archived'] = ChoiceValue(ids: {'archived'});
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
      final raw = def['$param${isNot ? '__not_in' : '__in'}'] ??
          (isNot ? null : def[param]);
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

  /// Accepts both stored forms: `"a,b"` and `["a","b"]`.
  List<String> _idList(Object? raw) {
    if (raw == null) return const [];
    final parts =
        raw is List ? raw.map((e) => e.toString()) : raw.toString().split(',');
    return [for (final p in parts) p.trim()].where((s) => s.isNotEmpty).toList();
  }

  /// A stored status id back to the option id the drawer uses — its name. Drops
  /// one the org no longer has, which would be an inert checkbox.
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
    if (catalog.isEmpty) return value; // mock, or an already-server value
    final needle = value.toLowerCase().trim();
    for (final o in catalog) {
      if (o.id == value || o.key == needle) return o.id;
    }
    return null;
  }

  String? _userId(String id) => id == 'me' ? currentUserId : id;
}
