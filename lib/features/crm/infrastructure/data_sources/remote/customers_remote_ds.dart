import 'package:intl/intl.dart';

import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/inr_format.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/status_keys.dart';
import '../../../../../data/api/user_directory.dart';
import '../../../domain/entities/customer.dart';

/// Remote customer data: HTTP via [ApiService] + JSON→[Customer] mapping.
/// No caching here — the api repository owns the Hive fallback.
///
/// Mappers are static so tests can feed fixture maps without any HTTP stack.
class CustomersRemoteDataSource {
  const CustomersRemoteDataSource(this._api);

  final ApiService _api;

  /// The UI keeps a full in-memory list, so follow `next` a bounded number of
  /// pages instead of paging on scroll.
  static const int _maxPages = 50; // safety cap; loop still breaks when next == null
  static const int _pageSize = 100;

  /// Raw customer rows (up to [_maxPages] pages). Exposed separately from
  /// [fetchCustomers] so the repository can cache the JSON before mapping.
  Future<List<Map<String, dynamic>>> fetchCustomerRows({
    Map<String, dynamic> filters = const {},
  }) async {
    // Paging steers the walk itself, so a stored filter can never own it.
    final safe = {...filters}
      ..removeWhere((k, _) => k == 'page' || k == 'page_size');
    final rows = <Map<String, dynamic>>[];
    int? page;
    for (var i = 0; i < _maxPages; i++) {
      final body = await _api.get(ApiEndpoints.customers, query: {
        ...safe,
        // The org's **mobile** card projection — the same config the card's
        // layout comes from. Without it the payload carried the list columns
        // while the card obeyed the mobile layout. After `safe` so a stored
        // filter cannot override it.
        'view_type': 'mobile',
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

  Future<List<Customer>> fetchCustomers({
    Map<String, dynamic> filters = const {},
  }) async =>
      mapCustomerRows(await fetchCustomerRows(filters: filters));

  /// `PATCH /crm/customers/{id}/` — a partial update.
  ///
  /// Sent verbatim: unlike [createCustomer] this must be able to *clear* a
  /// field, so blanks and nulls are meaningful and are not stripped.
  Future<void> updateCustomer(String id, Map<String, dynamic> fields) =>
      _api.patch(ApiEndpoints.customer(id), body: fields);

  /// `POST /crm/customers/{id}/upsell/` — spawns a new upsell lead against this
  /// customer and moves it into the `upsell_in_progress` status.
  ///
  /// The new lead comes back so the caller can navigate to it; a shape surprise
  /// answers null rather than throwing, since the upsell itself succeeded.
  Future<String?> createUpsell(String id) async {
    final body = await _api.post(ApiEndpoints.customerUpsell(id));
    if (body is! Map) return null;
    final lead = body['lead'] is Map ? body['lead'] as Map : body;
    return (lead['lead_id'] ?? lead['id'])?.toString();
  }

  /// `GET /crm/customer-statuses/` — the org's own customer statuses, in the
  /// order an admin arranged them.
  ///
  /// `status_type` travels alongside the name: it is the backend-fixed code
  /// (`active` / `upsell_in_progress` / `completed` / `lost`) that decides the
  /// pill colour, where the name is free text an org can rename.
  Future<List<Map<String, dynamic>>> fetchCustomerStatusRows() async {
    final body = await _api.get(ApiEndpoints.customerStatuses,
        query: {'page_size': 100});
    return Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
  }

  /// Creates a customer from API-shaped form fields; only non-empty values
  /// are sent. Returns null when the response shape is unexpected.
  Future<Customer?> createCustomer(Map<String, dynamic> fields) async {
    final body = await _api.post(ApiEndpoints.customers, body: {
      for (final e in fields.entries)
        if (e.value != null && e.value.toString().trim().isNotEmpty)
          e.key: e.value,
    });
    if (body is! Map<String, dynamic>) return null;
    try {
      return mapCustomer(body);
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
  /// `customer_id` are skipped, never fatal.
  static List<Customer> mapCustomerRows(List<dynamic> rows) {
    final out = <Customer>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      try {
        final customer = mapCustomer(row);
        if (customer != null) out.add(customer);
      } on Object {
        // A malformed row is skipped, never fatal.
      }
    }
    return out;
  }

  /// Maps one API customer row (list or detail shape) onto the UI entity.
  /// Returns null when the row has no `customer_id`.
  static Customer? mapCustomer(Map<String, dynamic> row) {
    final id = _str(row, 'customer_id');
    if (id.isEmpty) return null;

    final name = _str(row, 'name');

    // value_need = {value: revenue, need: purpose}; fall back to `revenue`.
    final valueNeed = row['value_need'];
    Object? rawValue = valueNeed is Map ? valueNeed['value'] : null;
    rawValue ??= row['revenue'];
    final valueNum = parseAmount(rawValue);
    final needRaw = valueNeed is Map ? valueNeed['need'] : null;
    final need = needRaw is String ? needRaw : '';

    // `assigned_to` is a bare uuid on some payloads, a user object on others.
    final assignedTo = row['assigned_to'];
    var owner = '';
    if (assignedTo is Map) {
      UserDirectory.registerJson(assignedTo);
      owner = UserDirectory.mapUserId(_userIdOf(assignedTo));
    } else if (assignedTo is String) {
      owner = UserDirectory.mapUserId(assignedTo);
    }

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

    final statusEntered = parseApiDate(row['status_entered_at']);
    final location = _str(row, 'location');

    return Customer(
      raw: row,
      id: id,
      leadId: null, // list rows carry no source-lead reference
      name: name,
      initials: UserDirectory.initialsOf(name),
      company: _str(row, 'organization_name'),
      project: need,
      value: formatInr(valueNum),
      valueNum: valueNum.toInt(),
      status: customerStatusKey(
        name: _strOrNull(row, 'status_name'),
        type: _strOrNull(row, 'status_type'),
      ),
      since: _monthYear(statusEntered),
      statusDays: _daysSince(statusEntered),
      score: (row['score'] as num?)?.toInt() ?? 0,
      source: _str(row, 'source'),
      owner: owner,
      team: team,
      phone: _str(row, 'phone'),
      email: _str(row, 'email'),
      website: _str(row, 'website'),
      industry: _str(row, 'industry_name'),
      location: location.isNotEmpty ? location : _str(row, 'address'),
      createdOn: absoluteDate(parseApiDate(row['created_at'])),
      time: relativeTime(parseApiDate(row['activity'])),
      lastFu: _followupLabel(row['last_followup_type'], row['last_followup_at']),
      notif: 0,
    );
  }

  /// "Since Dec 2025"-style month label from `status_entered_at`.
  static String _monthYear(DateTime? time) =>
      time == null ? '' : DateFormat('MMM yyyy').format(time.toLocal());

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

  static String? _userIdOf(Map<dynamic, dynamic> user) {
    final id = user['user_id'];
    return id is String ? id : null;
  }

  static String _str(Map<String, dynamic> row, String key) {
    final v = row[key];
    return v is String ? v : '';
  }

  static String? _strOrNull(Map<String, dynamic> row, String key) {
    final v = row[key];
    return v is String ? v : null;
  }
}
