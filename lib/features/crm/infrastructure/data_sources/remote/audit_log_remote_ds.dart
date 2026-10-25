import 'package:intl/intl.dart';

import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../domain/entities/audit_entry.dart';

/// A record's activity log: `GET /access-control/audit-logs/`.
///
/// Shared across modules — the same endpoint backs the Lead, Customer and
/// Quotation activity cards, differing only by `model_name` + `record_id`.
///
/// **This endpoint returns raw diffs.** Unlike the project/task activity feeds,
/// it sends no `summary` or `event_type`, so the humanizing here is not
/// decoration — without it there is nothing renderable, just before/after field
/// dumps.
///
/// Best-effort: any failure yields an empty list. Reading the audit trail needs
/// the `view_audit_log` permission, so a perfectly ordinary user gets a 403 —
/// that must not break the page they came for.
class AuditLogRemoteDataSource {
  const AuditLogRemoteDataSource(this._api);

  final ApiService _api;

  /// Newest-first, capped — an activity card shows a recent history, not the
  /// record's entire life.
  static const int _pageSize = 30;

  Future<List<AuditEntry>> fetchFor({
    required String modelName,
    required String recordId,
    Map<String, String> statusNames = const {},
    String recordLabel = 'Lead',
  }) async {
    if (recordId.isEmpty) return const [];
    try {
      final body = await _api.get(ApiEndpoints.auditLogs, query: {
        'model_name': modelName,
        'record_id': recordId,
        'ordering': '-timestamp',
        'page_size': _pageSize,
      });
      final rows = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
      return mapEntries(rows, statusNames: statusNames, recordLabel: recordLabel);
    } on Object {
      return const [];
    }
  }

  // ── mapping (visible for tests) ──

  static List<AuditEntry> mapEntries(
    List<dynamic> rows, {
    Map<String, String> statusNames = const {},
    String recordLabel = 'Lead',
  }) {
    final out = <AuditEntry>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final entry = mapEntry(row, statusNames: statusNames, recordLabel: recordLabel);
      if (entry != null) out.add(entry);
    }
    return out;
  }

  /// Turns one raw audit row into a readable timeline entry, or null when the
  /// row describes nothing worth showing.
  ///
  /// [statusNames] maps `lead_status_id` → name so a stage change reads
  /// "Status changed to Qualified" rather than quoting a uuid at the user.
  static AuditEntry? mapEntry(
    Map<String, dynamic> row, {
    Map<String, String> statusNames = const {},
    /// What the record is called in the log's own sentences ("Lead",
    /// "Customer", "Task", "Follow-up", "Quote"…).
    String recordLabel = 'Lead',
  }) {
    final id = _str(row['audit_log_id']);
    if (id.isEmpty) return null;

    final action = _str(row['action']).toLowerCase();
    final rawChanges = row['changes'];
    final changes = rawChanges is Map ? rawChanges : const <String, dynamic>{};
    // Same actor rule as the webapp: an automation's label, else the user, else
    // their email, else the system.
    final actor = _firstNonEmpty([
      _str(changes['actor_label']),
      _str(row['user_full_name']),
      _str(row['user_email']),
    ]);
    final at = parseApiDate(row['timestamp']);
    final noun = recordLabel.toLowerCase();

    AuditEntry build(AuditEventKind kind, String title, [String detail = '']) => AuditEntry(
          id: id,
          kind: kind,
          title: title,
          subtitle: _withActor(detail, actor),
          at: at,
          actor: actor,
        );

    // Written by the automation engine: name the rule and what it applied.
    final automation = changes['automation'];
    if (automation is Map) {
      final rule = _str(automation['rule_name']).trim();
      final summary = _appliedSummary(automation['applied']);
      final ruleName = rule.isEmpty ? 'automation' : rule;
      return build(
        action == 'create' ? AuditEventKind.created : AuditEventKind.fieldChanged,
        'Automation ran',
        summary.isEmpty ? ruleName : '$ruleName — $summary',
      );
    }

    // A linked item (note, task, call, quote) was created / updated / deleted:
    // "Created note", detail its label — the webapp's wording.
    final related = changes['related_change'];
    if (related is Map) {
      final type = _str(related['type']);
      final verb = _verb(_str(related['action']).toLowerCase());
      return build(
        type.toLowerCase() == 'note' ? AuditEventKind.noteAdded : AuditEventKind.childAdded,
        '$verb ${_relatedTypeLabel(type)}',
        _str(related['label']),
      );
    }

    // A lifecycle event the backend raised itself (SLA clock, ticket reopen).
    final event = changes['issue_event'];
    if (event is Map) {
      final type = _str(event['type']);
      if (type.isNotEmpty) {
        return AuditEntry(
          id: id,
          kind: _eventKind(type),
          title: _eventLabel(type),
          subtitle: 'System',
          at: at,
        );
      }
    }

    // The action decides create/delete first: a create also carries a request
    // body, which would otherwise read as an update.
    // Tasks and follow-ups read "Created task"; every other record reads
    // "<Record> created" ("Lead created", "Customer created", "Quote created").
    final leadStyle = noun != 'task' && noun != 'follow-up';
    if (action == 'create') {
      return build(AuditEventKind.created, leadStyle ? '$recordLabel created' : 'Created $noun');
    }
    if (action == 'delete') {
      return build(AuditEventKind.deleted, leadStyle ? '$recordLabel deleted' : 'Deleted $noun');
    }

    final updated = 'Updated $noun';

    // The recorded diff ("Status: New → Qualified") is the whole story when the
    // server sent one.
    final diff = formatAuditDiff(changes);
    if (diff != null) {
      final statusOnly = changes['diff'] is List &&
          (changes['diff'] as List).length == 1 &&
          (changes['diff'] as List).first is Map &&
          '${((changes['diff'] as List).first as Map)['field']}'.startsWith('status');
      return build(statusOnly ? AuditEventKind.statusChanged : AuditEventKind.fieldChanged, updated, diff);
    }

    // An older row: summarise the submitted fields, old → new where both sides
    // are printable.
    final body = changes['request_body'];
    if (body is Map && body.isNotEmpty) {
      final keys = body.keys.map((k) => '$k').toList();
      final isStatus = keys.length == 1 && (keys.first == 'status_id' || keys.first == 'status');
      return build(
        isStatus ? AuditEventKind.statusChanged : AuditEventKind.fieldChanged,
        updated,
        _fieldChangeDetail(body, changes['before'], statusNames),
      );
    }

    return build(AuditEventKind.other, '${_verb(action)} $noun');
  }

  // ── webapp audit wording (leadAudit.response.ts / auditDiff.ts) ──

  static const _relatedLabels = {
    'CRMCallLog': 'call',
    'Task': 'task',
    'Note': 'note',
    'Lead': 'lead',
    'Quotation': 'quote',
  };

  static String _relatedTypeLabel(String type) =>
      type.isEmpty ? 'item' : (_relatedLabels[type] ?? type);

  static String _verb(String action) => switch (action) {
        'create' => 'Created',
        'update' => 'Updated',
        'delete' => 'Deleted',
        _ => 'Changed',
      };

  static const _fieldLabels = {
    'lead_owner': 'lead owner',
    'assignees': 'assignees',
    'status': 'status',
    'status_id': 'status',
    'organization_name': 'company name',
    'lead_name': 'lead name',
    'email': 'email',
    'mobile_no': 'contact',
    'whatsapp_no': 'WhatsApp',
    'lead_value': 'value',
    'lead_source': 'lead source',
    'territory': 'territory',
    'custom_fields': 'custom fields',
    'priority': 'priority',
    'assigned_to': 'assignee',
    'assigned_team': 'team',
    'task_type': 'type',
    'due_date': 'due date',
    'due_time': 'due time',
  };

  static String _fieldLabelLower(String key) =>
      _fieldLabels[key] ?? key.replaceAll('_', ' ');

  static final _uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false);

  /// A value worth printing inline: a short, non-id scalar.
  static String? _scalar(Object? v) {
    if (v == null) return null;
    if (v is bool) return v ? 'Yes' : 'No';
    if (v is num) return '$v';
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty || s.length > 40 || _uuid.hasMatch(s)) return null;
      return s;
    }
    return null;
  }

  /// "status: New → Contacted, email: a@x.in" for the scalar fields, else
  /// "Changed <fields>" — the webapp's `fieldChangeDetail`.
  static String _fieldChangeDetail(Map body, Object? before, Map<String, String> statusNames) {
    final prev = before is Map ? before : const {};
    final parts = <String>[];
    for (final entry in body.entries) {
      final key = '${entry.key}';
      final label = _fieldLabelLower(key);
      var next = _scalar(entry.value);
      var old = _scalar(prev[key]);
      if (key == 'status' || key == 'status_id') {
        next = statusNames['${entry.value}'] ?? next;
        old = statusNames['${prev['status_id'] ?? prev[key]}'] ?? old;
      }
      if (next != null && old != null && next != old) {
        parts.add('$label: $old → $next');
      } else if (next != null && old == null) {
        parts.add('$label: $next');
      }
    }
    if (parts.isNotEmpty) return parts.join(', ');
    return 'Changed ${body.keys.map((k) => _fieldLabelLower('$k')).join(', ')}';
  }

  /// Columns the system derives from another change — never an edit of their own.
  static const _derived = {
    'stage_entered_at', 'status_entered_at', 'lead_score', 'lead_score_breakdown',
    'lead_score_updated_at', 'customer_score', 'customer_score_breakdown',
    'customer_score_updated_at', 'updated_at', 'modified_by',
  };

  static String _diffValue(Object? v) {
    if (v == null) return '—';
    if (v is bool) return v ? 'Yes' : 'No';
    if (v is num) return '$v';
    if (v is String) {
      final t = v.trim();
      if (t.isEmpty) return '—';
      if (_uuid.hasMatch(t)) return 'unknown';
      final date = DateTime.tryParse(t);
      if (date != null && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(t)) {
        return t.length <= 10
            ? DateFormat('d MMM yyyy').format(date)
            : DateFormat('d MMM yyyy, h:mm a').format(date.toLocal());
      }
      return t.length > 60 ? '${t.substring(0, 59).trimRight()}…' : t;
    }
    if (v is List) {
      final parts = v.map(_diffValue).where((p) => p != '—').toList();
      return parts.isEmpty ? '—' : parts.join(', ');
    }
    if (v is Map) {
      for (final k in const ['label', 'name', 'full_name', 'display']) {
        final n = v[k];
        if (n is String && n.trim().isNotEmpty) return _diffValue(n);
      }
      return 'unknown';
    }
    return 'unknown';
  }

  /// The row's `changes.diff` as one line ("Status: Open → Completed;
  /// Assignees: +Asha"), or null when the row has no diff — the webapp's
  /// `formatAuditDiff`.
  static String? formatAuditDiff(Map changes) {
    final diff = changes['diff'];
    if (diff is! List) return null;
    final out = <String>[];
    for (final raw in diff) {
      if (raw is! Map) continue;
      final field = raw['field'];
      if (field is String && _derived.contains(field)) continue;
      final rawLabel = raw['label'];
      final label = rawLabel is String && rawLabel.trim().isNotEmpty
          ? rawLabel.trim()
          : (field is String ? _humanize(field) : '');
      if (label.isEmpty) continue;
      if (raw.containsKey('added') || raw.containsKey('removed')) {
        List<String> names(Object? v) =>
            v is List ? v.map(_diffValue).where((n) => n != '—').toList() : const [];
        final added = names(raw['added']);
        final removed = names(raw['removed']);
        if (added.isEmpty && removed.isEmpty) continue;
        out.add('$label: ${[...added.map((n) => '+$n'), ...removed.map((n) => '−$n')].join(', ')}');
        continue;
      }
      final from = _diffValue(raw.containsKey('old') ? raw['old'] : raw['before']);
      final to = _diffValue(raw.containsKey('new') ? raw['new'] : raw['after']);
      if (from != to) out.add('$label: $from → $to');
    }
    return out.join('; ');
  }

  /// One line for what an automation applied.
  static String _appliedSummary(Object? applied) {
    if (applied is! List) return '';
    const models = {
      'lead': 'Lead', 'customer': 'Customer', 'task': 'Task',
      'followup': 'Follow-up', 'quote': 'Quote',
    };
    final parts = <String>[];
    for (final raw in applied) {
      if (raw is! Map) continue;
      final action = _str(raw['action']);
      final label = _str(raw['record_label']).trim();
      if (action == 'create_row') {
        final m = _str(raw['model']);
        final model = models[m] ?? (m.isEmpty ? 'record' : _humanize(m));
        parts.add(label.isEmpty ? 'created $model' : "created $model '$label'");
      } else if (action == 'notify') {
        final listed = raw['recipients'] is List
            ? (raw['recipients'] as List).whereType<String>().join(', ')
            : '';
        parts.add(listed.isEmpty ? 'sent a notification' : 'notified $listed');
      } else if (raw['changes'] is Map) {
        (raw['changes'] as Map).forEach((field, ch) {
          if (ch is! Map) return;
          final to = _scalar(ch['to']);
          final from = _scalar(ch['from']);
          if (to == null) return;
          final label = _humanize('$field');
          parts.add(from != null && from != to ? '$label: $from → $to' : '$label: $to');
        });
      }
    }
    return parts.join('; ');
  }

  static String _humanize(String key) {
    final k = key.replaceAll('_', ' ').trim();
    return k.isEmpty ? key : '${k[0].toUpperCase()}${k.substring(1)}';
  }

  static String _firstNonEmpty(List<String> values) {
    for (final v in values) {
      if (v.trim().isNotEmpty) return v.trim();
    }
    return 'System';
  }

  static String _withActor(String detail, String actor) {
    final by = actor.isEmpty ? '' : 'by $actor';
    if (detail.isEmpty) return by;
    return by.isEmpty ? detail : '$detail · $by';
  }

  /// `sla_breached` → "SLA breached".
  static String _eventLabel(String type) {
    switch (type) {
      case 'sla_breached':
        return 'SLA breached';
      case 'first_response_breached':
        return 'First-response SLA breached';
      case 'sla_paused':
        return 'SLA paused';
      case 'sla_resumed':
        return 'SLA resumed';
      case 'reopened':
        return 'Ticket reopened';
      case 'resolved':
        return 'Ticket resolved';
      case 'closed':
        return 'Ticket closed';
      case 'escalated':
        return 'Ticket escalated';
    }
    // An event the app has no sentence for still reads as something: the raw
    // type, humanised, beats swallowing the row.
    final words = type.replaceAll('_', ' ').trim();
    if (words.isEmpty) return 'Ticket updated';
    return '${words[0].toUpperCase()}${words.substring(1)}';
  }

  static AuditEventKind _eventKind(String type) =>
      type.contains('breach') || type.contains('escalat')
          ? AuditEventKind.other
          : AuditEventKind.statusChanged;

  static String _str(Object? v) => v is String ? v : '';
}
