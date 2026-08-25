import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../../core/network/network_providers.dart';
import '../../../crm/domain/entities/crm_catalog.dart';
import '../../../crm/application/providers/customers_providers.dart';
import '../../../../data/api/user_directory.dart';
import '../../../../core/filters/filter_models.dart';
import '../filters/project_filter_codec.dart';
import '../filters/projects_filter_spec.dart';
import '../../../crm/domain/entities/lead_file.dart';
import '../../domain/entities/project.dart';
import '../../domain/repositories/projects_repository.dart';
import '../../infrastructure/data_sources/local/projects_mock_ds.dart';
import '../../infrastructure/data_sources/remote/projects_remote_ds.dart';
import '../../infrastructure/repositories/projects_api_repository.dart';
import '../../infrastructure/repositories/projects_repository_impl.dart';

/// The prototype's "today" for Operations overdue calculations (09 Jul 2026).
final DateTime kOpsToday = DateTime(2026, 7, 9);

/// A project is overdue when its end date has passed and it is neither
/// completed nor cancelled (the prototype's `isOverdueProj`).
bool isProjectOverdue(Project p) {
  // The server already decided this against the real date and the org's own
  // closed statuses. `kOpsToday` below is the prototype's frozen clock
  // (9 Jul 2026), so anything due since then read as on-time forever.
  if (p.isOverdue != null) return p.isOverdue!;
  if (p.status == 'completed' || p.status == 'cancelled') return false;
  final end = DateTime.tryParse(p.endISO);
  return end != null && end.isBefore(kOpsToday);
}

/// DI seam: mock-backed with no API base URL, remote-backed otherwise.
final projectsRepositoryProvider = Provider<ProjectsRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const ProjectsRepositoryImpl(ProjectsMockDataSource());
  }
  return ProjectsApiRepository(
    ProjectsRemoteDataSource(ref.watch(apiServiceProvider)),
  );
});

/// The org's project statuses (`operations.md` §3) — the tab strip and the
/// drawer's Status facet.
final projectStatusCatalogProvider = FutureProvider<List<CatalogOption>>(
  (ref) => ref.watch(projectsRepositoryProvider).getProjectStatuses(),
);

/// Synchronous view — empty while in flight, in mock mode and on failure, which
/// callers read as "use the built-in vocabulary".
final projectStatusOptionsProvider = Provider<List<CatalogOption>>(
  (ref) => ref.watch(projectStatusCatalogProvider).valueOrNull ?? const [],
);

/// The pill a project's status should render as — the twin of
/// `crmTaskStatusMeta`.
///
/// Shows the org's **own** status name whenever the API sent one, so a project
/// in "In Delivery" reads that rather than the built-in bucket
/// [projectStatusKey] folded it into. [statusName] is `status_name` off the
/// record; [key] is the folded value, which still decides the colour when the
/// lane is not in the catalog (still loading, or since removed).
StatusMeta projectStatusMeta({
  required String key,
  required String statusName,
  required List<CatalogOption> statuses,
}) {
  final fallback = StatusMeta$.project[key] ?? StatusMeta$.project['planning']!;
  final name = statusName.trim();
  if (name.isEmpty) return fallback;
  final needle = name.toLowerCase();
  for (final s in statuses) {
    if (s.name.trim().toLowerCase() == needle) {
      return StatusMeta(s.name, s.color ?? fallback.color);
    }
  }
  return StatusMeta(name, fallback.color);
}

/// The org's project types (§4) — the drawer's Type facet.
final projectTypeCatalogProvider = FutureProvider<List<CatalogOption>>(
  (ref) => ref.watch(projectsRepositoryProvider).getProjectTypes(),
);

final projectTypeOptionsProvider = Provider<List<CatalogOption>>(
  (ref) => ref.watch(projectTypeCatalogProvider).valueOrNull ?? const [],
);

/// Started at mount by the list screen so the drawer never snapshots a
/// half-loaded catalog.
final projectFilterCatalogsProvider = FutureProvider<void>((ref) async {
  await Future.wait([
    ref.watch(projectStatusCatalogProvider.future),
    ref.watch(projectTypeCatalogProvider.future),
    // The Customer facet's options come from here now, so the drawer must wait
    // for it too — the sheet snapshots its spec once and keeps it.
    ref.watch(customersProvider.future),
  ]);
});

/// The query key for one project fetch.
class ProjectListQuery {
  const ProjectListQuery({this.filters = const {}});

  final Map<String, dynamic> filters;

  String get signature {
    final keys = filters.keys.toList()..sort();
    return [for (final k in keys) '$k=${filters[k]}'].join('&');
  }

  @override
  bool operator ==(Object other) =>
      other is ProjectListQuery && other.signature == signature;

  @override
  int get hashCode => signature.hashCode;
}

/// Projects for one query — the server does the filtering.
final projectsScopedProvider =
    FutureProvider.family<List<Project>, ProjectListQuery>(
  (ref, q) => ref.watch(projectsRepositoryProvider).getProjects(filters: q.filters),
);

/// The server params the current drawer + My-projects state produces.
///
/// `ownership=me` is the documented scope param (§1 "Other useful params"), so
/// the My-projects toggle is resolved by the server rather than by filtering
/// `p.isMine` over a page of rows.
/// [search] and [statusTab] are the header's own two controls, which used to be
/// applied only to rows already downloaded — so neither could find a project
/// outside the loaded set.
///
/// The tab sends `status_name__in` rather than `status__in`: it holds the
/// org's status *name*, and keeping the two on different params lets the tab
/// and the drawer's Status facet intersect instead of overwriting each other.
Map<String, dynamic> projectFilterParamsFor({
  required FilterValues values,
  required ProjectFilterCodec codec,
  required bool mine,
  String search = '',
  String statusTab = 'all',
}) {
  if (!ApiConfig.apiEnabled) return const {};
  return {
    if (mine) 'ownership': 'me',
    if (search.trim().isNotEmpty) 'search': search.trim(),
    if (statusTab != 'all' && statusTab.isNotEmpty) 'status_name__in': statusTab,
    ...codec.encode(values),
  };
}

final projectFilterParamsProvider = Provider<Map<String, dynamic>>(
  (ref) => projectFilterParamsFor(
    values: ref.watch(projectFiltersProvider),
    codec: ref.watch(projectFilterCodecProvider),
    mine: ref.watch(myProjectsProvider),
    search: ref.watch(projSearchDebouncedProvider),
    statusTab: ref.watch(projTabProvider),
  ),
);

/// The search box, settled.
///
/// The raw provider updates on every keystroke and drives the instant local
/// narrowing; this one lags it so the server sees one query per pause rather
/// than one per character.
final projSearchDebouncedProvider =
    StateNotifierProvider<_DebouncedSearch, String>((ref) => _DebouncedSearch(ref));

class _DebouncedSearch extends StateNotifier<String> {
  _DebouncedSearch(Ref ref) : super('') {
    ref.listen<String>(projSearchProvider, (_, next) {
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 350), () {
        if (mounted) state = next.trim();
      });
    });
  }

  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// The tab strip's counts, from `/projects/projects/status-counts/` under the
/// same filters as the list.
///
/// Keyed by status name, plus `'all'`. Empty (mock mode, a failed call) means
/// the strip falls back to counting the rows it has — which is only right when
/// every page happens to be downloaded.
final projectStatusCountsProvider = FutureProvider<Map<String, int>>((ref) {
  // The tab itself is stripped server-side, but excluding it here keeps one
  // cached aggregate across tab switches instead of one per tab.
  final params = {...ref.watch(projectFilterParamsProvider)}
    ..remove('status_name__in');
  return ref.watch(projectsRepositoryProvider).getStatusCounts(params);
});

/// Org-wide projects — the cross-screen lookup source (ops tasks resolve their
/// project here), so it deliberately ignores the list's filters.
final projectsProvider = FutureProvider<List<Project>>(
  (ref) => ref.watch(projectsScopedProvider(const ProjectListQuery()).future),
);

/// The Projects list itself, with the drawer, the status tab scope and the
/// My-projects toggle resolved by the server where the API supports it.
final projectsFilteredProvider = FutureProvider<List<Project>>(
  (ref) => ref.watch(
    projectsScopedProvider(
      ProjectListQuery(filters: ref.watch(projectFilterParamsProvider)),
    ).future,
  ),
);

/// Translates the Projects drawer to the documented query params.
final projectFilterCodecProvider = Provider<ProjectFilterCodec>(
  (ref) => ProjectFilterCodec(
    statuses: ref.watch(projectStatusOptionsProvider),
    types: ref.watch(projectTypeOptionsProvider),
    // The drawer's Customer options are company names; this maps them to ids.
    customers: [
      for (final c in ref.watch(customersProvider).valueOrNull ?? const [])
        CatalogOption(id: c.id, name: c.company ?? c.name),
    ],
    currentUserId: UserDirectory.currentUserId,
  ),
);

/// Synchronous view of the **org-wide** list — the cross-screen lookup source
/// (the create forms and the task screens resolve a project name here), so it
/// must not carry the Projects list screen's filters.
final projectsListProvider = Provider<List<Project>>(
  (ref) => ref.watch(projectsProvider).valueOrNull ?? const [],
);

/// Synchronous view of the **filtered** fetch — only the Projects list screen.
final projectsFilteredListProvider = Provider<List<Project>>(
  (ref) => ref.watch(projectsFilteredProvider).valueOrNull ?? const [],
);

/// Every project in the org, ignoring the Projects screen's filter state.
///
/// This is what pickers, name lookups and filter facets want. Reading
/// [projectsListProvider] instead makes them inherit whatever the Projects list
/// happens to be showing — and since **My Projects defaults to on**
/// (`ownership=me`), a form's project picker came up empty for anyone who
/// manages no projects, and a task on a colleague's project could not be
/// named.
final allProjectsProvider = Provider<List<Project>>(
  (ref) => ref.watch(projectsProvider).valueOrNull ?? const [],
);

/// The signed-in user's own projects, scoped **by the server** (`ownership=me`,
/// §1 "Other useful params").
///
/// The Operations home used to take the org-wide list and filter it on
/// [Project.isMine]. That cannot work against the API: the list is read with
/// `?view=list`, whose slim projection drops `assignees` entirely, so `isMine`
/// collapses to "am I the manager" and a project you are merely assigned to is
/// invisible. The Projects list screen already avoids the same trap — this
/// gives the dashboard the same server-resolved answer.
final myProjectsListProvider = FutureProvider<List<Project>>(
  (ref) => ref.watch(
    projectsScopedProvider(
      const ProjectListQuery(filters: {'ownership': 'me'}),
    ).future,
  ),
);

/// Of my projects, the ones still live — anything not completed, cancelled or
/// archived.
///
/// Matches the KPI endpoint's own definition of an active project ("open,
/// non-archived", `admin_operations_dashboard.md` §1). Counting only the rows
/// whose status folds to exactly `active` dropped every project sitting in
/// Planning, On hold or any org status that folds elsewhere — which on a young
/// org is most of them.
final myOpenProjectsProvider = Provider<List<Project>>((ref) {
  final mine = ref.watch(myProjectsListProvider).valueOrNull ?? const [];
  return [
    for (final p in mine)
      if (p.status != 'completed' && p.status != 'cancelled') p,
  ];
});

/// Look up a single project by id (detail screen).
final projectByIdProvider = Provider.family<Project?, String>((ref, id) {
  for (final p in ref.watch(projectsListProvider)) {
    if (p.id == id) return p;
  }
  return null;
});

/// One project in its full shape — `GET /projects/projects/{id}/`.
///
/// The list is fetched with `?view=list`, whose slim rows drop the costing,
/// the nested assignees, the team, the visibility and the progress method. The
/// detail screen read only that row, which is why Visibility always said
/// "Team", Progress method always said "Task-based", and Assigned team fell
/// back to the seed name "Team Kochi".
///
/// Null while in flight, in mock mode, and on failure.
final projectDetailProvider =
    FutureProvider.autoDispose.family<Project?, String>((ref, id) {
  if (id.isEmpty) return Future.value(null);
  ref.watch(apiWriteTickProvider);
  return ref.watch(projectsRepositoryProvider).getProject(id);
});

/// The project's attachments — the Files tab.
///
/// Depends on the write tick so an upload made anywhere refreshes it.
final projectAttachmentsProvider =
    FutureProvider.autoDispose.family<List<LeadFile>, String>((ref, id) {
  if (id.isEmpty) return Future.value(const <LeadFile>[]);
  ref.watch(apiWriteTickProvider);
  return ref.watch(projectsRepositoryProvider).getProjectAttachments(id);
});

/// The fullest project available: the enriched record once it lands, the list
/// row until then. Read this on the detail screen so it paints immediately.
final projectDetailOrListProvider = Provider.autoDispose.family<Project?, String>(
  (ref, id) =>
      ref.watch(projectDetailProvider(id)).valueOrNull ??
      ref.watch(projectByIdProvider(id)),
);

// ── List UI state ──

final projTabProvider = StateProvider<String>((ref) => 'all');
final projSearchProvider = StateProvider<String>((ref) => '');
final projSearchOpenProvider = StateProvider<bool>((ref) => false);

/// "My Projects" saved-view default (on, mirroring the prototype's
/// `myProjects: true`).
final myProjectsProvider = StateProvider<bool>((ref) => true);

/// The base list before the status tab (respects the My/All view).
final projBaseProvider = Provider<List<Project>>((ref) {
  final all = ref.watch(projectsFilteredListProvider);
  // In API mode `ownership=me` already narrowed this — re-filtering on `isMine`
  // would double-apply it, and `isMine` is derived from the row's manager which
  // the slim `view=list` row collapses to a bare id.
  if (ApiConfig.apiEnabled) return all;
  final mine = ref.watch(myProjectsProvider);
  return mine ? all.where((p) => p.isMine).toList() : all;
});

/// Count for a status tab within the base list.
int projTabCount(List<Project> base, String key, {required bool mine}) {
  if (key == 'all') {
    if (!mine) return base.length;
    return base.where((p) => p.status != 'completed' && p.status != 'cancelled').length;
  }
  return base.where((p) => projectInTab(p, key)).length;
}

/// Whether a project belongs under a status tab.
///
/// The tab key is the org's own status name once `/projects/project-statuses/`
/// has loaded ("In Delivery"), and a built-in folded key ("planning") before it
/// does or in mock mode. Both are accepted so the strip keeps working through
/// the switch-over, and so a project whose status was deleted still lands
/// somewhere via its folded key rather than vanishing.
bool projectInTab(Project p, String tabKey) =>
    p.statusName.trim().toLowerCase() == tabKey.trim().toLowerCase() ||
    p.status == tabKey;

/// Projects filtered by the active tab + search query.
final visibleProjectsProvider = Provider<List<Project>>((ref) {
  final base = ref.watch(projBaseProvider);
  final tab = ref.watch(projTabProvider);
  final mine = ref.watch(myProjectsProvider);
  final q = ref.watch(projSearchProvider).trim().toLowerCase();

  Iterable<Project> out = base;
  if (tab != 'all') {
    out = out.where((p) => projectInTab(p, tab));
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
