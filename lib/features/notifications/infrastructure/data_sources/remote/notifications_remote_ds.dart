import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../../app/theme/app_colors.dart';
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

/// Per-category icon/colour combos, copied from the mock seed so remote rows
/// look identical to the design.
({IconData icon, Color color, Color bg}) notificationIconFor(
  String category, {
  bool urgent = false,
  String type = '',
}) {
  switch (category) {
    case 'leads':
      return (
        icon: PhosphorIconsFill.userPlus,
        color: AppColors.blueBright,
        bg: AppColors.tintBlue,
      );
    case 'payments':
      return urgent
          ? (icon: PhosphorIconsFill.warningCircle, color: AppColors.error, bg: AppColors.tintRed)
          : (icon: PhosphorIconsFill.currencyInr, color: AppColors.success, bg: AppColors.tintGreen);
    case 'tasks':
      return urgent
          ? (icon: PhosphorIconsFill.warning, color: AppColors.warningDeep, bg: AppColors.tintAmber)
          : (icon: PhosphorIconsFill.listChecks, color: AppColors.blueBright, bg: AppColors.tintBlue);
    case 'ops':
      return urgent
          ? (icon: PhosphorIconsFill.kanban, color: AppColors.error, bg: AppColors.tintRed)
          : (icon: PhosphorIconsFill.briefcase, color: AppColors.blueBright, bg: AppColors.tintBlue);
    case 'help':
      return urgent
          ? (icon: PhosphorIconsFill.ticket, color: AppColors.error, bg: AppColors.tintRed)
          : (icon: PhosphorIconsFill.chatCircleDots, color: AppColors.blueBright, bg: AppColors.tintBlue);
    case 'training':
      return (
        icon: PhosphorIconsFill.graduationCap,
        color: AppColors.blueBright,
        bg: AppColors.tintBlue,
      );
    default: // system
      if (type.toLowerCase().contains('user')) {
        return (icon: PhosphorIconsFill.userCirclePlus, color: AppColors.textLabelAlt, bg: AppColors.tintGrey);
      }
      return urgent
          ? (icon: PhosphorIconsFill.plug, color: AppColors.pending, bg: AppColors.tintPurple)
          : (icon: PhosphorIconsFill.downloadSimple, color: AppColors.textLabelAlt, bg: AppColors.tintGrey);
  }
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

/// The row payload has no source-object ids, so only list-level deep links
/// can be derived from the type. Everything else is 'none'.
(String, String?) _targetFor(String type) {
  final t = type.toLowerCase();
  if (t.startsWith('lms')) return ('list', 'lmsMy');
  if (t.startsWith('payment') ||
      t.startsWith('dunning') ||
      t.startsWith('mandate') ||
      t.startsWith('license')) {
    return ('list', 'billing');
  }
  return ('none', null);
}

/// One `/crm/notifications/` row → [AppNotification]; null when malformed.
AppNotification? notificationFromJson(Map<String, dynamic> row, {DateTime? now}) {
  final id = (row['crm_notification_id'] ?? row['pk'] ?? row['id'])?.toString();
  if (id == null || id.isEmpty) return null;

  final type = _str(row['type']) ?? '';
  final category = notificationCategoryToUi(_str(row['category']), type);

  // No urgency flag exists on the serializer today — read defensively anyway.
  final urgent = row['urgent'] == true ||
      row['is_urgent'] == true ||
      _str(row['priority'])?.toLowerCase() == 'high';

  final text = _str(row['notification_text']);
  final message = _str(row['message']);
  final body = message == null ? '' : _stripHtml(message);
  final title = text ?? (body.isNotEmpty ? body : _humanizeType(type));

  // The live field is `read`; `is_read` kept as a defensive alias. When both
  // are absent, fall back to the computed `status` string.
  final readFlag = row['is_read'] ?? row['read'];
  final unread =
      readFlag is bool ? !readFlag : _str(row['status'])?.toLowerCase() == 'unread';

  final created = parseApiDate(row['created_at']);
  final look = notificationIconFor(category, urgent: urgent, type: type);
  final target = _targetFor(type);

  return AppNotification(
    id: id,
    category: category,
    urgent: urgent,
    day: notificationDayBucket(created, now: now),
    icon: look.icon,
    iconColor: look.color,
    iconBg: look.bg,
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
