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
import '../../application/providers/followups_providers.dart';
import '../components/followup_card.dart';

/// Follow-ups list — checkbox cards grouped overdue→upcoming→done, with
/// status tabs, search and a filter toast.
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
    final all = ref.watch(followupsProvider).valueOrNull ?? const [];
    final visible = ref.watch(visibleFollowupsProvider);
    final tab = ref.watch(followupTabProvider);
    final searchOpen = ref.watch(followupSearchOpenProvider);
    final query = ref.watch(followupSearchProvider);

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
              onSearch: () => ref.read(followupSearchOpenProvider.notifier).state = !searchOpen,
              onFilter: () => ref.read(toastProvider.notifier).show('Filters — full CRM filter engine'),
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
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: visible.isEmpty
              ? ListView(
                  children: const [
                    EmptyState(
                      icon: PhosphorIconsRegular.checkCircle,
                      title: 'All caught up',
                      body: 'No pending follow-ups. Schedule your next call or site visit to see it here.',
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
}
