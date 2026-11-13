import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/crm/domain/entities/crm_catalog.dart';

/// Waits out a burst of rebuilds (typing in the search box) before a counts
/// provider asks the server. False when the provider was rebuilt or disposed
/// meanwhile — its answer would be discarded, so the caller skips the call.
Future<bool> settledFor(Ref ref,
    [Duration delay = const Duration(milliseconds: 350)]) async {
  var live = true;
  ref.onDispose(() => live = false);
  await Future<void>.delayed(delay);
  return live;
}

/// Status GROUPS for the list screens' header (Oct 2026 list-header redesign).
///
/// Each org defines its own statuses, so a one-chip-per-status row ran to two or
/// three screens' width. The header now shows a short, fixed row of groups and
/// reveals a group's statuses only when it is picked. The vocabularies mirror
/// the backend's `crm/services/status_groups.py`, and so does what decides a
/// status's group:
///
/// * leads, CRM tasks / follow-ups — the backend-fixed `status_type`;
/// * projects, project tasks, tickets — the status's own flags (closed /
///   cancelled / resolved / on hold), which is all those modules have.
class StatusGroup {
  const StatusGroup(this.code, this.label);

  /// The backend code (`in_progress`) — what `?status_type=` and the
  /// `status-counts` response's `groups[].code` carry.
  final String code;
  final String label;
}

abstract final class StatusGroups {
  static const lead = [
    StatusGroup('new', 'New'),
    StatusGroup('in_progress', 'In progress'),
    StatusGroup('won', 'Won'),
    StatusGroup('lost', 'Lost'),
    StatusGroup('junk', 'Junk'),
  ];
  static const task = [
    StatusGroup('open', 'Open'),
    StatusGroup('in_progress', 'In progress'),
    StatusGroup('completed', 'Completed'),
    StatusGroup('cancelled', 'Cancelled'),
  ];
  static const project = [
    StatusGroup('open', 'Open'),
    StatusGroup('closed', 'Closed'),
  ];
  static const projectTask = [
    StatusGroup('open', 'Open'),
    StatusGroup('completed', 'Completed'),
    StatusGroup('cancelled', 'Cancelled'),
  ];
  static const ticket = [
    StatusGroup('open', 'Open'),
    StatusGroup('on_hold', 'On hold'),
    StatusGroup('resolved', 'Resolved'),
  ];

  /// The key a group's total is stored under in a tab-counts map, beside the
  /// per-status keys. Status keys are names or uuids, so `group:` cannot
  /// collide with one.
  static String countKey(String code) => 'group:$code';

  /// Lead and CRM-task statuses: the type the backend fixed on the status.
  static String? ofTyped(CatalogOption s) {
    final t = (s.statusType ?? '').trim().toLowerCase();
    return t.isEmpty ? null : t;
  }

  /// Projects: `is_closed` (backend `project_status_group`).
  static String ofProject(CatalogOption s) => s.isClosed ? 'closed' : 'open';

  /// Project tasks: `is_cancelled`, then `is_closed`
  /// (backend `project_task_status_group`).
  static String ofProjectTask(CatalogOption s) =>
      s.isCancelled ? 'cancelled' : (s.isClosed ? 'completed' : 'open');

  /// Tickets: `is_resolved` (carried as [CatalogOption.isClosed]), then
  /// `is_on_hold` (backend `ticket_status_group`).
  static String ofTicket(CatalogOption s) =>
      s.isClosed ? 'resolved' : (s.isOnHold ? 'on_hold' : 'open');

  /// Reads a `status-counts` response's `groups: [{code, count}]` into [out]
  /// under [countKey]. A response from before the redesign has no `groups`
  /// and adds nothing, so the header sums its statuses instead.
  static void readGroupCounts(Object? body, Map<String, int> out) {
    if (body is! Map) return;
    final groups = body['groups'];
    if (groups is! List) return;
    for (final g in groups) {
      if (g is! Map) continue;
      final code = (g['code'] ?? '').toString();
      if (code.isEmpty) continue;
      final n = g['count'];
      out[countKey(code)] =
          n is num ? n.toInt() : int.tryParse('${n ?? ''}') ?? 0;
    }
  }

  /// The status keys a header selection stands for: the statuses picked when
  /// there are any, else every status in [group] — so picking a group alone
  /// lists all of its statuses. Empty with no group means "All".
  static Set<String> effectiveKeys({
    required Set<String> picked,
    required String? group,
    required Iterable<CatalogOption> statuses,
    required String? Function(CatalogOption) groupOf,
    required String Function(CatalogOption) keyOf,
  }) {
    if (picked.isNotEmpty || group == null) return picked;
    return {
      for (final s in statuses)
        if (groupOf(s) == group) keyOf(s)
    };
  }

  /// The group the header shows open: the one holding the first picked status
  /// when a status is picked (another screen may have set it directly), else
  /// the group picked on its own.
  static String? displayedGroup({
    required Set<String> picked,
    required String? group,
    required Iterable<CatalogOption> statuses,
    required String? Function(CatalogOption) groupOf,
    required String Function(CatalogOption) keyOf,
  }) {
    for (final s in statuses) {
      if (picked.contains(keyOf(s))) return groupOf(s);
    }
    return group;
  }
}
