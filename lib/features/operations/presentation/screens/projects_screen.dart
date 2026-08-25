import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/filter_sheet.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../crm/application/providers/saved_filters_providers.dart';
import '../../../crm/presentation/components/saved_chip_row.dart' as chips;
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../../../core/config/api_config.dart';
import '../../application/filters/projects_filter_spec.dart';
import '../../application/providers/projects_providers.dart';
import '../../domain/entities/project.dart';
import '../components/ops_widgets.dart';
import '../components/project_card.dart';

/// Projects list — status tabs + a "My Projects" saved-view chip + saved-view
/// bookmark row over a scrolling list of project cards. Wired to the spec-driven
/// filter engine (drawer → applied provider → matcher → badge → saved views),
/// following the Leads reference.
class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(projSearchProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Contextual add: the bottom-nav `+` opens the create-project form here (#14).
    registerAdd(
      ref,
      AddAction(label: 'New project', run: (ctx) => ctx.push(Routes.createProject)),
    );

    // The **filtered** fetch: this is what the list renders, so its loading and
    // error states are the ones the screen must show. Watching the unfiltered
    // `projectsProvider` here meant a filter change re-queried invisibly and the
    // old rows stayed on screen until it landed.
    final projectsAsync = ref.watch(projectsFilteredProvider);
    final base = ref.watch(projBaseProvider);
    final tab = ref.watch(projTabProvider);
    final mine = ref.watch(myProjectsProvider);
    // Watched purely to start the facet fetches now, at mount. Nothing else here
    // reads them, so without this the drawer would snapshot them unloaded and
    // fall back to the built-in vocabularies.
    ref.watch(projectStatusOptionsProvider);
    ref.watch(projectTypeOptionsProvider);
    final searchOpen = ref.watch(projSearchOpenProvider);
    final query = ref.watch(projSearchProvider);
    final filters = ref.watch(projectFiltersProvider);
    final filterCount = filters.activeCount;

    // The org's own statuses drive the tab strip — names and order straight from
    // `/projects/project-statuses/` (ordered by `position`). Empty (still
    // loading, failed fetch, mock mode) falls back to the built-in vocabulary,
    // the same "empty is no opinion" contract used everywhere else.
    final statusCatalog = ref.watch(projectStatusOptionsProvider);
    final counts = ref.watch(projectStatusCountsProvider).valueOrNull ?? const <String, int>{};
    final tabDefs = <(String, String)>[
      ('all', 'All'),
      if (statusCatalog.isEmpty)
        for (final k in StatusMeta$.project.keys) (k, StatusMeta$.project[k]!.label)
      else
        for (final s in statusCatalog) (s.name, s.name),
    ];

    return Column(
      children: [
        ListHeader(
          children: [
            const AppHeaderBar(),
            SizedBox(height: 14.h),
            const HeaderHairline(),
            SizedBox(height: 14.h),
            ScreenTitleRow(
              title: 'Projects',
              hasSearchQuery: query.isNotEmpty,
              filterCount: filterCount,
              onSearch: () => ref.read(projSearchOpenProvider.notifier).state = !searchOpen,
              onFilter: _openFilters,
            ),
            if (searchOpen) ...[
              SizedBox(height: 12.h),
              SearchField(
                controller: _searchCtrl,
                hint: 'Search projects…',
                onChanged: (v) => ref.read(projSearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(projSearchProvider.notifier).state = '';
                  ref.read(projSearchOpenProvider.notifier).state = false;
                },
              ),
            ],
            SizedBox(height: 12.h),
            SizedBox(
              height: 40.h,
              child: TabChipRow(
                children: [
                  for (final (k, label) in tabDefs)
                    TabChip(
                      // The server's aggregate when it answered, else the rows
                      // on hand — which only counts what has been downloaded.
                      label: '$label (${counts[k] ?? projTabCount(base, k, mine: mine)})',
                      active: tab == k,
                      onTap: () => ref.read(projTabProvider.notifier).state = k,
                    ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            _savedViewRow(mine, filterCount),
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: AsyncStateView<List<Project>>(
            value: projectsAsync,
            onRetry: () => ref.invalidate(projectsScopedProvider),
            data: (_) {
              final tabVisible = ref.watch(visibleProjectsProvider);
              final visible = filters.isEmpty
                  ? tabVisible
                  : tabVisible
                      .where((p) => projectMatchesFilters(p, filters,
                          serverApplied: ApiConfig.apiEnabled))
                      .toList();
              return visible.isEmpty
                  ? ListView(
                      children: const [
                        EmptyState(
                          icon: PhosphorIconsRegular.briefcase,
                          title: 'No projects found',
                          body: 'Try a different status, clear filters, or turn off "My Projects" to see the whole portfolio.',
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => SizedBox(height: 12.h),
                      itemBuilder: (context, i) {
                        final p = visible[i];
                        return ProjectCard(
                          project: p,
                          onTap: () => context.push('${Routes.projectDetail}?id=${p.id}'),
                        );
                      },
                    );
            },
          ),
        ),
      ],
    );
  }

  // ── Filter drawer ──
  /// Applies a filter set to the list.
  ///
  /// The query it is about to watch is dropped first, so re-applying a
  /// combination fetched earlier really re-queries rather than serving the list
  /// as it looked then.
  void _applyFilters(FilterValues values) {
    // Every input the query key is built from, or the invalidation targets a
    // different key than the one the list is about to watch and re-applying a
    // combination fetched earlier would serve the cached result.
    final params = projectFilterParamsFor(
      values: values,
      codec: ref.read(projectFilterCodecProvider),
      mine: ref.read(myProjectsProvider),
      search: ref.read(projSearchDebouncedProvider),
      statusTab: ref.read(projTabProvider),
    );
    ref.invalidate(projectsScopedProvider(ProjectListQuery(filters: params)));
    ref.read(projectFiltersProvider.notifier).state = values;
  }

  Future<void> _openFilters() async {
    // The sheet takes its spec once and keeps it, so the facets must be settled
    // before it opens. Normally already resolved — the fetches start at mount.
    await ref.read(projectFilterCatalogsProvider.future);
    if (!mounted) return;
    final spec = ref.read(projectsFilterSpecProvider);
    final current = ref.read(projectFiltersProvider);
    final base = ref.read(projBaseProvider);
    final activeView = ref.read(projectSavedFiltersProvider).active;

    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: current,
      previewCount: (draft) => base.where((p) => projectMatchesFilters(p, draft)).length,
      activeViewName: activeView?.name,
      onSaveView: _saveView,
    );
    if (result == null) return;

    _applyFilters(result);
    // A manual Apply deactivates the active saved view unless the draft still
    // means the same thing. Compared as encoded definitions, since that is what
    // the view actually stores.
    final active = ref.read(projectSavedFiltersProvider).active;
    if (active != null) {
      final encoded = ref.read(projectFilterCodecProvider).encode(result);
      if (!sameFilterDefinition(encoded, active.definition)) {
        ref.read(projectSavedFiltersProvider.notifier).deactivate();
      }
    }
    ref.read(toastProvider.notifier).show('Filters applied');
  }

  /// Persists the drawer draft as a saved filter on `/crm/saved-filters/`
  /// (module `project`).
  ///
  /// The API stores the backend's own param dict, so the draft is encoded
  /// before it is sent; rejections (duplicate name, the per-module limit, an
  /// unknown filter key) come back as user-safe text and are shown as-is.
  Future<void> _saveView(String name, FilterValues draft) async {
    final definition = ref.read(projectFilterCodecProvider).encode(draft);
    final error =
        await ref.read(projectSavedFiltersProvider.notifier).save(name, definition);
    if (!mounted) return;
    ref.read(toastProvider.notifier).show(error ?? 'View "$name" saved');
  }

  // ── Saved-view row: My Projects toggle + saved bookmark chips + Clear ──
  Widget _savedViewRow(bool mine, int filterCount) {
    final saved = ref.watch(projectSavedFiltersProvider);
    return SizedBox(
      height: 34.h,
      child: Row(
        children: [
          OpsSavedChip(
            label: 'My Projects',
            active: mine,
            // `ownership=me` is a server scope, so flipping it changes the
            // query key rather than re-filtering rows already on screen.
            onTap: () {
              ref.read(myProjectsProvider.notifier).state = !mine;
              _applyFilters(ref.read(projectFiltersProvider));
            },
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: chips.SavedChipRow(
              views: [for (final f in saved.filters) chips.SavedView(f.id, f.name)],
              active: {if (saved.activeId != null) saved.activeId!},
              showClearAlways: filterCount > 0,
              onToggle: _toggleView,
              onClear: _clearFilters,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleView(String id) async {
    final saved = ref.read(projectSavedFiltersProvider);
    if (saved.activeId == id) {
      // Tapping the active view deactivates it and clears the applied filters.
      ref.read(projectSavedFiltersProvider.notifier).deactivate();
      _applyFilters(FilterValues());
      return;
    }
    final view = saved.filters.firstWhere((f) => f.id == id);
    // A filter the server marked invalid fails inert by contract — never run
    // it, say why instead.
    if (!view.isValid) {
      ref.read(toastProvider.notifier).show(
            'View "${view.name}" refers to a field that no longer exists.',
          );
      return;
    }
    // A chip is tappable without ever opening the drawer, so wait for the same
    // catalogs here: decoding maps stored status/type/customer ids back to
    // drawer options, and a half-loaded catalog would drop them.
    await ref.read(projectFilterCatalogsProvider.future);
    if (!mounted) return;

    final values = ref
        .read(projectFilterCodecProvider)
        .decode(view.definition, ref.read(projectsFilterSpecProvider));
    ref.read(projectSavedFiltersProvider.notifier).apply(id);
    _applyFilters(values);
    ref.read(toastProvider.notifier).show('View "${view.name}" applied');
  }

  void _clearFilters() {
    ref.read(projectSavedFiltersProvider.notifier).deactivate();
    _applyFilters(FilterValues());
    ref.read(toastProvider.notifier).show('Filters cleared');
  }
}
