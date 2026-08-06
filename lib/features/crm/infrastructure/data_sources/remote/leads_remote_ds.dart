import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/inr_format.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/status_keys.dart';
import '../../../../../data/api/user_directory.dart';
import '../../../domain/entities/lead.dart';

/// Remote lead data: HTTP via [ApiService] + JSON→[Lead] mapping. No caching
/// here — the api repository owns the Hive fallback.
///
/// Mappers are static so tests can feed fixture maps without any HTTP stack.
class LeadsRemoteDataSource {
  LeadsRemoteDataSource(this._api, {this.statusTypesLoader});

  final ApiService _api;

  /// Supplies the `name` → `status_type` map from an already-fetched source,
  /// so the app does not request `/crm/lead-statuses/` twice — once here and
  /// once for the status tabs. Falls back to fetching when null.
  final Future<Map<String, String>> Function()? statusTypesLoader;

  /// Org lead-status catalog (`name` → `status_type`), fetched once per
  /// data-source lifetime. The leads *list* serializer sends `status` as a
  /// display name with no `status_type`, so without this the mapper can only
  /// guess from the name — which mis-files stages like "Disqualified".
  Map<String, String>? _statusTypeCache;

  /// The UI keeps a full in-memory list (tab counts, drawer filters and search
  /// all run over it), so follow DRF's `next` a bounded number of pages instead
  /// of paging on scroll.
  ///
  /// [_pageSize] is the server's `max_page_size` — fewer round trips for the
  /// same rows. `page_size` above the ceiling is clamped server-side, not
  /// rejected, so this is safe even if the ceiling drops.
  static const int _maxPages = 50; // safety cap; loop still breaks when next == null
  static const int _pageSize = 200;

  /// Raw lead rows (up to [_maxPages] pages). Exposed separately from
  /// [fetchLeads] so the repository can cache the JSON before mapping.
  ///
  /// [mineOnly] adds `is_teams=true` — the server-side "My leads" scope (leads
  /// the caller owns OR is an assignee on). It is re-sent on every page so the
  /// scope holds across the whole walk.
  Future<List<Map<String, dynamic>>> fetchLeadRows({
    bool mineOnly = false,
    Map<String, dynamic> filters = const {},
  }) async {
    // Paging steers the walk itself, so a filter can never own it — dropped
    // outright rather than merged, since on the first request there is no
    // `page` of ours to override a stored one with.
    final safe = {...filters}..removeWhere(_isPagingKey);
    final rows = <Map<String, dynamic>>[];
    int? page;
    for (var i = 0; i < _maxPages; i++) {
      final body = await _api.get(ApiEndpoints.leads, query: {
        ...safe,
        'page_size': _pageSize,
        if (mineOnly) 'is_teams': true,
        if (page != null) 'page': page,
      });
      final paged = Paginated.fromAny<Map<String, dynamic>>(body, (row) => row);
      rows.addAll(paged.results);
      page = _pageOf(paged.next);
      if (page == null) break;
    }
    return rows;
  }

  /// The org's lead statuses as `name` → `status_type`, cached after the first
  /// successful fetch.
  ///
  /// Best-effort by design: any failure yields an empty map (and is **not**
  /// cached, so a later call retries), leaving the mapper on its name-matching
  /// path. Loading leads must never fail because this lookup did.
  Future<Map<String, String>> statusTypes() async {
    final cached = _statusTypeCache;
    if (cached != null) return cached;
    final loader = statusTypesLoader;
    if (loader != null) {
      try {
        final out = await loader();
        return out.isEmpty ? out : (_statusTypeCache = out);
      } on Object {
        return const {};
      }
    }
    try {
      final body =
          await _api.get(ApiEndpoints.leadStatuses, query: {'page_size': 100});
      final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
      final out = <String, String>{};
      for (final row in rows) {
        final name = _lower(row['name']);
        final type = _lower(row['status_type']);
        if (name.isNotEmpty && type.isNotEmpty) out[name] = type;
      }
      return out.isEmpty ? out : (_statusTypeCache = out);
    } on Object {
      return const {};
    }
  }

  /// Drops the cached status catalog (org switch / sign-out).
  void resetStatusCache() => _statusTypeCache = null;

  Future<List<Lead>> fetchLeads({
    bool mineOnly = false,
    Map<String, dynamic> filters = const {},
  }) async {
    final types = statusTypes(); // starts concurrently with the row fetch
    final rows = await fetchLeadRows(mineOnly: mineOnly, filters: filters);
    return mapLeadRows(rows, statusTypes: await types);
  }

  /// The raw record row for one lead. Exposed separately from [fetchLead] so
  /// the repository can cache the JSON before mapping, as it does for the list.
  ///
  /// `GET /crm/leads/{id}/` resolves to the org's **detail** field config, so
  /// this row carries fields the list rows do not have at all — `lead_owner`,
  /// `email`, `mobile_no`, `whatsapp_no`, `territory`, `meta_qa`. That is the
  /// whole reason the detail screen cannot just reuse a row from the list.
  Future<Map<String, dynamic>?> fetchLeadRow(String id) async {
    final body = await _api.get(ApiEndpoints.lead(id));
    return body is Map<String, dynamic> ? body : null;
  }

  /// Detail fetch — same mapper; detail rows simply carry more contact fields.
  Future<Lead?> fetchLead(String id) async {
    final types = statusTypes();
    final row = await fetchLeadRow(id);
    return row == null ? null : mapLead(row, statusTypes: await types);
  }

  /// Creates a lead from API-shaped form fields; only non-empty values are
  /// sent. Returns null when the response is not a recognizable lead row
  /// (e.g. a merge-mode duplicate response with an unexpected shape).
  Future<Lead?> createLead(Map<String, dynamic> fields) async {
    final body = await _api.post(ApiEndpoints.leads, body: {
      for (final e in fields.entries)
        if (e.value != null && e.value.toString().trim().isNotEmpty)
          e.key: e.value,
    });
    if (body is! Map<String, dynamic>) return null;
    try {
      return mapLead(body);
    } on Object {
      return null; // unexpected shape → null, never a crash
    }
  }

  /// The Add/Edit lead form's fields, under the names the API actually stores
  /// them as. Shared by create and update so the two can never drift.
  ///
  /// Two names deliberately absent, both verified against a live org:
  ///
  /// * **`phone`** — the model has one, but the serializer's contact field is
  ///   `mobile_no` (which is also what [_phoneOf] reads first). A `phone` sent
  ///   here is accepted, echoed back in the response, and never stored.
  /// * **`purpose`** — not a Lead field at all. The form's "project" box has no
  ///   backend counterpart; `Lead.project` is derived from the lead's linked
  ///   products, which this form does not edit.
  ///
  /// A field the org has not configured as detail-visible is likewise not on
  /// the serializer, so it is silently dropped. That is the server's call, not
  /// something this map can predict — it sends the superset it knows is real.
  static Map<String, dynamic> leadWriteFields({
    required String name,
    required String company,
    required String email,
    required String phone,
    required String website,
  }) =>
      {
        'lead_name': name.trim(),
        'organization_name': company.trim(),
        'email': email.trim(),
        'mobile_no': phone.trim(),
        'website': website.trim(),
      };

  /// `PATCH /crm/leads/{id}/` — saves the Edit lead form.
  ///
  /// Unlike [createLead] this does **not** drop blank values: the form was
  /// prefilled from the record, so a box the user emptied is an instruction to
  /// clear that field.
  ///
  /// A field this org has not configured as visible is not on the serializer
  /// at all, so the API accepts it, echoes it back and never stores it. Send
  /// only names the schema actually exposes — see [leadWriteFields].
  Future<Lead?> updateLead(String id, Map<String, dynamic> fields) async {
    final body = await _api.patch(ApiEndpoints.lead(id), body: fields);
    if (body is! Map<String, dynamic>) return null;
    try {
      return mapLead(body);
    } on Object {
      return null; // unexpected shape → null, never a crash
    }
  }

  /// `PATCH /crm/leads/{id}/` — moves the lead to another pipeline stage.
  ///
  /// The field is **`status_id`**, not `status`: the serializer exposes
  /// `status` read-only as the display name, so patching that is accepted and
  /// silently ignored. The response echoes the updated record (and a freshly
  /// stamped `stage_entered_at`, which the aging filter reads).
  Future<Lead?> updateLeadStatus(String id, String statusId) async {
    final body = await _api.patch(ApiEndpoints.lead(id), body: {'status_id': statusId});
    if (body is! Map<String, dynamic>) return null;
    return mapLead(body, statusTypes: await statusTypes());
  }

  static bool _isPagingKey(String key, Object? _) =>
      key == 'page' || key == 'page_size';

  /// Extracts the page number from a DRF `next` URL (absolute or relative).
  static int? _pageOf(String? next) {
    if (next == null || next.isEmpty) return null;
    final uri = Uri.tryParse(next);
    if (uri == null) return null;
    return int.tryParse(uri.queryParameters['page'] ?? '');
  }

  // ── mapping (visible for tests) ──

  /// Maps a raw results list defensively: non-map entries and rows without a
  /// `lead_id` are skipped, never fatal.
  static List<Lead> mapLeadRows(
    List<dynamic> rows, {
    Map<String, String> statusTypes = const {},
  }) {
    final out = <Lead>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      try {
        final lead = mapLead(row, statusTypes: statusTypes);
        if (lead != null) out.add(lead);
      } on Object {
        // A malformed row is skipped, never fatal.
      }
    }
    return out;
  }

  /// Maps one API lead row (list or detail shape) onto the UI entity.
  /// Returns null when the row has no `lead_id`.
  static Lead? mapLead(
    Map<String, dynamic> row, {
    Map<String, String> statusTypes = const {},
  }) {
    final id = _str(row, 'lead_id');
    if (id.isEmpty) return null;

    final name = _str(row, 'lead_name');

    final ownerJson = row['lead_owner'];
    UserDirectory.registerJson(ownerJson);
    final owner = ownerJson is Map
        ? UserDirectory.mapUserId(_userIdOf(ownerJson))
        : '';

    final team = <String>[];
    final assignees = row['assignees'];
    if (assignees is List) {
      for (final a in assignees) {
        if (a is! Map) continue;
        UserDirectory.registerJson(a);
        final uid = UserDirectory.mapUserId(_userIdOf(a));
        if (uid.isNotEmpty) team.add(uid);
      }
    }

    final valueNum = parseAmount(row['lead_value']);
    final source = _refName(row['lead_source']);
    final industryName = _str(row, 'industry_name');

    return Lead(
      id: id,
      name: name,
      initials: UserDirectory.initialsOf(name),
      company: _strOrNull(row, 'organization_name'),
      project: _projectOf(row, source),
      value: formatInr(valueNum),
      valueNum: valueNum.toInt(),
      // The list serializer sends `status` as a display NAME, not an id, and
      // carries no `status_type` — so fall back to the org catalog keyed by
      // that name (empty map → name matching only, as before).
      status: leadStatusKey(
        name: _strOrNull(row, 'status'),
        type: _strOrNull(row, 'status_type') ??
            statusTypes[_lower(row['status'])],
      ),
      // Kept verbatim alongside the folded key so the tabs and Stage filter can
      // show the org's real stage list (see [Lead.statusName]).
      statusName: _str(row, 'status'),
      statusDays: _daysSince(parseApiDate(row['stage_entered_at'])),
      score: (row['lead_score'] as num?)?.toInt() ?? 0,
      source: source,
      owner: owner,
      team: team,
      // Present only when the org's list field config makes `assigned_team`
      // visible; both forms are mapped since the payload may nest the team
      // object or send a bare id.
      assignedTeam:
          row['assigned_team'] is Map ? _refName(row['assigned_team']) : '',
      assignedTeamId: _refId(row['assigned_team'], 'team_id'),
      phone: _phoneOf(row),
      whatsappNo: _str(row, 'whatsapp_no'),
      // Sent as a nested object on the detail payload, a bare name elsewhere.
      territory: _refName(row['territory']),
      email: _str(row, 'email'),
      website: _str(row, 'website'),
      industry: industryName.isNotEmpty ? industryName : _refName(row['industry']),
      location: _str(row, 'location'),
      createdOn: absoluteDate(parseApiDate(row['created_at'])),
      time: relativeTime(parseApiDate(row['activity'])),
      lastFu: _followupLabel(row['last_followup_type'], row['last_followup_at']),
      notif: 0,
      upsell: row['is_upsell'] == true,
      fromCustomerId: _parentCustomerOf(row['parent_customer']),
      customFields: _customFieldsOf(row['custom_fields']),
    );
  }

  /// The row's `custom_fields` object, kept verbatim.
  ///
  /// Values stay untyped on purpose — the org decides what fields exist and of
  /// what type, and `/crm/leads/schema/` is what tells the UI how to render
  /// them. Anything that is not an object (absent, or an unexpected shape)
  /// becomes an empty map, never an error.
  static Map<String, Object?> _customFieldsOf(Object? value) {
    if (value is! Map) return const {};
    final out = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is String && key.isNotEmpty) out[key] = entry.value;
    }
    return out;
  }

  /// First product name when a products list is present, else the lead-source
  /// name, else ''.
  static String _projectOf(Map<String, dynamic> row, String sourceName) {
    final products = row['products'];
    if (products is List) {
      for (final p in products) {
        if (p is! Map) continue;
        final n = (p['product_name'] ?? p['name'] ?? '').toString();
        if (n.isNotEmpty) return n;
      }
    }
    return sourceName;
  }

  /// The lead's contact number. The API carries it as `mobile_no` (detail
  /// serializer); `phone` is kept as a fallback for any alternate shape. The
  /// separate `whatsapp_no` is deliberately NOT used here — it is a different
  /// number and belongs to a WhatsApp action, not the Mobile/Call field.
  static String _phoneOf(Map<String, dynamic> row) {
    for (final key in const ['mobile_no', 'phone']) {
      final v = _str(row, key);
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  /// "Call · 2d ago"-style label; empty when there is no follow-up timestamp.
  static String _followupLabel(Object? type, Object? at) {
    final when = parseApiDate(at);
    if (when == null) return '';
    final t = (type is String ? type : '').trim();
    final label = t.isEmpty
        ? 'Follow-up'
        : '${t[0].toUpperCase()}${t.substring(1)}';
    return '$label · ${relativeTime(when)}';
  }

  static int _daysSince(DateTime? time) {
    if (time == null) return 0;
    final days = DateTime.now().difference(time).inDays;
    return days < 0 ? 0 : days;
  }

  /// A name out of an FK that may arrive as an object (`{name: …}`) or a bare
  /// display string.
  static String _refName(Object? value) {
    if (value is Map) return (value['name'] ?? '').toString();
    if (value is String) return value;
    return '';
  }

  /// The id out of an FK that may arrive as an object (`{team_id: …}`) or as a
  /// bare id string.
  static String _refId(Object? value, String idKey) {
    if (value is Map) return (value[idKey] ?? '').toString();
    if (value is String) return value;
    return '';
  }

  static String? _parentCustomerOf(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    if (value is Map) {
      final id = value['customer_id'];
      if (id is String && id.isNotEmpty) return id;
    }
    return null;
  }

  static String? _userIdOf(Map<dynamic, dynamic> user) {
    final id = user['user_id'];
    return id is String ? id : null;
  }

  /// Lower-cased, trimmed string — the key form used by the status catalog.
  static String _lower(Object? v) => v is String ? v.toLowerCase().trim() : '';

  static String _str(Map<String, dynamic> row, String key) {
    final v = row[key];
    return v is String ? v : '';
  }

  static String? _strOrNull(Map<String, dynamic> row, String key) {
    final v = row[key];
    return v is String ? v : null;
  }
}
