import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/ops_task.dart';
import '../../domain/repositories/ops_tasks_repository.dart';
import '../../infrastructure/data_sources/local/ops_tasks_mock_ds.dart';
import '../../infrastructure/repositories/ops_tasks_repository_impl.dart';
import 'projects_providers.dart';

/// The prototype's `ohNow` — 09 Jul 2026, 09:41 — used for due-date deltas.
final DateTime kOpsNow = DateTime(2026, 7, 9, 9, 41);

/// A task is overdue when its end date has passed and it is neither completed
/// nor cancelled (the prototype's `isOverdueOt`).
bool isTaskOverdue(OpsTask t) {
  if (t.status == 'completed' || t.status == 'cancelled') return false;
  final end = DateTime.tryParse(t.endISO);
  return end != null && end.isBefore(kOpsToday);
}

/// Whole-day delta from now to the task's end-of-day (negative = overdue).
int taskDueDelta(OpsTask t) {
  final end = DateTime.tryParse('${t.endISO}T23:59:59');
  if (end == null) return 0;
  final ms = end.millisecondsSinceEpoch - kOpsNow.millisecondsSinceEpoch;
  return (ms / 86400000).floor();
}

/// DI seam: override in `bootstrap` to inject a real API-backed repo.
final opsTasksRepositoryProvider = Provider<OpsTasksRepository>(
  (ref) => const OpsTasksRepositoryImpl(OpsTasksMockDataSource()),
);

/// Async source of all ops tasks.
final opsTasksProvider = FutureProvider<List<OpsTask>>(
  (ref) => ref.watch(opsTasksRepositoryProvider).getOpsTasks(),
);

/// Synchronous view of the loaded ops tasks (empty until loaded).
final opsTasksListProvider = Provider<List<OpsTask>>(
  (ref) => ref.watch(opsTasksProvider).valueOrNull ?? const [],
);

/// Look up a single ops task by id (detail screen).
final opsTaskByIdProvider = Provider.family<OpsTask?, String>((ref, id) {
  for (final t in ref.watch(opsTasksListProvider)) {
    if (t.id == id) return t;
  }
  return null;
});

// ── List UI state ──

final otTabProvider = StateProvider<String>((ref) => 'all');
final otSearchProvider = StateProvider<String>((ref) => '');
final otSearchOpenProvider = StateProvider<bool>((ref) => false);

/// "My Tasks" saved-view default (on, mirroring `myTasksF: true`).
final myTasksFProvider = StateProvider<bool>((ref) => true);

/// Ops-home "My Tasks" sort segment — 'priority' (default) or 'due'.
final opsSortProvider = StateProvider<String>((ref) => 'priority');

/// Base list before the status tab (respects the My/All view).
final otBaseProvider = Provider<List<OpsTask>>((ref) {
  final all = ref.watch(opsTasksListProvider);
  final mine = ref.watch(myTasksFProvider);
  return mine ? all.where((t) => t.isMine).toList() : all;
});

/// Count for a status tab within the base list.
int otTabCount(List<OpsTask> base, String key, {required bool mine}) {
  if (key == 'all') {
    if (!mine) return base.length;
    return base.where((t) => t.status != 'completed' && t.status != 'cancelled').length;
  }
  return base.where((t) => t.status == key).length;
}

/// Ops tasks filtered by the active tab + search query.
final visibleOpsTasksProvider = Provider<List<OpsTask>>((ref) {
  final base = ref.watch(otBaseProvider);
  final tab = ref.watch(otTabProvider);
  final mine = ref.watch(myTasksFProvider);
  final q = ref.watch(otSearchProvider).trim().toLowerCase();
  final projects = ref.watch(projectsListProvider);
  String projName(String id) => projects.where((p) => p.id == id).map((p) => p.name).firstOrNull ?? '';

  Iterable<OpsTask> out = base;
  if (tab != 'all') {
    out = out.where((t) => t.status == tab);
  } else if (mine) {
    out = out.where((t) => t.status != 'completed' && t.status != 'cancelled');
  }
  if (q.isNotEmpty) {
    out = out.where((t) =>
        t.subject.toLowerCase().contains(q) ||
        t.id.toLowerCase().contains(q) ||
        projName(t.projId).toLowerCase().contains(q) ||
        t.group.toLowerCase().contains(q));
  }
  return out.toList();
});

/// Unresolved dependencies for a task (waiting-on tasks not yet done).
List<OpsTask> unresolvedDeps(OpsTask t, List<OpsTask> all) {
  return t.waitingOn
      .map((id) => all.where((x) => x.id == id).firstOrNull)
      .whereType<OpsTask>()
      .where((x) => x.status != 'completed' && x.status != 'cancelled')
      .toList();
}
