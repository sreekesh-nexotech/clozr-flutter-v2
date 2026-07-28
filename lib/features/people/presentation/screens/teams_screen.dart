import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/people_providers.dart';
import '../components/info_banner.dart';
import '../components/people_title_actions.dart';
import '../components/team_card.dart';

/// Teams — groups of members organised by region or function. Header (brand +
/// title + search + create) over a scrolling list led by an info banner.
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
    final visible = ref.watch(visibleTeamsProvider);
    final byId = ref.watch(membersByIdProvider);
    final searchOpen = ref.watch(teamSearchOpenProvider);
    final query = ref.watch(teamSearchProvider);

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
                  onTap: () => toast('Filters — team lead & size'),
                ),
                PeopleCreateButton(onTap: () => toast('New team — coming soon')),
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
          ],
        ),
        Expanded(
          child: ListView(
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
          ),
        ),
      ],
    );
  }
}
