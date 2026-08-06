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
  LeadsRemoteDataSource(this._api);

  final ApiService _api;

  /// Org lead-status catalog (`name` → `status_type`), fetched once per
  /// data-source lifetime. The leads *list* serializer sends `status` as a
  /// display name with no `status_type`, so without this the mapper can only
  /// guess from the name — which mis-files stages like "Disqualified".
  Map<String, String>? _statusTypeCache;

  /// The UI keeps a full in-memory list, so follow `next` a bounded number of
  /// pages instead of paging on scroll.
  static const int _maxPages = 50; // safety cap; loop still breaks when next == null
  static const int _pageSize = 100;

  /// Raw lead rows (up to [_maxPages] pages). Exposed separately from
  /// [fetchLeads] so the repository can cache the JSON before mapping.
  Future<List<Map<String, dynamic>>> fetchLeadRows() async {
    final rows = <Map<String, dynamic>>[];
    int? page;
    for (var i = 0; i < _maxPages; i++) {
      final body = await _api.get(ApiEndpoints.leads, query: {
        'page_size': _pageSize,
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

  Future<List<Lead>> fetchLeads() async {
    final types = statusTypes(); // starts concurrently with the row fetch
    final rows = await fetchLeadRows();
    return mapLeadRows(rows, statusTypes: await types);
  }

  /// Detail fetch — same mapper; detail rows simply carry more contact fields.
  Future<Lead?> fetchLead(String id) async {
    final types = statusTypes();
    final body = await _api.get(ApiEndpoints.lead(id));
    return body is Map<String, dynamic>
        ? mapLead(body, statusTypes: await types)
        : null;
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
      phone: _phoneOf(row),
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
    );
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
