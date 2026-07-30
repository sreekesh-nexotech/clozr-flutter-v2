import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/filter_sheet.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../shell/application/providers/contextual_add_provider.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/filters/followups_filter_spec.dart';
import '../../application/providers/followups_providers.dart';
import '../components/followup_card.dart';
import '../components/saved_chip_row.dart' as chips;
import '../sheets/add_followup_sheet.dart';

/// Follow-ups list — checkbox cards grouped overdue→upcoming→done, wired to the
/// spec-driven filter engine and the contextual Add follow-up sheet.
class FollowupsScreen extends ConsumerStatefulWidget {
  const FollowupsScreen({super.key});

  @override
  ConsumerState<FollowupsScreen> createState() => _FollowupsScreenState();
}

class _FollowupsScreenState extends ConsumerState<FollowupsScreen> {
  final _searchCtrl = TextEditingController();

  static const _tabDefs = <(String, String)>[
    ('all', 'All'),
    ('overdue', 'Overdue'),
    ('due', 'Upcoming'),
    ('done', 'Done'),
  ];

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(followupSearchProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Contextual add: the bottom-nav `+` opens the Add follow-up sheet here.
    registerAdd(
      ref,
      AddAction(label: 'Add follow-up', run: (ctx) => showAddFollowupSheet(ctx, ref)),
    );

    final all = ref.watch(followupsAllProvider);
    final visible = ref.watch(visibleFollowupsProvider);
    final tab = ref.watch(followupTabProvider);
    final searchOpen = ref.watch(followupSearchOpenProvider);
    final query = ref.watch(followupSearchProvider);
    final filterCount = ref.watch(followupFiltersProvider).activeCount;

    return Column(
      children: [
        ListHeader(
          children: [
            const AppHeaderBar(),
            SizedBox(height: 14.h),
            const HeaderHairline(),
            SizedBox(height: 14.h),
            ScreenTitleRow(
              title: 'Follow-ups',
              hasSearchQuery: query.isNotEmpty,
              filterCount: filterCount,
              onSearch: () => ref.read(followupSearchOpenProvider.notifier).state = !searchOpen,
              onFilter: _openFilters,
            ),
            if (searchOpen) ...[
              SizedBox(height: 10.h),
              SearchField(
                controller: _searchCtrl,
                hint: 'Search follow-ups…',
                onChanged: (v) => ref.read(followupSearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(followupSearchProvider.notifier).state = '';
                  ref.read(followupSearchOpenProvider.notifier).state = false;
                },
              ),
            ],
            SizedBox(height: 10.h),
            SizedBox(
              height: 40.h,
              child: TabChipRow(
                children: [
                  for (final (k, lbl) in _tabDefs)
                    TabChip(
                      label: '$lbl (${followupTabCount(all, k)})',
                      active: tab == k,
                      onTap: () => ref.read(followupTabProvider.notifier).state = k,
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
          child: visible.isEmpty
              ? ListView(
                  children: [
                    EmptyState(
                      icon: PhosphorIconsRegular.checkCircle,
                      title: 'All caught up',
                      body: 'No pending follow-ups. Schedule your next call or site visit to see it here.',
                      ctaLabel: 'Add follow-up',
                      ctaIcon: PhosphorIconsBold.plus,
                      onCta: () => showAddFollowupSheet(context, ref),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => SizedBox(height: 12.h),
                  itemBuilder: (context, i) {
                    final f = visible[i];
                    return FollowupCard(
                      followup: f,
                      onTap: () => context.push('${Routes.followupDetail}?id=${f.id}'),
                      onToggle: () => ref.read(toastProvider.notifier).show(
                          f.status == 'done' ? 'Follow-up reopened' : 'Follow-up marked done'),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Filter drawer ──
  Future<void> _openFilters() async {
    final spec = ref.read(followupsFilterSpecProvider);
    final current = ref.read(followupFiltersProvider);
    final base = ref.read(followupsAllProvider);
    final activeView = ref.read(followupSavedViewsProvider).active;

    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: current,
      previewCount: (draft) => base.where((f) => followupMatchesFilters(f, draft)).length,
      activeViewName: activeView?.name,
      onSaveView: (name, draft) {
        ref.read(followupSavedViewsProvider.notifier).upsert(name, draft);
        ref.read(toastProvider.notifier).show('View "$name" saved');
      },
    );
    if (result == null) return;

    ref.read(followupFiltersProvider.notifier).state = result;
    final views = ref.read(followupSavedViewsProvider);
    if (views.active != null && views.active!.values != result) {
      ref.read(followupSavedViewsProvider.notifier).deactivate();
    }
    ref.read(toastProvider.notifier).show('Filters applied');
  }

  // ── Saved-view row: saved bookmark chips + Clear ──
  Widget _savedViewRow(int filterCount) {
    final saved = ref.watch(followupSavedViewsProvider);
    return SizedBox(
      height: 34.h,
      child: chips.SavedChipRow(
        views: [for (final v in saved.views) chips.SavedView(v.id, v.name)],
        active: {if (saved.activeId != null) saved.activeId!},
        showClearAlways: filterCount > 0,
        onToggle: _toggleView,
        onClear: _clearFilters,
      ),
    );
  }

  void _toggleView(String id) {
    final saved = ref.read(followupSavedViewsProvider);
    if (saved.activeId == id) {
      ref.read(followupSavedViewsProvider.notifier).deactivate();
      ref.read(followupFiltersProvider.notifier).state = FilterValues();
      return;
    }
    final view = saved.views.firstWhere((v) => v.id == id);
    ref.read(followupSavedViewsProvider.notifier).apply(id);
    ref.read(followupFiltersProvider.notifier).state = view.values.copy();
    ref.read(toastProvider.notifier).show('View "${view.name}" applied');
  }

  void _clearFilters() {
    ref.read(followupSavedViewsProvider.notifier).clearActive();
    ref.read(followupFiltersProvider.notifier).state = FilterValues();
    ref.read(toastProvider.notifier).show('Filters cleared');
  }
}
