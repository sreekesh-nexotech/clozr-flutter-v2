import '../../../../../core/config/api_config.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/status_keys.dart';
import '../../../../../data/api/user_directory.dart';
import '../../../domain/entities/ticket.dart';

/// Remote data source for helpdesk tickets (`/crm/issues/`).
///
/// HTTP + JSON→[Ticket] mapping only — no caching (that's the repository's
/// job). Mapping is exposed as statics so the repository can re-map cached raw
/// rows and tests can exercise it without an [ApiService].
///
/// Backend field names confirmed from `crm/serializers/issue.py`:
/// `issue_id`, `subject`, `description`, `priority` (Low|Medium|High|Critical),
/// `channel`/`channel_display`, nested `status` (write via `status_id`),
/// `type_name`, `assigned_to`/`assigned_to_name`, `customer`/`customer_name`
/// (write via `customer_id`), `product_name`, `project`, `created_at`,
/// `first_response_due_at`, `first_responded_at`, `sla_deadline`,
/// `resolution_date`.
class TicketsRemoteDataSource {
  TicketsRemoteDataSource(this._api);

  final ApiService _api;

  /// Session-lived issue-status roster (`issue_status_id` + `name` rows),
  /// fetched once and reused by [setStatusByKey].
  List<Map<String, dynamic>>? _statusRows;

  // ── Reads ──

  /// Raw issue rows, following pagination up to 3 pages.
  Future<List<Map<String, dynamic>>> fetchTicketRows() async {
    final rows = <Map<String, dynamic>>[];
    var page = 1;
    while (page <= 50) {
      final body = await _api.get(ApiEndpoints.issues, query: {
        'page': page,
        'page_size': ApiConfig.defaultPageSize,
      });
      final paged = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m);
      rows.addAll(paged.results);
      if (!paged.hasMore) break;
      page++;
    }
    return rows;
  }

  Future<List<Ticket>> fetchTickets() async => mapTickets(await fetchTicketRows());

  // ── Writes ──

  /// POST a new issue. Sends only fields the serializer is known to accept.
  Future<Ticket?> createTicket(Map<String, dynamic> fields) async {
    final body = await _api.post(ApiEndpoints.issues, body: _writePayload(fields));
    return body is Map<String, dynamic> ? mapTicket(body) : null;
  }

  /// PATCH subject/description/priority (and channel/customer when valid).
  Future<void> updateTicket(String id, Map<String, dynamic> fields) =>
      _api.patch(ApiEndpoints.issue(id), body: _writePayload(fields));

  /// Resolves the org's issue status whose name maps onto [uiStatusKey]
  /// (`new|open|pending|resolved|closed`) and PATCHes it. The serializer's
  /// write field is `status_id` (nested `status` is read-only). A key with no
  /// matching org status is a silent no-op — never a crash from a
  /// fire-and-forget call site.
  Future<void> setStatusByKey(String id, String uiStatusKey) async {
    final rows = await _fetchStatusRows();
    String? statusId;
    for (final row in rows) {
      if (ticketStatusKey(_str(row['name'])) == uiStatusKey) {
        statusId = _str(row['issue_status_id']);
        break;
      }
    }
    if (statusId == null) return;
    await _api.patch(ApiEndpoints.issue(id), body: {'status_id': statusId});
  }

  Future<List<Map<String, dynamic>>> _fetchStatusRows() async {
    final cached = _statusRows;
    if (cached != null && cached.isNotEmpty) return cached;
    final body =
        await _api.get(ApiEndpoints.issueStatuses, query: {'page_size': 100});
    final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
    _statusRows = rows;
    return rows;
  }

  // ── Mapping (static: reusable from cache fallback + unit tests) ──

  /// Maps a list of raw rows, skipping malformed entries and rows without an
  /// `issue_id` — a bad row is dropped, never fatal.
  static List<Ticket> mapTickets(List<dynamic> rows) {
    final out = <Ticket>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final ticket = mapTicket(Map<String, dynamic>.from(row));
      if (ticket != null) out.add(ticket);
    }
    return out;
  }

  /// One issue row → [Ticket]. Returns null when the row has no `issue_id`
  /// (or is malformed beyond repair).
  static Ticket? mapTicket(Map<String, dynamic> json) {
    try {
      final id = _str(json['issue_id']);
      if (id == null) return null;

      final respByISO = _validIso(_str(json['first_response_due_at']));
      final resolveByISO = _validIso(_str(json['sla_deadline']));
      final respondedAt = parseApiDate(json['first_responded_at']);
      final resolvedAt =
          parseApiDate(json['resolved_at'] ?? json['resolution_date']);

      return Ticket(
        id: id,
        subject: _str(json['subject']) ?? _str(json['title']) ?? '',
        cat: _category(_typeName(json)),
        custId: _customerId(json),
        contact: '',
        channel: _channel(json),
        status: ticketStatusKey(_statusName(json['status'])),
        pri: _uiPriority(_str(json['priority'])),
        assignees: _assignees(json),
        product: _str(json['product_name']),
        projId: _str(json['project']) ?? _relatedId(json, 'project'),
        taskId: _relatedId(json, 'task'),
        created: absoluteDate(parseApiDate(json['created_at'])),
        responded: respondedAt == null ? null : absoluteDate(respondedAt),
        resolved: resolvedAt == null ? null : absoluteDate(resolvedAt),
        respByISO: respByISO,
        respByLabel: _slaLabel(respByISO),
        resolveByISO: resolveByISO,
        resolveByLabel: _slaLabel(resolveByISO),
        desc: _str(json['description']) ?? '',
      );
    } on Object {
      return null;
    }
  }

  /// Non-empty string or null — every field read goes through this so shape
  /// drift (numbers, lists, nulls) never throws.
  static String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

  /// Keeps an ISO deadline only when it actually parses, so the SLA utils'
  /// `DateTime.parse(respByISO!)` can never throw at render time.
  static String? _validIso(String? iso) =>
      iso != null && DateTime.tryParse(iso) != null ? iso : null;

  static String? _slaLabel(String? iso) {
    final d = parseApiDate(iso);
    return d == null ? null : absoluteDate(d);
  }

  static final RegExp _uuidRe = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F-]{23,27}$');

  static String? _typeName(Map<String, dynamic> json) {
    final tn = _str(json['type_name']);
    if (tn != null) return tn;
    final type = json['issue_type'];
    if (type is Map) return _str(type['name']);
    // A bare string is the issue_type UUID — only usable when it's a name.
    final s = _str(type);
    return s != null && !_uuidRe.hasMatch(s) ? s : null;
  }

  /// Issue-type name → the UI's fixed category set.
  static String _category(String? typeName) {
    final n = (typeName ?? '').toLowerCase();
    if (n.contains('complain')) return 'Complaint';
    if (n.contains('request')) return 'Request';
    return 'Query';
  }

  static String _customerId(Map<String, dynamic> json) {
    final customer = json['customer'];
    if (customer is Map) return _str(customer['customer_id']) ?? '';
    return _str(customer) ?? _relatedId(json, 'customer') ?? '';
  }

  /// Legacy generic-FK linkage (`related_to`/`related_to_id`), read
  /// defensively across the shapes the mixin has used.
  static String? _relatedId(Map<String, dynamic> json, String model) {
    final relatedTo =
        (_str(json['related_to']) ?? _str(json['related_to_model']) ?? '')
            .toLowerCase();
    if (relatedTo != model) return null;
    return _str(json['related_to_id']) ?? _str(json['related_to_object_id']);
  }

  static const Map<String, String> _channelLabels = {
    'email': 'Email',
    'whatsapp': 'WhatsApp',
    'phone': 'Phone',
    'api': 'API/Webhook',
  };

  static String _channel(Map<String, dynamic> json) =>
      _str(json['channel_display']) ??
      _channelLabels[(_str(json['channel']) ?? _str(json['source']) ?? '')
          .toLowerCase()] ??
      'Email';

  static String? _statusName(Object? status) =>
      status is Map ? _str(status['name']) : _str(status);

  /// Backend `Critical` has no UI twin — it lands on `Urgent` (closest
  /// severity) instead of `priorityKey`'s Medium fallback.
  static String _uiPriority(String? v) =>
      (v ?? '').toLowerCase().startsWith('crit') ? 'Urgent' : priorityKey(v);

  static List<String> _assignees(Map<String, dynamic> json) {
    final out = <String>[];

    void add(Object? user, {String? name}) {
      String mapped = '';
      if (user is Map) {
        UserDirectory.registerJson(user);
        mapped = UserDirectory.mapUserId(_str(user['user_id']));
      } else if (user is String && user.isNotEmpty) {
        if (name != null) UserDirectory.register(userId: user, fullName: name);
        mapped = UserDirectory.mapUserId(user);
      }
      if (mapped.isNotEmpty && !out.contains(mapped)) out.add(mapped);
    }

    add(json['assigned_to'], name: _str(json['assigned_to_name']));
    final many = json['assignees'] ?? json['assigned_users'];
    if (many is List) {
      for (final user in many) {
        add(user);
      }
    }
    return out;
  }

  // ── Write payload ──

  static const Map<String, String> _channelCodes = {
    'phone': 'phone',
    'email': 'email',
    'whatsapp': 'whatsapp',
    'api': 'api',
  };

  /// UI field map → serializer field names. Only fields the backend is known
  /// to accept are sent; values that would 400 (non-UUID customer ids from
  /// mock pickers, channels like "Walk-in" outside the backend's choices) are
  /// dropped rather than rejected server-side.
  static Map<String, dynamic> _writePayload(Map<String, dynamic> fields) {
    final out = <String, dynamic>{};
    final subject = _str(fields['subject']) ?? _str(fields['title']);
    if (subject != null) out['subject'] = subject.trim();
    if (fields.containsKey('description')) {
      out['description'] = _str(fields['description']) ?? '';
    }
    final pri = _str(fields['priority']);
    if (pri != null) out['priority'] = _apiPriority(pri);
    final channel = _channelCodes[(_str(fields['channel']) ?? '').toLowerCase()];
    if (channel != null) out['channel'] = channel;
    final custId = _str(fields['customer_id']);
    if (custId != null && _uuidRe.hasMatch(custId)) out['customer_id'] = custId;
    return out;
  }

  /// UI priority (`Urgent`) → backend choice (`Critical`).
  static String _apiPriority(String v) {
    final n = v.toLowerCase();
    if (n.startsWith('urg') || n.startsWith('crit')) return 'Critical';
    if (n.startsWith('hi')) return 'High';
    if (n.startsWith('lo')) return 'Low';
    return 'Medium';
  }
}
