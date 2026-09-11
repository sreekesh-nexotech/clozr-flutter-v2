import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/filter_sheet.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../crm/presentation/components/saved_chip_row.dart' as chips;
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/filters/members_filter_spec.dart';
import '../../application/providers/people_providers.dart';
import '../../domain/entities/member.dart';
import '../components/member_card.dart';
import '../components/people_title_actions.dart';
import '../sheets/invite_member_sheet.dart';

/// Members — everyone with access to the workspace. Header (brand + title +
/// search + filter + role-filter tabs) over a scrolling list of member cards.
/// Wired to the spec-driven filter engine (drawer → applied provider → matcher
/// → badge → saved views), following the Leads reference.
class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key});

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(memberSearchProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Contextual add: the bottom-nav `+` opens the Invite member sheet here.
    registerAdd(
      ref,
      AddAction(label: 'Invite member', run: (ctx) => showInviteMemberSheet(ctx)),
    );

    final membersAsync = ref.watch(membersProvider);
    final all = membersAsync.valueOrNull ?? const [];
    final role = ref.watch(effectiveMemberRoleProvider);
    final searchOpen = ref.watch(memberSearchOpenProvider);
    final query = ref.watch(memberSearchProvider);
    final filterCount = ref.watch(memberFiltersProvider).activeCount;

    // The org's own roles when `/management/roles/` has loaded, the built-in
    // five otherwise. Counted client-side — the members list is already fully
    // in memory, and there is no per-role facet endpoint.
    final tabKeys = <String>['all', ...ref.watch(memberRoleTabsProvider)];

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
                Expanded(child: Text('Members', style: AppText.screenTitle())),
                PeopleIconAction(
                  icon: PhosphorIconsRegular.magnifyingGlass,
                  dot: query.isNotEmpty,
                  onTap: () => ref.read(memberSearchOpenProvider.notifier).state = !searchOpen,
                ),
                PeopleIconAction(
                  icon: PhosphorIconsRegular.slidersHorizontal,
                  badge: filterCount > 0 ? '$filterCount' : null,
                  onTap: _openFilters,
                ),
                PeopleCreateButton(onTap: () => showInviteMemberSheet(context)),
              ],
            ),
            SizedBox(height: 6.h),
            Text(
              'Everyone with access to this workspace. Reporting lines drive visibility scope.',
              style: AppText.caption(),
            ),
            SizedBox(height: 14.h),
            if (searchOpen) ...[
              SearchField(
                controller: _searchCtrl,
                hint: 'Search name, email, team…',
                onChanged: (v) => ref.read(memberSearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(memberSearchProvider.notifier).state = '';
                  ref.read(memberSearchOpenProvider.notifier).state = false;
                },
              ),
              SizedBox(height: 14.h),
            ],
            SizedBox(
              height: 40.h,
              child: TabChipRow(
                children: [
                  for (final k in tabKeys)
                    TabChip(
                      label: k == 'all' ? 'All (${all.length})' : k,
                      active: role == k,
                      onTap: () => ref.read(memberRoleProvider.notifier).state = k,
                    ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            _savedViewRow(filterCount),
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: AsyncStateView<List<Member>>(
            value: membersAsync,
            onRetry: () => ref.invalidate(membersProvider),
            onRefresh: _refresh,
            data: (_) {
              final visible = ref.watch(filteredMembersProvider);
              return visible.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        EmptyState(
                          icon: PhosphorIconsRegular.users,
                          title: 'No members found',
                          body: 'Try a different role, clear filters, or invite a new member.',
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => SizedBox(height: 10.h),
                      itemBuilder: (context, i) {
                        final m = visible[i];
                        return MemberCard(
                          member: m,
                          onTap: () => context.push('${Routes.memberDetail}?id=${m.id}'),
                        );
                      },
                    );
            },
          ),
        ),
      ],
    );
  }

  /// Pull-to-refresh. The org's own roles drive the role tabs, so both are
  /// reloaded together — refetching only the roster would leave the tab strip
  /// showing a stale role list.
  Future<void> _refresh() async {
    ref.invalidate(membersProvider);
    ref.invalidate(rolesProvider);
    await settle([
      ref.read(membersProvider.future),
      ref.read(rolesProvider.future),
    ]);
  }

  // ── Filter drawer ──
  Future<void> _openFilters() async {
    final spec = ref.read(membersFilterSpecProvider);
    final current = ref.read(memberFiltersProvider);
    final base = ref.read(visibleMembersProvider);
    final activeView = ref.read(memberSavedViewsProvider).active;

    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: current,
      previewCount: (draft) => base.where((m) => memberMatchesFilters(m, draft)).length,
      activeViewName: activeView?.name,
      existingViewNames: ref.read(memberSavedViewsProvider).views.map((v) => v.name).toSet(),
      onSaveView: (name, draft) {
        ref.read(memberSavedViewsProvider.notifier).upsert(name, draft);
        ref.read(toastProvider.notifier).show('View "$name" saved');
      },
    );
    if (result == null) return;

    ref.read(memberFiltersProvider.notifier).state = result;
    final views = ref.read(memberSavedViewsProvider);
    if (views.active != null && views.active!.values != result) {
      ref.read(memberSavedViewsProvider.notifier).deactivate();
    }
    ref.read(toastProvider.notifier).show('Filters applied');
  }

  // ── Saved-view row: saved bookmark chips + Clear ──
  Widget _savedViewRow(int filterCount) {
    final saved = ref.watch(memberSavedViewsProvider);
    return chips.SavedChipRow(
      views: [for (final v in saved.views) chips.SavedView(v.id, v.name)],
      active: {if (saved.activeId != null) saved.activeId!},
      showClearAlways: filterCount > 0,
      onToggle: _toggleView,
      onClear: _clearFilters,
    );
  }

  void _toggleView(String id) {
    final saved = ref.read(memberSavedViewsProvider);
    if (saved.activeId == id) {
      ref.read(memberSavedViewsProvider.notifier).deactivate();
      ref.read(memberFiltersProvider.notifier).state = FilterValues();
      return;
    }
    final view = saved.views.firstWhere((v) => v.id == id);
    ref.read(memberSavedViewsProvider.notifier).apply(id);
    ref.read(memberFiltersProvider.notifier).state = view.values.copy();
    ref.read(toastProvider.notifier).show('View "${view.name}" applied');
  }

  void _clearFilters() {
    ref.read(memberSavedViewsProvider.notifier).clearActive();
    ref.read(memberFiltersProvider.notifier).state = FilterValues();
    ref.read(toastProvider.notifier).show('Filters cleared');
  }
}
