
import '../../../../../core/config/api_config.dart';
import '../../../../../core/network/api_endpoints.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/network/paginated.dart';
import '../../../../../core/utils/relative_time.dart';
import '../../../domain/entities/app_notification.dart';

// ─────────────────────────────────────────────────────────────────────────────
// JSON → entity mapping (top-level so unit tests run without an ApiService).
//
// Server contract (confirmed against crm/serializers/communication.py):
//   crm_notification_id (UUID) · type (PascalCase) · category (server-computed:
//   crm|pmo|lms|system|billing) · notification_text · message (HTML) ·
//   read (bool — NOT is_read) · status (unread|read|pinned|snoozed) ·
//   created_at. The list row carries NO source-object id, so record deep-links
//   are not derivable — only list-level targets are mapped.
// ─────────────────────────────────────────────────────────────────────────────

String? _str(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

/// Server `category` (+ `type` refinements) → the UI's fixed category keys
/// (leads/payments/tasks/system/ops/help/training).
String notificationCategoryToUi(String? category, String? type) {
  final t = (type ?? '').toLowerCase();
  // Helpdesk-ish types win over the broad module category.
  if (t.contains('ticket') || t.contains('issue') || t.contains('sla')) {
    return 'help';
  }
  // CRM task / follow-up types read as "Tasks" in the UI.
  if (t.startsWith('task') || t.startsWith('followup')) return 'tasks';
  switch ((category ?? '').toLowerCase()) {
    case 'crm':
      return 'leads';
    case 'pmo':
      return 'ops';
    case 'lms':
      return 'training';
    case 'billing':
      return 'payments';
    default:
      return 'system';
  }
}

/// created_at → the feed's day header bucket.
String notificationDayBucket(DateTime? createdAt, {DateTime? now}) {
  if (createdAt == null) return 'earlier';
  final ref = now ?? DateTime.now();
  final local = createdAt.toLocal();
  final today = DateTime(ref.year, ref.month, ref.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'today';
  if (diff == 1) return 'yesterday';
  return 'earlier';
}

/// `message` is documented as HTML content — strip tags/entities for the
/// two-line plain-text row body.
String _stripHtml(String html) {
  var text = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
  const entities = {
    '&nbsp;': ' ',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
  };
  entities.forEach((k, v) => text = text.replaceAll(k, v));
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 'LeadAssigned' → 'Lead assigned' (title fallback when the row has no text).
String _humanizeType(String type) {
  if (type.isEmpty) return 'Notification';
  final spaced = type
      .replaceAll('_', ' ')
      .replaceAllMapped(RegExp('(?<=[a-z0-9])(?=[A-Z])'), (_) => ' ');
  return spaced[0].toUpperCase() + spaced.substring(1).toLowerCase();
}

/// Whether a notification type is time-critical, which is what drives the
/// row's red/amber treatment.
///
/// Derived from `type` because **the serializer carries no urgency field** —
/// the mapper's `urgent`/`is_urgent`/`priority` reads below match nothing the
/// API sends, so every live row rendered as routine and the design's urgent
/// styling never appeared. The names come from the documented event-type
/// vocabulary (`notification-preference-settings.md` §"Event types"): the
/// deadline and overdue events are the ones a user has to act on.
bool notificationUrgentForType(String type) {
  final t = type.toLowerCase();
  return t.contains('overdue') ||
      t.contains('duereminder') ||
      t.contains('deadline') ||
      t.contains('missed') ||
      t.contains('breach') ||
      t.contains('escalat') ||
      t.contains('expir') ||
      t.contains('dunning') ||
      t.contains('failed') ||
      t.contains('rejected');
}

/// The list a notification's type belongs to.
///
/// The row payload carries **no source-object id** — not even on the detail
/// endpoint, where `source_content_type` comes back null — so a record-level
/// deep link is not derivable. What the type does say is which *module* the
/// event happened in, so the row opens that list instead of nothing at all,
/// which is where every CRM and PMO notification used to land.
(String, String?) _targetFor(String type) {
  final t = type.toLowerCase();
  if (t.startsWith('lms')) return ('list', 'lmsMy');
  if (t.startsWith('payment') ||
      t.startsWith('dunning') ||
      t.startsWith('mandate') ||
      t.startsWith('license')) {
    return ('list', 'billing');
  }
  if (t.startsWith('lead')) return ('list', 'leads');
  if (t.startsWith('followup')) return ('list', 'followups');
  // PMO first: `PmoTask*` also starts with neither `task` nor `project`.
  if (t.startsWith('pmotask')) return ('list', 'opsTasks');
  if (t.startsWith('project')) return ('list', 'projects');
  if (t.startsWith('task')) return ('list', 'tasks');
  if (t.contains('ticket') || t.contains('issue') || t.contains('sla')) {
    return ('list', 'tickets');
  }
  if (t.startsWith('quote')) return ('list', 'quotes');
  if (t.startsWith('user')) return ('list', 'members');
  return ('none', null);
}

/// One `/crm/notifications/` row → [AppNotification]; null when malformed.
AppNotification? notificationFromJson(Map<String, dynamic> row, {DateTime? now}) {
  final id = (row['crm_notification_id'] ?? row['pk'] ?? row['id'])?.toString();
  if (id == null || id.isEmpty) return null;

  final type = _str(row['type']) ?? '';
  final category = notificationCategoryToUi(_str(row['category']), type);

  // No urgency flag exists on the serializer, so the type decides. The
  // explicit reads stay first in case one is ever added.
  final urgent = row['urgent'] == true ||
      row['is_urgent'] == true ||
      _str(row['priority'])?.toLowerCase() == 'high' ||
      notificationUrgentForType(type);

  final text = _str(row['notification_text']);
  final message = _str(row['message']);
  var body = message == null ? '' : _stripHtml(message);
  final title = text ?? (body.isNotEmpty ? body : _humanizeType(type));

  // `message` is empty on every live row, which left the row's second line
  // blank. The person who caused the event is the useful thing to put there —
  // "Kavita Das" under "You have been assigned a task: Write unit tests".
  if (body.isEmpty) body = _str(row['from_user_name']) ?? '';

  // The live field is `read`; `is_read` kept as a defensive alias. When both
  // are absent, fall back to the computed `status` string.
  final readFlag = row['is_read'] ?? row['read'];
  final unread =
      readFlag is bool ? !readFlag : _str(row['status'])?.toLowerCase() == 'unread';

  final created = parseApiDate(row['created_at']);
  final target = _targetFor(type);

  return AppNotification(
    id: id,
    category: category,
    urgent: urgent,
    day: notificationDayBucket(created, now: now),
    type: type,
    title: title,
    body: body == title ? '' : body,
    time: relativeTime(created, now: now),
    unread: unread,
    targetKind: target.$1,
    targetId: target.$2,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Remote data source
// ─────────────────────────────────────────────────────────────────────────────

class NotificationsRemoteDataSource {
  NotificationsRemoteDataSource(this._api);

  final ApiService _api;

  static const int _pageSize = ApiConfig.defaultPageSize;
  static const int _maxPages = 50; // safety cap; loop still breaks when next == null

  Future<List<Map<String, dynamic>>> fetchNotificationRows() async {
    final rows = <Map<String, dynamic>>[];
    for (var page = 1; page <= _maxPages; page++) {
      final body = await _api.get(ApiEndpoints.notifications, query: {
        'page_size': _pageSize,
        if (page > 1) 'page': page,
      });
      final parsed = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m);
      rows.addAll(parsed.results);
      if (parsed.next == null) break;
    }
    return rows;
  }

  List<AppNotification> mapRows(List rows, {DateTime? now}) {
    final out = <AppNotification>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final n = notificationFromJson(Map<String, dynamic>.from(row), now: now);
      if (n != null) out.add(n);
    }
    return out;
  }

  Future<void> markRead(String id) =>
      _api.post(ApiEndpoints.notificationMarkRead(id));

  Future<void> markAllRead() => _api.post(ApiEndpoints.notificationsMarkAllRead);

  Future<void> delete(String id) => _api.delete(ApiEndpoints.notification(id));
}
