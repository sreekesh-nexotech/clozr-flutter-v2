import 'dart:ui' show Color;

import 'package:dio/dio.dart' show FormData, MultipartFile;

import '../../../../../core/config/api_config.dart';
import '../../../../../core/network/app_error.dart';
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
        final pri = (row['default_priority'] ?? '').toString().trim();
        out.add(CatalogOption(id: id, name: name, defaultPriority: pri.isEmpty ? null : pri));
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
        final hex = (row['color'] ?? '').toString().replaceFirst('#', '');
        final rgb = hex.length == 6 ? int.tryParse(hex, radix: 16) : null;
        out.add(CatalogOption(
          id: id,
          name: name,
          // The org's own dot colour — the status chips and card pills.
          color: rgb == null ? null : Color(0xFF000000 | rgb),
          isClosed: row['is_resolved'] == true,
          isDefault: row['is_default'] == true,
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
      // Quiet: the detail screen reports a refusal itself, as its own notice.
      final body = await _api.get(ApiEndpoints.issue(id), quiet: true);
      return body is Map<String, dynamic> ? mapTicket(body) : null;
    } on AppError catch (e) {
      // Gone → "Ticket not found". Anything else (no access, a server fault,
      // no network) is an error the screen explains, not a missing ticket.
      if (e.type == AppErrorType.notFound) return null;
      rethrow;
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
    final status = json['status'];
    return TicketTask(
      id: _str(json['task_id']) ?? _str(json['id']) ?? '',
      subject: _str(json['subject']) ?? '',
      // `status` is the status uuid on this serializer; the name rides beside it.
      status: _str(json['status_name']) ??
          (status is Map ? _str(status['name']) : null) ??
          '',
      priority: _str(json['priority']) ?? '',
      projectName: _str(json['project_name']) ?? (project is Map ? _str(project['name']) ?? '' : ''),
      isOverdue: json['is_overdue'] == true,
      projectId: _str(json['project_id']) ?? (project is Map ? _str(project['project_id']) : _str(project)),
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

  /// `GET issues/{id}/children/` — one parent's direct children. Quiet: the
  /// tab says "No child tickets" rather than toasting a refusal.
  Future<List<Ticket>> fetchChildren(String issueId) async {
    if (issueId.isEmpty) return const [];
    final body = await _api.get(ApiEndpoints.issueChildren(issueId), quiet: true, query: {'page_size': 100});
    return mapTickets(Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results);
  }

  /// The "Attach a child ticket" candidates: tickets without a parent
  /// (`is_child=false`) matching [search], first 20.
  Future<List<Ticket>> searchRootTickets(String search) async {
    final q = search.trim();
    final body = await _api.get(ApiEndpoints.issues, quiet: true, query: {
      'is_child': 'false',
      'page': 1,
      'page_size': 20,
      if (q.isNotEmpty) 'search': q,
    });
    return mapTickets(Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results);
  }

  /// Attaches [issueId] under [parentId], or detaches it with null. The write
  /// key is `parent_issue_id` (the read key `parent_issue` is ignored).
  Future<void> setParent(String issueId, String? parentId) =>
      _api.patch(ApiEndpoints.issue(issueId), body: {'parent_issue_id': parentId});

  /// `POST issues/{id}/log-first-response/` — stamps `first_responded_at`
  /// for a response given outside Clozr.
  Future<void> logFirstResponse(String issueId) =>
      _api.post(ApiEndpoints.issueLogFirstResponse(issueId), body: const <String, dynamic>{});

  /// `POST issues/{id}/replies/ {body}` — dispatched by the server through the
  /// ticket's own channel (email / WhatsApp).
  Future<void> sendReply(String issueId, String body) =>
      _api.post(ApiEndpoints.issueReplies(issueId), body: {'body': body});

  /// Multipart `POST /crm/attachments/` against the ticket
  /// (`related_to=issue`), as the webapp's Files tab sends it.
  Future<void> uploadAttachment(String issueId, {required String path, required String name}) async {
    final form = FormData.fromMap({
      'related_to': 'issue',
      'related_to_id': issueId,
      'name': name,
      'file_upload': await MultipartFile.fromFile(path, filename: name),
    });
    await _api.postForm(ApiEndpoints.attachments, form);
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
      // Webapp audit row: "<actor> · <date-time>".
      subtitle: isSystem ? 'System' : actorName,
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
        // Date and time, as the webapp's detail rows print them
        // (`formatDateTime`); the list's "5m ago" reads [createdISO].
        created: absoluteDateTime(parseApiDate(json['created_at'])),
        createdISO: _str(json['created_at']),
        responded: respondedAt == null ? null : absoluteDateTime(respondedAt),
        resolved: resolvedAt == null ? null : absoluteDateTime(resolvedAt),
        // Kept beside the display form: the resolved-grid's within/after-SLA
        // split needs the real instant, not the day.
        resolvedISO: resolvedAt?.toIso8601String(),
        respondedISO: respondedAt?.toIso8601String(),
        respByISO: respByISO,
        respByLabel: _slaLabel(respByISO),
        resolveByISO: resolveByISO,
        resolveByLabel: _slaLabel(resolveByISO),
        desc: _str(json['description']) ?? '',
        // Live on the list serializer today, with `billable` false and the
        // other three null on every row. All four tolerate absent and null —
        // this mapper only ever reads keys it names.
        billable: json['billable'] == true,
        billableAmount: _str(json['billable_amount']),
        billableProductId: _str(json['billable_product']),
        billedDocumentLineId: _str(json['billed_document_line_id']),
        facts: _facts(json),
      );
    } on Object {
      return null;
    }
  }

  /// The row's own status / SLA facts (webapp `issue.response.ts`).
  static TicketServerFacts _facts(Map<String, dynamic> json) {
    final st = json['status'];
    final status = st is Map ? st : const {};
    double? num_(Object? v) => v is num ? v.toDouble() : null;
    final deadline = _str(json['sla_deadline']);
    final remaining = num_(json['sla_remaining_seconds']);
    return TicketServerFacts(
      statusColor: _str(status['color']),
      statusResolved: status['is_resolved'] == true,
      statusOnHold: status['is_on_hold'] == true,
      typeName: _str(json['type_name']),
      customerName: _str(json['customer_name']),
      contactName: _str(json['contact_name']),
      contactId: _str(json['contact']) ?? _str(json['contact_id']),
      reportedFor: _str(json['reported_for']) == 'self' ? 'self' : 'client',
      assignedToId: _str(json['assigned_to']),
      assignedToName: _str(json['assigned_to_name']),
      hasSla: deadline != null || remaining != null,
      slaRemainingSeconds: remaining,
      slaHoldStarted: _str(json['sla_hold_started_at']) != null,
      slaBreachedFlag: json['sla_breached'] == true,
      firstResponseDue: _str(json['first_response_due_at']) != null,
      firstResponded: _str(json['first_responded_at']) != null,
      firstResponseRemainingSeconds: num_(json['first_response_remaining_seconds']),
      firstResponseBreached: json['is_first_response_breached'] == true,
      channelCode: _str(json['channel'])?.toLowerCase(),
      slaValue: json['sla_value'] is num ? json['sla_value'] as num : num.tryParse('${json['sla_value'] ?? ''}'),
      slaUnit: _str(json['sla_unit']) ?? '',
      parentIssueId: _parentId(json['parent_issue']),
      parentReference: _str(json['parent_reference']) ?? '',
      parentSubject: _str(json['parent_subject']) ?? '',
      childCount: (json['child_count'] as num?)?.toInt() ?? 0,
      // Falls back to the parent link so a trimmed serializer cannot make a
      // child render as a root (webapp `isChild`).
      isChild: json['is_child'] == true || _parentId(json['parent_issue']) != null,
      attachments: _attachments(json['attachments']),
      replies: _replies(json['notes']),
      customFields: _customFields(json['custom_fields']),
    );
  }

  static String? _parentId(Object? v) => v is Map ? _str(v['issue_id']) : _str(v);

  /// `attachments[]` → [TicketAttachment], skipping rows without an id.
  static List<TicketAttachment> _attachments(Object? raw) {
    if (raw is! List) return const [];
    final out = <TicketAttachment>[];
    for (final r in raw) {
      if (r is! Map) continue;
      final id = _str(r['attachment_id']);
      if (id == null) continue;
      final by = r['uploaded_by'];
      out.add(TicketAttachment(
        id: id,
        name: _str(r['name']) ?? 'File',
        url: _str(r['file_url']) ?? _str(r['file']) ?? '',
        uploadedAt: parseApiDate(r['uploaded_at']),
        uploadedBy: (by is Map ? (_str(by['name']) ?? _str(by['full_name'])) : null) ??
            _str(r['uploaded_by_name']) ??
            '',
        uploadedById: (by is Map ? _str(by['user_id']) : _str(by)) ?? _str(r['uploaded_by_id']),
      ));
    }
    return out;
  }

  /// The customer replies among `notes[]` — every note whose `kind` is set and
  /// is not `internal` (webapp: a missing kind is an internal note).
  static List<TicketReply> _replies(Object? raw) {
    if (raw is! List) return const [];
    final out = <TicketReply>[];
    for (final r in raw) {
      if (r is! Map) continue;
      final kind = _str(r['kind']) ?? 'internal';
      final id = _str(r['note_id']);
      if (kind == 'internal' || id == null) continue;
      final by = r['created_by'];
      out.add(TicketReply(
        id: id,
        body: _str(r['content']) ?? '',
        author: (by is Map ? (_str(by['name']) ?? _str(by['full_name'])) : null) ??
            _str(r['created_by_name']) ??
            '',
        at: parseApiDate(r['created_at']),
      ));
    }
    return out;
  }

  /// `custom_fields` as display strings; empty for every non-webhook ticket.
  static Map<String, String> _customFields(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        '${e.key}': e.value == null ? '' : (e.value is String ? e.value as String : '${e.value}'),
    };
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
    // `client` (a customer's ticket) or `self` (internal — no customer, no SLA).
    final reportedFor = _str(fields['reported_for']);
    if (reportedFor == 'client' || reportedFor == 'self') out['reported_for'] = reportedFor;
    // The org's issue type, which the category chips now offer verbatim.
    //
    // These links accept an explicit null, which clears them (verified against
    // the dev backend) — so "absent" and "cleared" must stay distinguishable:
    // a key sent as null is "Uncategorised" / no customer / "No contact" /
    // "Unassigned", a missing key leaves the ticket's value alone.
    for (final key in const ['customer_id', 'issue_type', 'contact_id', 'assigned_to']) {
      if (!fields.containsKey(key)) continue;
      final id = _str(fields[key]);
      if (id == null) {
        out[key] = null;
      } else if (_uuidRe.hasMatch(id)) {
        out[key] = id;
      }
    }
    // The status, under the serializer's **write** name.
    //
    // Nested `status` is read-only, and this builder used to have no case for
    // it at all — so a caller passing `{'status': <uuid>}` produced an *empty*
    // body. `PATCH {}` answers 200 and only bumps `updated_at`, so the status
    // chip reported success, changed nothing, and reverted on the next read.
    // Worse, it hid the backend's own rules: placing a ticket on hold is
    // refused with "A mandatory note must be added to the issue before placing
    // it on hold", which the user never saw because the request carried no
    // status to refuse.
    final statusId = _str(fields['status_id']) ?? _str(fields['status']);
    if (statusId != null && _uuidRe.hasMatch(statusId)) {
      out['status_id'] = statusId;
    }
    // Billing (handover §9.5). Only when the form sent it.
    if (fields['billable'] is bool) out['billable'] = fields['billable'];
    if (fields.containsKey('billable_amount')) {
      final amount = _str(fields['billable_amount']);
      out['billable_amount'] = amount != null && double.tryParse(amount) != null ? amount : null;
    }
    if (fields.containsKey('billable_product_id')) {
      final id = _str(fields['billable_product_id']);
      out['billable_product_id'] = id != null && _uuidRe.hasMatch(id) ? id : null;
    }
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
