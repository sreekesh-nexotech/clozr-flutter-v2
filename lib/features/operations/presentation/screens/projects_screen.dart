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
import '../../../crm/presentation/components/saved_chip_row.dart' as chips;
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../../shell/application/providers/shell_providers.dart';
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

    final projectsAsync = ref.watch(projectsProvider);
    final base = ref.watch(projBaseProvider);
    final tab = ref.watch(projTabProvider);
    final mine = ref.watch(myProjectsProvider);
    final searchOpen = ref.watch(projSearchOpenProvider);
    final query = ref.watch(projSearchProvider);
    final filters = ref.watch(projectFiltersProvider);
    final filterCount = filters.activeCount;

    final tabDefs = <(String, String)>[
      ('all', 'All'),
      for (final k in StatusMeta$.project.keys) (k, StatusMeta$.project[k]!.label),
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
                      label: '$label (${projTabCount(base, k, mine: mine)})',
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
            onRetry: () => ref.invalidate(projectsProvider),
            data: (_) {
              final tabVisible = ref.watch(visibleProjectsProvider);
              final visible = filters.isEmpty
                  ? tabVisible
                  : tabVisible.where((p) => projectMatchesFilters(p, filters)).toList();
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
  Future<void> _openFilters() async {
    final spec = ref.read(projectsFilterSpecProvider);
    final current = ref.read(projectFiltersProvider);
    final base = ref.read(projBaseProvider);
    final activeView = ref.read(projectSavedViewsProvider).active;

    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: current,
      previewCount: (draft) => base.where((p) => projectMatchesFilters(p, draft)).length,
      activeViewName: activeView?.name,
      onSaveView: (name, draft) {
        ref.read(projectSavedViewsProvider.notifier).upsert(name, draft);
        ref.read(toastProvider.notifier).show('View "$name" saved');
      },
    );
    if (result == null) return;

    ref.read(projectFiltersProvider.notifier).state = result;
    final views = ref.read(projectSavedViewsProvider);
    if (views.active != null && views.active!.values != result) {
      ref.read(projectSavedViewsProvider.notifier).deactivate();
    }
    ref.read(toastProvider.notifier).show('Filters applied');
  }

  // ── Saved-view row: My Projects toggle + saved bookmark chips + Clear ──
  Widget _savedViewRow(bool mine, int filterCount) {
    final saved = ref.watch(projectSavedViewsProvider);
    return SizedBox(
      height: 34.h,
      child: Row(
        children: [
          OpsSavedChip(
            label: 'My Projects',
            active: mine,
            onTap: () => ref.read(myProjectsProvider.notifier).state = !mine,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: chips.SavedChipRow(
              views: [for (final v in saved.views) chips.SavedView(v.id, v.name)],
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

  void _toggleView(String id) {
    final saved = ref.read(projectSavedViewsProvider);
    if (saved.activeId == id) {
      ref.read(projectSavedViewsProvider.notifier).deactivate();
      ref.read(projectFiltersProvider.notifier).state = FilterValues();
      return;
    }
    final view = saved.views.firstWhere((v) => v.id == id);
    ref.read(projectSavedViewsProvider.notifier).apply(id);
    ref.read(projectFiltersProvider.notifier).state = view.values.copy();
    ref.read(toastProvider.notifier).show('View "${view.name}" applied');
  }

  void _clearFilters() {
    ref.read(projectSavedViewsProvider.notifier).clearActive();
    ref.read(projectFiltersProvider.notifier).state = FilterValues();
    ref.read(toastProvider.notifier).show('Filters cleared');
  }
}
