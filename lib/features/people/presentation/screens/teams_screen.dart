import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/filter_sheet.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../crm/presentation/components/saved_chip_row.dart' as chips;
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/filters/teams_filter_spec.dart';
import '../../application/providers/people_providers.dart';
import '../../domain/entities/team.dart';
import '../components/info_banner.dart';
import '../components/people_title_actions.dart';
import '../components/team_card.dart';
import '../sheets/create_team_sheet.dart';

/// Teams — groups of members organised by region or function. Header (brand +
/// title + search + filter + create) over a scrolling list led by an info
/// banner. Wired to the spec-driven filter engine, following the Leads
/// reference.
class TeamsScreen extends ConsumerStatefulWidget {
  const TeamsScreen({super.key});

  @override
  ConsumerState<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends ConsumerState<TeamsScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(teamSearchProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Contextual add: the bottom-nav `+` opens the Create team sheet here.
    registerAdd(
      ref,
      AddAction(label: 'Create team', run: (ctx) => showCreateTeamSheet(ctx)),
    );

    final teamsAsync = ref.watch(teamsProvider);
    final searchOpen = ref.watch(teamSearchOpenProvider);
    final query = ref.watch(teamSearchProvider);
    final filterCount = ref.watch(teamFiltersProvider).activeCount;

    void toast(String m) => ref.read(toastProvider.notifier).show(m);

    return Column(
      children: [
        ListHeader(
          children: [
            const AppHeaderBar(),
            SizedBox(height: 14.h),
            const HeaderHairline(),
            SizedBox(height: 14.h),
            Row(
              children: [
                Expanded(child: Text('Teams', style: AppText.screenTitle())),
                PeopleIconAction(
                  icon: PhosphorIconsRegular.magnifyingGlass,
                  dot: query.isNotEmpty,
                  onTap: () => ref.read(teamSearchOpenProvider.notifier).state = !searchOpen,
                ),
                PeopleIconAction(
                  icon: PhosphorIconsRegular.slidersHorizontal,
                  badge: filterCount > 0 ? '$filterCount' : null,
                  onTap: _openFilters,
                ),
                PeopleCreateButton(onTap: () => showCreateTeamSheet(context)),
              ],
            ),
            SizedBox(height: 6.h),
            Text('Groups of members, organised by region or function.', style: AppText.caption()),
            SizedBox(height: 14.h),
            if (searchOpen) ...[
              SearchField(
                controller: _searchCtrl,
                hint: 'Search team, lead, member…',
                onChanged: (v) => ref.read(teamSearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(teamSearchProvider.notifier).state = '';
                  ref.read(teamSearchOpenProvider.notifier).state = false;
                },
              ),
              SizedBox(height: 14.h),
            ],
            _savedViewRow(filterCount),
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: AsyncStateView<List<Team>>(
            value: teamsAsync,
            onRetry: () => ref.invalidate(teamsProvider),
            data: (_) {
              final visible = ref.watch(filteredTeamsProvider);
              final byId = ref.watch(membersByIdProvider);
              return ListView(
                padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                children: [
                  const InfoBanner(
                    spans: [
                      TextSpan(text: 'Teams are for grouping only — they carry '),
                      TextSpan(text: 'no visibility scope of their own', style: TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: '. Access always comes from a member’s role and reporting hierarchy.'),
                    ],
                  ),
                  SizedBox(height: 10.h),
                  if (visible.isEmpty)
                    EmptyState(
                      icon: PhosphorIconsRegular.usersThree,
                      iconColor: AppColors.navy,
                      title: 'No teams found',
                      body: 'Try a different search or clear the filters.',
                    )
                  else
                    for (int i = 0; i < visible.length; i++) ...[
                      if (i > 0) SizedBox(height: 10.h),
                      TeamCard(
                        team: visible[i],
                        membersById: byId,
                        onAdd: () => toast('Add member — coming soon'),
                      ),
                    ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Filter drawer ──
  Future<void> _openFilters() async {
    final spec = ref.read(teamsFilterSpecProvider);
    final current = ref.read(teamFiltersProvider);
    final base = ref.read(visibleTeamsProvider);
    final activeView = ref.read(teamSavedViewsProvider).active;

    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: current,
      previewCount: (draft) => base.where((t) => teamMatchesFilters(t, draft)).length,
      activeViewName: activeView?.name,
      onSaveView: (name, draft) {
        ref.read(teamSavedViewsProvider.notifier).upsert(name, draft);
        ref.read(toastProvider.notifier).show('View "$name" saved');
      },
    );
    if (result == null) return;

    ref.read(teamFiltersProvider.notifier).state = result;
    final views = ref.read(teamSavedViewsProvider);
    if (views.active != null && views.active!.values != result) {
      ref.read(teamSavedViewsProvider.notifier).deactivate();
    }
    ref.read(toastProvider.notifier).show('Filters applied');
  }

  // ── Saved-view row: saved bookmark chips + Clear ──
  Widget _savedViewRow(int filterCount) {
    final saved = ref.watch(teamSavedViewsProvider);
    return chips.SavedChipRow(
      views: [for (final v in saved.views) chips.SavedView(v.id, v.name)],
      active: {if (saved.activeId != null) saved.activeId!},
      showClearAlways: filterCount > 0,
      onToggle: _toggleView,
      onClear: _clearFilters,
    );
  }

  void _toggleView(String id) {
    final saved = ref.read(teamSavedViewsProvider);
    if (saved.activeId == id) {
      ref.read(teamSavedViewsProvider.notifier).deactivate();
      ref.read(teamFiltersProvider.notifier).state = FilterValues();
      return;
    }
    final view = saved.views.firstWhere((v) => v.id == id);
    ref.read(teamSavedViewsProvider.notifier).apply(id);
    ref.read(teamFiltersProvider.notifier).state = view.values.copy();
    ref.read(toastProvider.notifier).show('View "${view.name}" applied');
  }

  void _clearFilters() {
    ref.read(teamSavedViewsProvider.notifier).clearActive();
    ref.read(teamFiltersProvider.notifier).state = FilterValues();
    ref.read(toastProvider.notifier).show('Filters cleared');
  }
}
