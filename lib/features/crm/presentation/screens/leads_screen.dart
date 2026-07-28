import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../components/lead_card.dart';

/// Leads list — the reference CRM list screen. Header (brand + title + search +
/// filter + status tabs + saved-view row) over a scrolling card list.
class LeadsScreen extends ConsumerStatefulWidget {
  const LeadsScreen({super.key});

  @override
  ConsumerState<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends ConsumerState<LeadsScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(leadSearchProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = ref.watch(leadBaseProvider);
    final visible = ref.watch(visibleLeadsProvider);
    final tab = ref.watch(leadTabProvider);
    final searchOpen = ref.watch(leadSearchOpenProvider);
    final query = ref.watch(leadSearchProvider);
    final teamAll = ref.watch(leadTeamAllProvider);

    final tabDefs = <(String, String?)>[
      ('all', null),
      for (final k in StatusMeta$.leadAll) (k, k),
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
              title: 'Leads',
              hasSearchQuery: query.isNotEmpty,
              onSearch: () => ref.read(leadSearchOpenProvider.notifier).state = !searchOpen,
              onFilter: () => ref.read(toastProvider.notifier).show('Filters — full CRM filter engine'),
            ),
            if (searchOpen) ...[
              SizedBox(height: 10.h),
              SearchField(
                controller: _searchCtrl,
                hint: 'Search name, company, product…',
                onChanged: (v) => ref.read(leadSearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(leadSearchProvider.notifier).state = '';
                  ref.read(leadSearchOpenProvider.notifier).state = false;
                },
              ),
            ],
            SizedBox(height: 10.h),
            SizedBox(
              height: 40.h,
              child: TabChipRow(
                children: [
                  for (final (k, dotKey) in tabDefs)
                    TabChip(
                      label: '${_label(k)} (${leadTabCount(base, k)})',
                      active: tab == k,
                      dotColor: dotKey == null ? null : StatusMeta$.lead[dotKey]!.color,
                      onTap: () => ref.read(leadTabProvider.notifier).state = k,
                    ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            _savedViewRow(teamAll),
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: visible.isEmpty
              ? ListView(
                  children: [
                    EmptyState(
                      icon: PhosphorIconsRegular.magnifyingGlass,
                      title: 'No leads found',
                      body: 'Try a different status, clear filters, or add a new lead to get started.',
                      ctaLabel: 'Add lead',
                      ctaIcon: PhosphorIconsBold.plus,
                      onCta: () => context.push(Routes.addLead),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => SizedBox(height: 14.h),
                  itemBuilder: (context, i) {
                    final lead = visible[i];
                    return LeadCard(
                      lead: lead,
                      onTap: () => context.push('${Routes.leadDetail}?id=${lead.id}'),
                      onCall: () => ref.read(toastProvider.notifier).show('Calling ${lead.name.split(' ').first}…'),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _label(String key) => key == 'all' ? 'All' : StatusMeta$.lead[key]!.label;

  Widget _savedViewRow(bool teamAll) {
    return SizedBox(
      height: 34.h,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _chip(
              label: teamAll ? 'All leads' : 'My leads',
              icon: PhosphorIconsFill.bookmarkSimple,
              active: !teamAll,
              onTap: () => ref.read(leadTeamAllProvider.notifier).state = !teamAll,
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({required String label, required IconData icon, required bool active, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34.h,
        padding: EdgeInsets.symmetric(horizontal: 11.w),
        decoration: BoxDecoration(
          color: active ? AppColors.blueSubtle : AppColors.bgChipGrey,
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13.sp, color: active ? AppColors.blueBright : AppColors.textLabelAlt),
            SizedBox(width: 5.w),
            Text(label,
                style: AppText.custom(
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: active ? AppColors.blueBright : AppColors.textLabelAlt)),
          ],
        ),
      ),
    );
  }
}
