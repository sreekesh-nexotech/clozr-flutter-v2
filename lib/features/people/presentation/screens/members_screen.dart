import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/people_providers.dart';
import '../components/member_card.dart';
import '../components/people_title_actions.dart';

/// Members — everyone with access to the workspace. Header (brand + title +
/// search + role-filter tabs) over a scrolling list of member cards.
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
    final all = ref.watch(membersProvider).valueOrNull ?? const [];
    final visible = ref.watch(visibleMembersProvider);
    final role = ref.watch(memberRoleProvider);
    final searchOpen = ref.watch(memberSearchOpenProvider);
    final query = ref.watch(memberSearchProvider);

    final tabKeys = <String>['all', ...memberRoleOrder];

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
                  onTap: () => ref.read(toastProvider.notifier).show('Filters — role & status'),
                ),
                PeopleCreateButton(
                  onTap: () => ref.read(toastProvider.notifier).show('Invite member — coming soon'),
                ),
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
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: visible.isEmpty
              ? ListView(
                  children: [
                    EmptyState(
                      icon: PhosphorIconsRegular.users,
                      title: 'No members found',
                      body: 'Try a different role, clear the search, or invite a new member.',
                    ),
                  ],
                )
              : ListView.separated(
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
                ),
        ),
      ],
    );
  }
}
