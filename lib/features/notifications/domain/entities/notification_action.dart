import 'dart:convert';

/// Where tapping a notification should go — the server's `action` object on
/// an inbox row, its detail, and (flattened to strings) an FCM push.
///
/// ```json
/// "action": {"resource": "crm_task", "id": "<uuid>",
///            "api_url": "/api/v1/crm/tasks/<uuid>/",
///            "context": {"note_id": "<uuid>", "is_followup": false}}
/// ```
///
/// A record action carries the record's [id]; a page action (`billing`,
/// `goals_rewards`, …) has none. The screen for each [resource] is decided in
/// the application layer (`routeForNotificationAction`).
class NotificationAction {
  const NotificationAction({
    required this.resource,
    this.id,
    this.context = const {},
  });

  final String resource;

  /// The record's id; null for a page action.
  final String? id;

  /// Optional extras (`note_id`, `is_followup`, `project_id`, …).
  final Map<String, dynamic> context;

  /// The resources the app has a screen for. Anything else — `call_log`,
  /// `account_security`, `org_backup`, or one added server-side later — is
  /// treated like a null action: mark read and stay put.
  static const openableResources = {
    'lead',
    'customer',
    'crm_task',
    'issue',
    'project',
    'project_task',
    'quotation',
    'lms_enrollment',
    'lms_course',
    'approval',
    'user',
    'billing',
    'goals_rewards',
  };

  /// `context.is_followup` — a `crm_task` that is a follow-up.
  bool get isFollowup {
    final v = context['is_followup'];
    return v == true || '$v'.toLowerCase() == 'true';
  }

  /// The `action` object of an inbox row; null when absent or malformed.
  static NotificationAction? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final resource = _nonEmpty(raw['resource']);
    if (resource == null) return null;
    final ctx = raw['context'];
    return NotificationAction(
      resource: resource,
      id: _nonEmpty(raw['id']),
      context: ctx is Map ? Map<String, dynamic>.from(ctx) : const {},
    );
  }

  /// The action keys of an FCM data payload. Every value is a string there:
  /// absent ones are `""`, and `context` is JSON-encoded. Null when the push
  /// carries no action.
  static NotificationAction? fromPushData(Map<String, dynamic> data) {
    final resource = _nonEmpty(data['resource']);
    if (resource == null) return null;
    var ctx = const <String, dynamic>{};
    final rawCtx = data['context'];
    if (rawCtx is Map) {
      ctx = Map<String, dynamic>.from(rawCtx);
    } else if (rawCtx is String && rawCtx.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawCtx);
        if (decoded is Map) ctx = Map<String, dynamic>.from(decoded);
      } on FormatException {
        // A bad context still leaves the record itself openable.
      }
    }
    return NotificationAction(
      resource: resource,
      id: _nonEmpty(data['id']),
      context: ctx,
    );
  }

  static String? _nonEmpty(Object? v) {
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty || s == 'null' ? null : s;
  }
}
