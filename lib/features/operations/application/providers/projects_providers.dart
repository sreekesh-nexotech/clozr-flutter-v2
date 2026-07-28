import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/project.dart';
import '../../domain/repositories/projects_repository.dart';
import '../../infrastructure/data_sources/local/projects_mock_ds.dart';
import '../../infrastructure/repositories/projects_repository_impl.dart';

/// The prototype's "today" for Operations overdue calculations (09 Jul 2026).
final DateTime kOpsToday = DateTime(2026, 7, 9);

/// A project is overdue when its end date has passed and it is neither
/// completed nor cancelled (the prototype's `isOverdueProj`).
bool isProjectOverdue(Project p) {
  if (p.status == 'completed' || p.status == 'cancelled') return false;
  final end = DateTime.tryParse(p.endISO);
  return end != null && end.isBefore(kOpsToday);
}

/// DI seam: override in `bootstrap` to inject a real API-backed repo.
final projectsRepositoryProvider = Provider<ProjectsRepository>(
  (ref) => const ProjectsRepositoryImpl(ProjectsMockDataSource()),
);

/// Async source of all projects.
final projectsProvider = FutureProvider<List<Project>>(
  (ref) => ref.watch(projectsRepositoryProvider).getProjects(),
);

/// Synchronous view of the loaded projects (empty until loaded).
final projectsListProvider = Provider<List<Project>>(
  (ref) => ref.watch(projectsProvider).valueOrNull ?? const [],
);

/// Look up a single project by id (detail screen).
final projectByIdProvider = Provider.family<Project?, String>((ref, id) {
  for (final p in ref.watch(projectsListProvider)) {
    if (p.id == id) return p;
  }
  return null;
});

// ── List UI state ──

final projTabProvider = StateProvider<String>((ref) => 'all');
final projSearchProvider = StateProvider<String>((ref) => '');
final projSearchOpenProvider = StateProvider<bool>((ref) => false);

/// "My Projects" saved-view default (on, mirroring the prototype's
/// `myProjects: true`).
final myProjectsProvider = StateProvider<bool>((ref) => true);

/// The base list before the status tab (respects the My/All view).
final projBaseProvider = Provider<List<Project>>((ref) {
  final all = ref.watch(projectsListProvider);
  final mine = ref.watch(myProjectsProvider);
  return mine ? all.where((p) => p.isMine).toList() : all;
});

/// Count for a status tab within the base list.
int projTabCount(List<Project> base, String key, {required bool mine}) {
  if (key == 'all') {
    if (!mine) return base.length;
    return base.where((p) => p.status != 'completed' && p.status != 'cancelled').length;
  }
  return base.where((p) => p.status == key).length;
}

/// Projects filtered by the active tab + search query.
final visibleProjectsProvider = Provider<List<Project>>((ref) {
  final base = ref.watch(projBaseProvider);
  final tab = ref.watch(projTabProvider);
  final mine = ref.watch(myProjectsProvider);
  final q = ref.watch(projSearchProvider).trim().toLowerCase();

  Iterable<Project> out = base;
  if (tab != 'all') {
    out = out.where((p) => p.status == tab);
  } else if (mine) {
    out = out.where((p) => p.status != 'completed' && p.status != 'cancelled');
  }
  if (q.isNotEmpty) {
    out = out.where((p) =>
        p.name.toLowerCase().contains(q) ||
        p.id.toLowerCase().contains(q) ||
        (p.company ?? '').toLowerCase().contains(q) ||
        p.type.toLowerCase().contains(q));
  }
  return out.toList();
});
