import '../../../../../core/config/api_config.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../../../data/api/status_keys.dart';
import '../../../../../data/api/user_directory.dart';
import '../../../../crm/domain/entities/audit_entry.dart';
import '../../../../crm/domain/entities/crm_catalog.dart';
import '../../../domain/entities/issue_summary.dart';
import '../../../domain/entities/ticket.dart';
import '../../../domain/entities/ticket_task.dart';

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

  /// Raw issue rows for [filters] — the documented `IssueFilter` params
  /// (`issue-filters.md` Part 4), applied **server-side**.
  Future<List<Map<String, dynamic>>> fetchTicketRows({
    Map<String, dynamic> filters = const {},
  }) async {
    final rows = <Map<String, dynamic>>[];
    var page = 1;
    while (page <= 50) {
      final body = await _api.get(ApiEndpoints.issues, query: {
        // Paging steers the walk itself, so a stored filter can never own it.
        ...{...filters}..removeWhere((k, _) => k == 'page' || k == 'page_size'),
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

  Future<List<Ticket>> fetchTickets({
    Map<String, dynamic> filters = const {},
  }) async =>
      mapTickets(await fetchTicketRows(filters: filters));

  /// The org's issue types (`/crm/issue-types/`) — the Category chips on the
  /// create/edit forms and the drawer's Category facet.
  ///
  /// Best-effort: a failure yields the empty list, which callers read as "no
  /// catalog, use the built-in vocabulary".
  Future<List<CatalogOption>> fetchIssueTypes() async {
    try {
      final body =
          await _api.get(ApiEndpoints.issueTypes, query: {'page_size': 100});
      final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
      final out = <CatalogOption>[];
      for (final row in rows) {
        if (row['is_active'] == false) continue;
        final id = (row['issue_type_id'] ?? '').toString();
        final name = (row['name'] ?? '').toString();
        if (id.isEmpty || name.isEmpty) continue;
        out.add(CatalogOption(id: id, name: name));
      }
      return out;
    } on Object {
      return const [];
    }
  }

  /// The org's own issue statuses (`/crm/issue-statuses/`) — the drawer's
  /// Status facet and the tab strip's vocabulary.
  ///
  /// Best-effort: a failure yields the empty list, which callers read as "no
  /// catalog, use the built-in vocabulary".
  Future<List<CatalogOption>> fetchIssueStatuses() async {
    try {
      final rows = await _fetchStatusRows();
      final out = <CatalogOption>[];
      for (final row in rows) {
        if (row['is_active'] == false) continue;
        final id = (row['issue_status_id'] ?? '').toString();
        final name = (row['name'] ?? '').toString();
        if (id.isEmpty || name.isEmpty) continue;
        out.add(CatalogOption(
          id: id,
          name: name,
          isClosed: row['is_resolved'] == true,
        ));
      }
      return out;
    } on Object {
      return const [];
    }
  }

  /// Per-status tab counts (`/crm/issues/status-counts/`), under the same
  /// filters as the list.
  ///
  /// Keyed by `issue_status_id`, plus `'all'` for the total. Empty on failure,
  /// which the strip reads as "count the loaded rows instead" rather than
  /// showing an empty tab bar.
  Future<Map<String, int>> fetchStatusCounts({
    Map<String, dynamic> filters = const {},
  }) async {
    try {
      final body = await _api.get(
        ApiEndpoints.issueStatusCounts,
        // The tab itself is dropped: the endpoint answers every status at
        // once, so keeping it would scope the strip to the open tab.
        query: {...filters}..removeWhere(
            (k, _) => k == 'status__in' || k == 'page' || k == 'page_size'),
      );
      if (body is! Map) return const {};
      final out = <String, int>{};
      final total = body['total'];
      if (total is num) out['all'] = total.toInt();
      final rows = body['statuses'];
      if (rows is List) {
        for (final row in rows) {
          if (row is! Map) continue;
          final id = (row['issue_status_id'] ?? '').toString();
          final count = row['count'];
          if (id.isEmpty || count is! num) continue;
          out[id] = count.toInt();
        }
      }
      return out;
    } on Object {
      return const {};
    }
  }

  /// `GET /crm/issues/summary/` — the Support Overview figures (§7), under the
  /// same filters as the list.
  ///
  /// Best-effort: any failure answers null and the screen falls back to
  /// counting the tickets it loaded.
  Future<IssueSummary?> fetchSummary({
    Map<String, dynamic> filters = const {},
  }) async {
    try {
      return IssueSummary.fromJson(
        await _api.get(ApiEndpoints.issueSummary, query: filters),
      );
    } on Object {
      return null;
    }
  }

  /// `GET /crm/issues/{id}/activity/` — the ticket's own audit feed (§10).
  ///
  /// Not the org-wide `/access-control/audit-logs/`: that one needs
  /// `view_audit_log`, so an agent without it saw an empty card on a ticket
  /// they can otherwise read. This one is gated by `view_issue` and scoped
  /// through the ticket, and its rows arrive **pre-humanized** (`summary`) with
  /// an `actor` that flags system events.
  ///
  /// [names] resolves the uuids the server leaves in a summary ("Status changed
  /// to f164d805-…") back to org names.
  Future<List<AuditEntry>> fetchActivity(
    String issueId, {
    Map<String, String> names = const {},
  }) async {
    if (issueId.isEmpty) return const [];
    try {
      final body = await _api.get(
        ApiEndpoints.issueActivity(issueId),
        query: {'page_size': 50},
      );
      final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
      return [
        for (final row in rows)
          if (activityFromJson(row, names: names) case final e?) e,
      ];
    } on Object {
      return const [];
    }
  }

  /// One ticket, straight from `GET /crm/issues/{id}/` (§8).
  ///
  /// The detail screen used to pick its ticket out of the org-wide list, so it
  /// could only show what that list happened to hold — and a saved edit did not
  /// land until the whole list had been walked again. Null on any failure, which
  /// sends the screen back to the list row.
  Future<Ticket?> fetchTicket(String id) async {
    if (id.isEmpty) return null;
    try {
      final body = await _api.get(ApiEndpoints.issue(id));
      return body is Map<String, dynamic> ? mapTicket(body) : null;
    } on Object {
      return null;
    }
  }

  /// The Operations tasks raised from this ticket (`helpdesk.md` §10).
  ///
  /// Empty on any failure: the Linked-tasks card is a secondary panel, and a
  /// permission gap on `view_issue`'s task list must not take the detail screen
  /// down with it.
  Future<List<TicketTask>> fetchLinkedTasks(String issueId) async {
    if (issueId.isEmpty) return const [];
    try {
      final body = await _api.get(
        ApiEndpoints.issueTasks(issueId),
        query: {'page_size': 50},
      );
      final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
      return [for (final row in rows) linkedTaskFromJson(row)];
    } on Object {
      return const [];
    }
  }

  /// One `/issues/{id}/tasks/` row → [TicketTask]. The row is a projects
  /// `Task`: `status` and `assigned_to` arrive as nested objects (or null).
  static TicketTask linkedTaskFromJson(Map<String, dynamic> json) {
    final assignee = json['assigned_to'];
    final project = json['project'];
    return TicketTask(
      id: _str(json['task_id']) ?? '',
      subject: _str(json['subject']) ?? '',
      status: _statusName(json['status']) ?? '',
      priority: _str(json['priority']) ?? '',
      projectId: project is Map ? _str(project['project_id']) : _str(project),
      assigneeName: assignee is Map
          ? (_str(assignee['full_name']) ?? _str(assignee['username']) ?? '')
          : '',
    );
  }

  // ── Writes ──

  /// POST a new issue. Sends only fields the serializer is known to accept.
  Future<Ticket?> createTicket(Map<String, dynamic> fields) async {
    final body = await _api.post(ApiEndpoints.issues, body: writePayload(fields));
    return body is Map<String, dynamic> ? mapTicket(body) : null;
  }

  /// PATCH subject/description/priority (and channel/customer when valid).
  Future<void> updateTicket(String id, Map<String, dynamic> fields) =>
      _api.patch(ApiEndpoints.issue(id), body: writePayload(fields));

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

  /// Sets the ticket's assignee. [userId] is the server's `user_id` uuid;
  /// null clears the assignment (both verified against the dev backend).
  ///
  /// The write field is `assigned_to`, not `assigned_to_id` — the latter is
  /// accepted with a `200` and silently ignored, so a "saved" toast would lie.
  Future<void> setAssignee(String id, String? userId) =>
      _api.patch(ApiEndpoints.issue(id), body: {'assigned_to': userId});

  /// Raises an Operations task against this ticket (`POST /issues/{id}/tasks/`).
  /// The ticket link comes from the URL, so it is never in the body. `subject`
  /// is the only required field.
  Future<TicketTask?> createLinkedTask(
    String issueId, {
    required String subject,
    String? priority,
  }) async {
    final body = await _api.post(ApiEndpoints.issueTasks(issueId), body: {
      'subject': subject.trim(),
      if (priority != null && priority.isNotEmpty) 'priority': priority,
    });
    return body is Map<String, dynamic> ? linkedTaskFromJson(body) : null;
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

  /// One `/issues/{id}/activity/` row → [AuditEntry].
  ///
  /// The server writes the sentence; this only picks the icon bucket and swaps
  /// any raw uuid in it for the name that uuid belongs to.
  static AuditEntry? activityFromJson(
    Map<String, dynamic> row, {
    Map<String, String> names = const {},
  }) {
    final id = _str(row['audit_log_id']);
    if (id == null || id.isEmpty) return null;

    final actor = row['actor'];
    final isSystem = actor is Map && actor['is_system'] == true;
    final actorName = actor is Map ? _str(actor['name']) ?? '' : '';
    final event = _str(row['event_type']) ?? '';

    var summary = _str(row['summary']) ?? _humanizeEvent(event);
    names.forEach((uuid, name) {
      if (uuid.isNotEmpty && name.isNotEmpty) summary = summary.replaceAll(uuid, name);
    });

    return AuditEntry(
      id: id,
      kind: _activityKind(event),
      title: summary,
      subtitle: isSystem ? 'System' : (actorName.isEmpty ? '' : 'by $actorName'),
      at: parseApiDate(row['timestamp']),
      actor: actorName,
    );
  }

  static AuditEventKind _activityKind(String event) {
    if (event.contains('breach') || event.contains('escalat')) {
      return AuditEventKind.other;
    }
    if (event == 'created') return AuditEventKind.created;
    if (event == 'deleted') return AuditEventKind.deleted;
    if (event.contains('note') || event.contains('reply')) {
      return AuditEventKind.noteAdded;
    }
    if (event.contains('status') || event == 'reopened' || event == 'resolved') {
      return AuditEventKind.statusChanged;
    }
    return AuditEventKind.fieldChanged;
  }

  /// Only used when a row arrives without a `summary`.
  static String _humanizeEvent(String event) {
    final words = event.replaceAll('_', ' ').trim();
    if (words.isEmpty) return 'Ticket updated';
    return '${words[0].toUpperCase()}${words.substring(1)}';
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
        // The number the user knows the ticket by; the uuid above is internal.
        reference: _str(json['reference']) ?? '',
        subject: _str(json['subject']) ?? _str(json['title']) ?? '',
        // The org's own type name is the category. The three-word fold is only
        // for a row that carries no type at all — this org has eight.
        cat: _typeName(json) ?? _category(null),
        typeId: _typeId(json) ?? '',
        custId: _customerId(json),
        contact: '',
        channel: _channel(json),
        status: ticketStatusKey(_statusName(json['status'])),
        // The org's own values, kept verbatim for the drawer and the server
        // params — the folded pair above is for display only.
        statusId: _statusId(json['status']) ?? '',
        statusName: _statusName(json['status']) ?? '',
        pri: _uiPriority(_str(json['priority'])),
        priorityName: _str(json['priority']) ?? '',
        assignees: _assignees(json),
        product: _str(json['product_name']),
        productId: _str(json['product']),
        projId: _str(json['project']) ?? _relatedId(json, 'project'),
        projName: _str(json['project_name']),
        taskId: _relatedId(json, 'task'),
        created: absoluteDate(parseApiDate(json['created_at'])),
        responded: respondedAt == null ? null : absoluteDate(respondedAt),
        resolved: resolvedAt == null ? null : absoluteDate(resolvedAt),
        // Kept beside the display form: the resolved-grid's within/after-SLA
        // split needs the real instant, not the day.
        resolvedISO: resolvedAt?.toIso8601String(),
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

  /// The `issue_type` uuid, however the row carries it.
  static String? _typeId(Map<String, dynamic> json) {
    final type = json['issue_type'];
    if (type is Map) return _str(type['issue_type_id']);
    final s = _str(type);
    return s != null && _uuidRe.hasMatch(s) ? s : null;
  }

  /// Issue-type name → the UI's fixed category set. Only reached when the row
  /// names no type.
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

  static String? _statusId(Object? status) =>
      status is Map ? _str(status['issue_status_id']) : null;

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

  /// UI field map → serializer field names. Public like the read mappers so a
  /// test can assert what a form actually sends. Only fields the backend is known
  /// to accept are sent; values that would 400 (non-UUID customer ids from
  /// mock pickers, channels like "Walk-in" outside the backend's choices) are
  /// dropped rather than rejected server-side.
  static Map<String, dynamic> writePayload(Map<String, dynamic> fields) {
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
    // Both links accept an explicit null, which unlinks them (verified against
    // the dev backend) — so "absent" and "cleared" must stay distinguishable.
    // The org's issue type, which the category chips now offer verbatim.
    final type = _str(fields['issue_type']);
    if (type != null && _uuidRe.hasMatch(type)) out['issue_type'] = type;
    for (final key in const ['product_id', 'project_id']) {
      if (!fields.containsKey(key)) continue;
      final id = _str(fields[key]);
      if (id == null) {
        out[key] = null;
      } else if (_uuidRe.hasMatch(id)) {
        out[key] = id;
      }
    }
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
