import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/filter_sheet.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../auth/application/providers/module_perm_providers.dart';
import '../../../crm/application/providers/leads_providers.dart';
import '../../../operations/application/providers/projects_providers.dart';
import '../../application/approval_rules.dart';
import '../../application/providers/approvals_providers.dart';
import '../../domain/entities/approval.dart';
import '../components/approval_decision_dialog.dart';
import '../components/approval_parts.dart';

const _all = 'all';
const _pageStep = 20;

/// People for the Requested-by / Owner filters. `/management/users/` refuses
/// anyone without People access, so — as on the webapp (backend ask AP-4) —
/// the assignable-user lists of the approval modules are merged instead; a
/// list the viewer cannot read comes back empty and is skipped.
final approvalPeopleOptionsProvider =
    Provider.autoDispose<List<FilterOption>>((ref) {
  final people = <String, String>{};
  for (final module in const ['lead', 'project_task', 'issue']) {
    for (final u
        in ref.watch(assignableUsersForModuleProvider(module)).valueOrNull ??
            const []) {
      if (u.id.isNotEmpty && u.name.isNotEmpty) people[u.id] = u.name;
    }
  }
  final sorted = people.entries.toList()
    ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
  return [for (final e in sorted) FilterOption(id: e.key, label: e.value)];
});

/// Projects for the Project filter — only for a role that can read projects,
/// so nobody else fires a request the server would refuse.
final approvalProjectOptionsProvider =
    Provider.autoDispose<List<FilterOption>>((ref) {
  if (!ref.watch(modulePermProvider('project')).read) return const [];
  final projects = ref.watch(projectsProvider).valueOrNull ?? const [];
  return [
    for (final p in projects)
      if (p.id.isNotEmpty) FilterOption(id: p.id, label: p.name)
  ];
});

/// Unified Approvals (webapp `ApprovalsScreen`): closing, owner-transfer and
/// due-date requests across modules, one tab at a time.
///
/// Not module-gated, like the webapp's `requires: 'signedIn'` entry: anyone
/// may have requests of their own, and the server scopes every row. What a
/// viewer may do with a row comes from the server's `can_*` flags.
class ApprovalsScreen extends ConsumerStatefulWidget {
  const ApprovalsScreen({super.key, this.initialTab, this.initialKind});

  /// `?tab=` — `pending` (default), `mine`, `team`, `history`.
  final String? initialTab;

  /// `?kind=` — `close`, `owner_transfer`, `due_date`. The old due-date
  /// approvals entry lands on `due_date`.
  final String? initialKind;

  @override
  ConsumerState<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends ConsumerState<ApprovalsScreen> {
  late String _tab;
  late FilterValues _filters;
  final _search = TextEditingController();
  Timer? _debounce;
  String _searchApplied = '';
  bool _searching = false;
  int _pageSize = _pageStep;
  bool _selecting = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _tab = ApprovalTabs.all.contains(widget.initialTab)
        ? widget.initialTab!
        : ApprovalTabs.pending;
    _filters = _spec(const [], const []).defaults();
    final kind = widget.initialKind;
    if (kind != null && ApprovalKinds.all.contains(kind)) {
      _filters['kind'] = RadioValue(id: kind, defaultId: _all);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  // ── Filters ──

  static List<FilterOption> _withAll(String allLabel, Map<String, String> m) =>
      [
        FilterOption(id: _all, label: allLabel),
        for (final e in m.entries) FilterOption(id: e.key, label: e.value)
      ];

  FilterSpec _spec(List<FilterOption> people, List<FilterOption> projects) {
    final requestFields = <FilterField>[
      FilterField(
          id: 'kind',
          label: 'Type',
          control: FilterControl.radio,
          options: _withAll('All types', approvalKindLabels)),
      FilterField(
          id: 'module',
          label: 'Module',
          control: FilterControl.radio,
          options: _withAll('All modules', approvalModuleLabels)),
      if (_tab != ApprovalTabs.pending)
        FilterField(
            id: 'status',
            label: 'Status',
            control: FilterControl.radio,
            options: _withAll('All statuses', approvalStatusLabels)),
      if (_tab == ApprovalTabs.team)
        FilterField(
            id: 'scope',
            label: 'Reportees',
            control: FilterControl.radio,
            options: [
              for (final s in ApprovalScopes.values)
                FilterOption(
                    id: s == ApprovalScopes.all ? _all : s,
                    label: approvalScopeLabels[s]!)
            ]),
    ];
    return FilterSpec(title: 'Filter approvals', sections: [
      FilterSection(title: 'Request', fields: requestFields),
      if (people.isNotEmpty)
        FilterSection(title: 'People', fields: [
          if (_tab != ApprovalTabs.mine)
            FilterField(
                id: 'requester',
                label: 'Requested by',
                control: FilterControl.radio,
                options: [
                  const FilterOption(id: _all, label: 'Anyone'),
                  ...people
                ]),
          FilterField(
              id: 'owner',
              label: 'Owner',
              control: FilterControl.radio,
              options: [
                const FilterOption(id: _all, label: 'Anyone'),
                ...people
              ]),
        ]),
      if (projects.isNotEmpty)
        FilterSection(title: 'Project', fields: [
          FilterField(
              id: 'project',
              label: 'Project',
              control: FilterControl.radio,
              options: [
                const FilterOption(id: _all, label: 'All projects'),
                ...projects
              ]),
        ]),
      const FilterSection(title: 'Raised', fields: [
        FilterField(
            id: 'raised', label: 'Raised', control: FilterControl.dateRange),
      ]),
    ]);
  }

  String? _radio(String id) {
    final v = _filters.radio(id)?.id;
    return v == null || v == _all ? null : v;
  }

  ApprovalListQuery get _query {
    final raised = _filters.date('raised');
    return ApprovalListQuery(
      tab: _tab,
      kind: _radio('kind'),
      module: _radio('module'),
      status: _tab == ApprovalTabs.pending ? null : _radio('status'),
      scope: _tab == ApprovalTabs.team
          ? (_radio('scope') ?? ApprovalScopes.all)
          : null,
      requesterId: _tab == ApprovalTabs.mine ? null : _radio('requester'),
      ownerId: _radio('owner'),
      projectId: _radio('project'),
      createdAfter: raised?.from,
      createdBefore: raised?.to,
      search: _searchApplied,
      pageSize: _pageSize,
    );
  }

  void _resetPaging() {
    _pageSize = _pageStep;
    _selected.clear();
  }

  Future<void> _openFilters() async {
    final spec = _spec(ref.read(approvalPeopleOptionsProvider),
        ref.read(approvalProjectOptionsProvider));
    final result = await showFilterSheet(
      context: context,
      spec: spec,
      initial: _filters,
      // Filtered by the server — the count is only known once applied.
      previewCount: (_) => -1,
    );
    if (result == null || !mounted) return;
    setState(() {
      _filters = result;
      _resetPaging();
    });
  }

  void _clearFilters() {
    _debounce?.cancel();
    _search.clear();
    setState(() {
      _filters = _spec(const [], const []).defaults();
      _searchApplied = '';
      _searching = false;
      _resetPaging();
    });
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _searchApplied = value.trim();
        _resetPaging();
      });
    });
  }

  void _setTab(String tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _selecting = false;
      _resetPaging();
      // Drop the filters this tab doesn't offer.
      if (tab == ApprovalTabs.pending) {
        _filters['status'] = const RadioValue(id: _all, defaultId: _all);
      }
      if (tab != ApprovalTabs.team) {
        _filters['scope'] = const RadioValue(id: _all, defaultId: _all);
      }
      if (tab == ApprovalTabs.mine) {
        _filters['requester'] = const RadioValue(id: _all, defaultId: _all);
      }
    });
  }

  // ── Actions ──

  void _open(Approval a) => context
      .push('${Routes.approvalDetail}?id=${Uri.encodeQueryComponent(a.id)}');

  Future<void> _bulk(List<Approval> rows, bool approve) async {
    final chosen = [
      for (final r in rows)
        if (_selected.contains(r.id) && r.canDecide) r
    ];
    if (chosen.isEmpty) return;
    final result = await showBulkDecisionDialog(context, ref,
        rows: chosen, approve: approve);
    if (result == null || !mounted) return;
    setState(() {
      _selected.clear();
      _selecting = false;
    });
  }

  void _refresh() {
    ref.invalidate(approvalsListProvider(_query));
    ref.invalidate(approvalCountsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(approvalTabsProvider);
    if (!tabs.contains(_tab)) {
      // The Team probe settled with nothing to show — fall back quietly.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !ref.read(approvalTabsProvider).contains(_tab)) {
          _setTab(ApprovalTabs.pending);
        }
      });
    }
    final counts =
        ref.watch(approvalCountsProvider).valueOrNull ?? ApprovalCounts.zero;
    // Kept alive while the screen is up, so the filter sheet's People and
    // Project sections have their options by the time it opens — a bare
    // `ref.read` of these auto-disposing lists found them still empty.
    ref.watch(approvalPeopleOptionsProvider);
    ref.watch(approvalProjectOptionsProvider);
    final query = _query;
    final async = ref.watch(approvalsListProvider(query));
    final filtered = hasNarrowingFilters(query);
    final canSelect = _tab == ApprovalTabs.pending &&
        (async.valueOrNull?.rows.any((r) => r.canDecide) ?? false);

    return Container(
      color: AppColors.bgDetail,
      child: Column(children: [
        DetailAppBar(
          section: 'Approvals',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (canSelect)
              DetailIconAction(
                icon: _selecting
                    ? PhosphorIconsRegular.x
                    : PhosphorIconsRegular.checkSquare,
                onTap: () => setState(() {
                  _selecting = !_selecting;
                  _selected.clear();
                }),
              ),
            DetailIconAction(
              icon: PhosphorIconsRegular.magnifyingGlass,
              onTap: () => setState(() => _searching = true),
            ),
            _FilterAction(active: _filters.activeCount, onTap: _openFilters),
          ]),
        ),
        if (_searching)
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 6.h),
            child: SearchField(
              controller: _search,
              hint: 'Search records',
              onChanged: _onSearch,
              onClose: () {
                _debounce?.cancel();
                _search.clear();
                setState(() {
                  _searching = false;
                  _searchApplied = '';
                  _resetPaging();
                });
              },
            ),
          ),
        SizedBox(
          height: 52.h,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 4.h),
            children: [
              for (final t in tabs) ...[
                TabChip(
                  label: t == ApprovalTabs.pending && counts.pendingForMe > 0
                      ? '${approvalTabLabels[t]} · ${counts.pendingForMe}'
                      : approvalTabLabels[t]!,
                  active: _tab == t,
                  onTap: () => _setTab(t),
                ),
                SizedBox(width: 8.w),
              ],
            ],
          ),
        ),
        OtherApprovalsStrip(counts: counts),
        if (filtered)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.w),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _clearFilters,
                icon: Icon(PhosphorIconsRegular.x, size: 14.sp),
                label: const Text('Clear filters'),
              ),
            ),
          ),
        if (_selecting) _selectionBar(async.valueOrNull?.rows ?? const []),
        Expanded(
          child: async.when(
            skipLoadingOnReload: true,
            loading: () => const ListSkeleton(itemCount: 4),
            error: (e, _) => ErrorState.forError(
                e is AppError
                    ? e
                    : const AppError(
                        type: AppErrorType.unknown,
                        message: 'Something went wrong. Please try again.'),
                onRetry: _refresh),
            data: (page) => _list(page, filtered),
          ),
        ),
      ]),
    );
  }

  Widget _list(ApprovalPage page, bool filtered) {
    if (page.rows.isEmpty) {
      final copy = emptyCopy(_tab, filtered: filtered);
      return RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(children: [
          EmptyState(
            icon: PhosphorIconsRegular.sealCheck,
            title: copy.title,
            body: copy.body,
            ctaLabel: filtered ? 'Clear filters' : null,
            ctaIcon: filtered ? PhosphorIconsBold.x : null,
            onCta: filtered ? _clearFilters : null,
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ListView(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
        children: [
          for (final a in page.rows)
            ApprovalCard(
              approval: a,
              onTap: () => _open(a),
              selectable: _selecting,
              selected: _selected.contains(a.id),
              onSelect: (v) {
                if (!a.canDecide) return;
                setState(
                    () => v ? _selected.add(a.id) : _selected.remove(a.id));
              },
              onLongPress: _tab == ApprovalTabs.pending && a.canDecide
                  ? () => setState(() {
                        _selecting = true;
                        _selected.add(a.id);
                      })
                  : null,
            ),
          if (page.hasMore)
            TextButton(
              onPressed: () => setState(() => _pageSize =
                  (_pageSize + _pageStep * 2).clamp(1, bulkDecideMax)),
              child: Text(
                  'Showing ${page.rows.length} of ${page.count} — show more'),
            ),
        ],
      ),
    );
  }

  Widget _selectionBar(List<Approval> rows) {
    final decidable = [
      for (final r in rows)
        if (r.canDecide) r
    ];
    final allSelected = decidable.isNotEmpty &&
        decidable.every((r) => _selected.contains(r.id));
    final n = _selected.length;
    final disabled = n == 0 || n > bulkDecideMax;
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 4.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
          color: AppColors.navy, borderRadius: BorderRadius.circular(12.r)),
      child: Row(children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            if (allSelected) {
              _selected.clear();
            } else {
              _selected.addAll(decidable.map((r) => r.id));
            }
          }),
          child: Text(allSelected ? 'Clear' : 'Select all',
              style: AppText.captionStrong(color: AppColors.white)),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Text('$n selected',
              style: AppText.bodyStrong(color: AppColors.white)),
        ),
        TextButton.icon(
          onPressed: disabled ? null : () => _bulk(rows, false),
          icon: Icon(PhosphorIconsRegular.x, size: 14.sp),
          label: const Text('Reject'),
          style: TextButton.styleFrom(foregroundColor: AppColors.white),
        ),
        TextButton.icon(
          onPressed: disabled ? null : () => _bulk(rows, true),
          icon: Icon(PhosphorIconsRegular.check, size: 14.sp),
          label: const Text('Approve'),
          style: TextButton.styleFrom(foregroundColor: AppColors.white),
        ),
      ]),
    );
  }
}

/// The filter icon with its active-filter count.
class _FilterAction extends StatelessWidget {
  const _FilterAction({required this.active, required this.onTap});

  final int active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      DetailIconAction(
          icon: PhosphorIconsRegular.funnelSimple,
          onTap: onTap,
          color: active > 0 ? AppColors.navy : AppColors.textSecondary),
      if (active > 0)
        Positioned(
            top: -2.h, right: -2.w, child: ApprovalCountDot(count: active)),
    ]);
  }
}
