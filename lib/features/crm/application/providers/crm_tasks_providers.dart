import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/crm_task.dart';
import '../../domain/repositories/crm_tasks_repository.dart';
import '../../infrastructure/data_sources/local/crm_tasks_mock_ds.dart';
import '../../infrastructure/repositories/crm_tasks_repository_impl.dart';

/// DI seam: override in `bootstrap` to inject a real API-backed repo.
final crmTasksRepositoryProvider = Provider<CrmTasksRepository>(
  (ref) => const CrmTasksRepositoryImpl(CrmTasksMockDataSource()),
);

/// Async source of all CRM tasks.
final crmTasksProvider = FutureProvider<List<CrmTask>>(
  (ref) => ref.watch(crmTasksRepositoryProvider).getTasks(),
);

/// Look up a single task by id (used by the detail screen).
final crmTaskByIdProvider = Provider.family<CrmTask?, String>((ref, id) {
  final list = ref.watch(crmTasksProvider).valueOrNull;
  if (list == null) return null;
  for (final t in list) {
    if (t.id == id) return t;
  }
  return null;
});

// ── List UI state ──

/// Active tab on the Tasks list (all / mine / overdue / status keys).
final crmTaskTabProvider = StateProvider<String>((ref) => 'all');

/// Search query on the Tasks list.
final crmTaskSearchProvider = StateProvider<String>((ref) => '');

/// Whether the search field is expanded.
final crmTaskSearchOpenProvider = StateProvider<bool>((ref) => false);

/// Tasks filtered by the active tab + search query.
final visibleCrmTasksProvider = Provider<List<CrmTask>>((ref) {
  final all = ref.watch(crmTasksProvider).valueOrNull ?? const [];
  final tab = ref.watch(crmTaskTabProvider);
  final q = ref.watch(crmTaskSearchProvider).trim().toLowerCase();

  Iterable<CrmTask> out = all;
  if (tab == 'mine') {
    out = out.where((t) => t.isMine);
  } else if (tab == 'overdue') {
    out = out.where((t) => t.isOverdue);
  } else if (tab != 'all') {
    out = out.where((t) => t.status == tab);
  }
  if (q.isNotEmpty) {
    out = out.where((t) =>
        t.title.toLowerCase().contains(q) || t.id.toLowerCase().contains(q));
  }
  return out.toList();
});

/// Count of tasks for a given tab key.
int crmTaskTabCount(List<CrmTask> all, String key) {
  switch (key) {
    case 'all':
      return all.length;
    case 'mine':
      return all.where((t) => t.isMine).length;
    case 'overdue':
      return all.where((t) => t.isOverdue).length;
    default:
      return all.where((t) => t.status == key).length;
  }
}
