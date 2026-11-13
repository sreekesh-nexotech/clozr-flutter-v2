import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/network_providers.dart';
import '../../crm/application/providers/crm_tasks_providers.dart';
import '../../crm/application/providers/customers_providers.dart'
    show customersScopedProvider;
import '../../crm/application/providers/followups_providers.dart'
    show followupsProvider, followupsQueriedProvider, followupsScopedProvider;
import '../domain/entities/app_notification.dart';
import '../infrastructure/data_sources/remote/notifications_remote_ds.dart';
import 'notification_links.dart';
import 'providers/notifications_providers.dart';

/// Opens what a notification is about. Shared by the inbox row, the in-app
/// banner and a tap on a system (push) notification, so all three land on
/// the same screen for the same event.
///
/// Takes the container and router rather than a `BuildContext`: a push tap
/// arrives with no widget in hand.
Future<void> openNotificationTarget(
    ProviderContainer container, GoRouter router, AppNotification n) async {
  // The server's `action` names the record: it wins over everything below.
  // An action with no mobile screen (`call_log`, an unknown resource) opens
  // nothing — the tap has already marked the row read.
  final action = n.action;
  if (action != null) {
    final route = routeForNotificationAction(action);
    if (route == null) return;
    _refreshListFor(container, action);
    await router.push(route);
    return;
  }

  // Rows from before `action` existed: recover the target from the text.
  final type = n.type.toLowerCase();
  if (n.targetKind == 'list' &&
      n.targetId == 'tasks' &&
      type.startsWith('task')) {
    return _openTask(container, router, n);
  }
  if (n.targetKind == 'list' &&
      n.targetId == 'followups' &&
      type.startsWith('followup')) {
    return _openTask(container, router, n, followupFirst: true);
  }
  if (n.targetKind == 'list') {
    final link = notificationLinkFor(n.type, n.title);
    if (link != null) {
      return _openLinked(container, router, link, listRouteFor(n.targetId));
    }
  }
  final route = switch (n.targetKind) {
    'lead' => '${Routes.leadDetail}?id=${n.targetId}',
    'payment' => '${Routes.paymentDetail}?id=${n.targetId}',
    'followup' => '${Routes.followupDetail}?id=${n.targetId}',
    'opstask' => '${Routes.opsTaskDetail}?id=${n.targetId}',
    'ticket' => '${Routes.ticketDetail}?id=${n.targetId}',
    'quote' => '${Routes.quoteDetail}?id=${n.targetId}',
    'project' => '${Routes.projectDetail}?id=${n.targetId}',
    'list' => listRouteFor(n.targetId),
    _ => null,
  };
  if (route != null) await router.push(route);
}

/// Marks [n] read and opens it — what a tap on the banner or on a system
/// notification does. The inbox row does the same two steps itself.
Future<void> openNotification(
    ProviderContainer container, GoRouter router, AppNotification n) {
  // A push sent with in-app notifications off has no inbox row to mark.
  if (n.hasInboxRow) {
    container.read(notificationsProvider.notifier).markRead(n.id);
  }
  return openNotificationTarget(container, router, n);
}

/// The mobile screen for a server `action`, or null when there is none.
///
/// Mirrors the web routes in notification-tap-action-integration.md:
/// record actions open the record's detail screen by its UUID; page actions
/// open the page. `account_security` / `org_backup` go to the web Settings
/// page, which the app does not have, and `call_log` has no screen anywhere.
String? routeForNotificationAction(NotificationAction a) {
  final id = a.id;
  String withId(String route, [String param = 'id']) =>
      '$route?$param=${Uri.encodeQueryComponent(id!)}';
  if (id == null) {
    return switch (a.resource) {
      'billing' => Routes.billing,
      'goals_rewards' => Routes.rewards,
      _ => null,
    };
  }
  return switch (a.resource) {
    'lead' => withId(Routes.leadDetail),
    'customer' => withId(Routes.customerDetail),
    'crm_task' =>
      withId(a.isFollowup ? Routes.followupDetail : Routes.taskDetail),
    'issue' => withId(Routes.ticketDetail),
    'project' => withId(Routes.projectDetail),
    'project_task' => withId(Routes.opsTaskDetail),
    'quotation' => withId(Routes.quoteDetail),
    'lms_enrollment' => withId(Routes.lmsPlayer, 'enrollment'),
    'lms_course' => withId(Routes.lmsCourseDetail),
    'approval' => withId(Routes.approvalDetail),
    'user' => withId(Routes.memberDetail),
    _ => null,
  };
}

/// Task, follow-up and customer detail screens read their record out of the
/// loaded list, which may predate the record the notification is about
/// (a task created a minute ago). Refetch it so the screen can find it.
void _refreshListFor(ProviderContainer container, NotificationAction a) {
  switch (a.resource) {
    case 'crm_task':
      container.invalidate(crmTasksProvider);
      container.invalidate(followupsScopedProvider);
      container.invalidate(followupsProvider);
      container.invalidate(followupsQueriedProvider);
    case 'customer':
      container.invalidate(customersScopedProvider);
  }
}

/// `GET /crm/notifications/<id>/` → the row, or null when it is gone or
/// unreadable. A push carries only the id; this is how it becomes a row.
Future<AppNotification?> fetchNotificationById(
    ProviderContainer container, String id) async {
  if (id.isEmpty) return null;
  try {
    final body = await container
        .read(apiServiceProvider)
        .get(ApiEndpoints.notification(id), quiet: true);
    if (body is! Map) return null;
    return notificationFromJson(Map<String, dynamic>.from(body));
  } on Object {
    return null;
  }
}

/// A task / follow-up notification names its record only in the text
/// (`You have been assigned to task: "Send quote".`) — the API sends no id —
/// so the record is looked up by that title and opened; the list otherwise.
///
/// Follow-ups are Task rows too and their `TaskAssigned` reads the same, so
/// both kinds are searched — follow-ups first for a `FollowUp…` event.
Future<void> _openTask(
    ProviderContainer container, GoRouter router, AppNotification n,
    {bool followupFirst = false}) async {
  final m = RegExp(r'"([^"]+)"').firstMatch('${n.title} ${n.body}');
  final title = m?.group(1)?.trim() ?? '';
  // The lists may predate the record this notification is about.
  container.invalidate(crmTasksProvider);
  container.invalidate(followupsScopedProvider);
  container.invalidate(followupsProvider);
  container.invalidate(followupsQueriedProvider);
  Future<String?> find(bool followup) async {
    try {
      final body = await container.read(apiServiceProvider).get(
          ApiEndpoints.crmTasks,
          query: {'search': title, 'is_followup': '$followup', 'page_size': 20},
          quiet: true);
      final rows = body is Map && body['results'] is List
          ? body['results'] as List
          : const [];
      for (final r in rows) {
        if (r is Map && '${r['title'] ?? ''}'.trim() == title) {
          return '${r['task_id'] ?? r['id']}';
        }
      }
    } on Object {
      // Fall back to the list.
    }
    return null;
  }

  String? route;
  if (title.isNotEmpty) {
    for (final followup
        in followupFirst ? const [true, false] : const [false, true]) {
      final id = await find(followup);
      if (id != null) {
        route = followup
            ? '${Routes.followupDetail}?id=$id'
            : '${Routes.taskDetail}?id=$id';
        break;
      }
    }
  }
  await router.push(route ?? (followupFirst ? Routes.followups : Routes.tasks));
}

/// Opens the record a lead / quote / mention notification names (see
/// [notificationLinkFor]); [fallback] — the module list — when the lookup
/// finds nothing.
Future<void> _openLinked(ProviderContainer container, GoRouter router,
    NotificationLink link, String fallback) async {
  final api = container.read(apiServiceProvider);
  String? route;
  try {
    switch (link) {
      case TicketByReference(:final reference):
        // Only a Helpdesk user can search the list; anyone else falls back
        // to the Tickets entry, which then explains the missing module.
        final body = await api.get(ApiEndpoints.issues,
            query: {'reference': reference, 'page_size': 5}, quiet: true);
        final rows = body is Map && body['results'] is List
            ? body['results'] as List
            : const [];
        for (final r in rows) {
          if (r is Map &&
              '${r['reference'] ?? ''}'.toUpperCase() ==
                  reference.toUpperCase()) {
            route = '${Routes.ticketDetail}?id=${r['issue_id'] ?? r['id']}';
            break;
          }
        }
      case QuoteByNumber(:final number):
        route = '${Routes.quoteDetail}?id=${Uri.encodeQueryComponent(number)}';
      case LeadByName(:final name):
        final body = await api.get(ApiEndpoints.leads,
            query: {'search': name, 'page_size': 20}, quiet: true);
        final rows = body is Map && body['results'] is List
            ? body['results'] as List
            : const [];
        for (final r in rows) {
          if (r is Map &&
              '${r['lead_name'] ?? r['name'] ?? ''}'.trim().toLowerCase() ==
                  name.toLowerCase()) {
            route = '${Routes.leadDetail}?id=${r['lead_id'] ?? r['id']}';
            break;
          }
        }
      case OpsTaskByTitle(:final title):
        final body = await api.get(ApiEndpoints.projectTasks,
            query: {'search': title, 'page_size': 20}, quiet: true);
        final rows = body is Map && body['results'] is List
            ? body['results'] as List
            : const [];
        for (final r in rows) {
          if (r is Map &&
              '${r['subject'] ?? ''}'.trim().toLowerCase() ==
                  title.toLowerCase()) {
            route = '${Routes.opsTaskDetail}?id=${r['task_id'] ?? r['id']}';
            break;
          }
        }
      case ProjectByName(:final name):
        final body = await api.get(ApiEndpoints.projects,
            query: {'search': name, 'page_size': 20}, quiet: true);
        final rows = body is Map && body['results'] is List
            ? body['results'] as List
            : const [];
        for (final r in rows) {
          if (r is Map &&
              '${r['project_name'] ?? ''}'.trim().toLowerCase() ==
                  name.toLowerCase()) {
            route = '${Routes.projectDetail}?id=${r['project_id'] ?? r['id']}';
            break;
          }
        }
      case NoteByContent(:final content):
        final body = await api.get(ApiEndpoints.notes,
            query: {'page_size': 100}, quiet: true);
        final rows = body is Map && body['results'] is List
            ? body['results'] as List
            : const [];
        for (final r in rows) {
          if (r is! Map ||
              !noteMatchesMention('${r['content'] ?? ''}', content)) continue;
          final src = noteSourceOf(Map<String, dynamic>.from(r));
          route = switch (src?.$1) {
            'lead' => '${Routes.leadDetail}?id=${src!.$2}',
            'customer' => '${Routes.customerDetail}?id=${src!.$2}',
            'quotation' || 'quote' => '${Routes.quoteDetail}?id=${src!.$2}',
            'task' => '${Routes.taskDetail}?id=${src!.$2}',
            'issue' => '${Routes.ticketDetail}?id=${src!.$2}',
            _ => null,
          };
          if (route != null) break;
        }
    }
  } on Object {
    // Fall back to the list.
  }
  await router.push(route ?? fallback);
}

/// A notification's module list — where a row without an `action` (sent
/// before the API carried one) opens when its text names no record.
String listRouteFor(String? id) => switch (id) {
      'payments' => Routes.payments,
      'lmsMy' => Routes.lmsMy,
      'rewards' => Routes.rewards,
      'billing' => Routes.billing,
      'leads' || 'mention' => Routes.leads,
      'followups' => Routes.followups,
      'tasks' => Routes.tasks,
      'quotes' => Routes.quotes,
      'opsTasks' => Routes.opsTasks,
      'projects' => Routes.opsProjects,
      'tickets' => Routes.tickets,
      'members' => Routes.members,
      'approvalsPending' => Routes.approvals,
      'approvalsMine' => '${Routes.approvals}?tab=mine',
      'approvalsDueDate' => '${Routes.approvals}?kind=due_date',
      _ => Routes.home,
    };
