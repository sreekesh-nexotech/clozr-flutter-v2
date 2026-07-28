import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/ops_tasks_providers.dart';
import '../../application/providers/projects_providers.dart';
import '../components/ops_task_card.dart';
import '../components/ops_widgets.dart';

/// Ops Tasks list — status tabs + a "My Tasks" saved-view chip over a scrolling
/// list of task cards.
class OpsTasksScreen extends ConsumerStatefulWidget {
  const OpsTasksScreen({super.key});

  @override
  ConsumerState<OpsTasksScreen> createState() => _OpsTasksScreenState();
}

class _OpsTasksScreenState extends ConsumerState<OpsTasksScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(otSearchProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = ref.watch(otBaseProvider);
    final visible = ref.watch(visibleOpsTasksProvider);
    final all = ref.watch(opsTasksListProvider);
    final projects = ref.watch(projectsListProvider);
    final tab = ref.watch(otTabProvider);
    final mine = ref.watch(myTasksFProvider);
    final searchOpen = ref.watch(otSearchOpenProvider);
    final query = ref.watch(otSearchProvider);

    final tabDefs = <(String, String)>[
      ('all', 'All'),
      for (final k in StatusMeta$.opsTask.keys) (k, StatusMeta$.opsTask[k]!.label),
    ];

    String projName(String id) =>
        projects.where((p) => p.id == id).map((p) => p.name).firstOrNull ?? '';

    return Column(
      children: [
        ListHeader(
          children: [
            const AppHeaderBar(),
            SizedBox(height: 14.h),
            const HeaderHairline(),
            SizedBox(height: 14.h),
            ScreenTitleRow(
              title: 'Tasks',
              hasSearchQuery: query.isNotEmpty,
              onSearch: () => ref.read(otSearchOpenProvider.notifier).state = !searchOpen,
              onFilter: () => ref.read(toastProvider.notifier).show('Filters — full task filter engine'),
            ),
            if (searchOpen) ...[
              SizedBox(height: 10.h),
              SearchField(
                controller: _searchCtrl,
                hint: 'Search tasks…',
                onChanged: (v) => ref.read(otSearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(otSearchProvider.notifier).state = '';
                  ref.read(otSearchOpenProvider.notifier).state = false;
                },
              ),
            ],
            SizedBox(height: 10.h),
            SizedBox(
              height: 40.h,
              child: TabChipRow(
                children: [
                  for (final (k, label) in tabDefs)
                    TabChip(
                      label: '$label (${otTabCount(base, k, mine: mine)})',
                      active: tab == k,
                      onTap: () => ref.read(otTabProvider.notifier).state = k,
                    ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                OpsSavedChip(
                  label: 'My Tasks',
                  active: mine,
                  onTap: () => ref.read(myTasksFProvider.notifier).state = !mine,
                ),
              ],
            ),
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: visible.isEmpty
              ? ListView(
                  children: const [
                    EmptyState(
                      icon: PhosphorIconsRegular.listChecks,
                      title: 'No tasks found',
                      body: 'Try a different status, or turn off "My Tasks" to see the whole team\'s work.',
                    ),
                  ],
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => SizedBox(height: 12.h),
                  itemBuilder: (context, i) {
                    final t = visible[i];
                    return OpsTaskCard(
                      task: t,
                      projectName: projName(t.projId),
                      unresolvedCount: unresolvedDeps(t, all).length,
                      onTap: () => context.push('${Routes.opsTaskDetail}?id=${t.id}'),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
