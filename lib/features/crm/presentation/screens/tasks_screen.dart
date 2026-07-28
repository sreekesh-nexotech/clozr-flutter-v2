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
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/crm_tasks_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../components/task_card.dart';

/// Tasks list — checkbox cards with status pills, filtered by tab + search.
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  final _searchCtrl = TextEditingController();

  static const _tabDefs = <(String, String)>[
    ('all', 'All'),
    ('mine', 'My tasks'),
    ('overdue', 'Overdue'),
    ('todo', 'To do'),
    ('inprogress', 'In Progress'),
    ('blocked', 'Blocked'),
    ('done', 'Done'),
  ];

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(crmTaskSearchProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(crmTasksProvider).valueOrNull ?? const [];
    final visible = ref.watch(visibleCrmTasksProvider);
    final tab = ref.watch(crmTaskTabProvider);
    final searchOpen = ref.watch(crmTaskSearchOpenProvider);
    final query = ref.watch(crmTaskSearchProvider);
    final leads = ref.watch(leadsProvider).valueOrNull ?? const [];

    String? relatedLineFor(String? leadId) {
      if (leadId == null) return null;
      for (final l in leads) {
        if (l.id == leadId) return '${l.company ?? l.name} · #${l.id}';
      }
      return null;
    }

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
              onSearch: () => ref.read(crmTaskSearchOpenProvider.notifier).state = !searchOpen,
              onFilter: () => ref.read(toastProvider.notifier).show('Filters — full CRM filter engine'),
            ),
            if (searchOpen) ...[
              SizedBox(height: 10.h),
              SearchField(
                controller: _searchCtrl,
                hint: 'Search tasks…',
                onChanged: (v) => ref.read(crmTaskSearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(crmTaskSearchProvider.notifier).state = '';
                  ref.read(crmTaskSearchOpenProvider.notifier).state = false;
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
                      label: '$lbl (${crmTaskTabCount(all, k)})',
                      active: tab == k,
                      onTap: () => ref.read(crmTaskTabProvider.notifier).state = k,
                    ),
                ],
              ),
            ),
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: visible.isEmpty
              ? ListView(
                  children: const [
                    EmptyState(
                      icon: PhosphorIconsRegular.funnel,
                      title: 'No tasks found',
                      body: 'Try a different status, clear filters or search to see more tasks.',
                    ),
                  ],
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => SizedBox(height: 12.h),
                  itemBuilder: (context, i) {
                    final t = visible[i];
                    return TaskCard(
                      task: t,
                      relatedLine: relatedLineFor(t.leadId),
                      onTap: () => context.push('${Routes.taskDetail}?id=${t.id}'),
                      onToggle: () => ref.read(toastProvider.notifier).show(
                          t.status == 'done' ? 'Task reopened' : 'Task marked complete'),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
