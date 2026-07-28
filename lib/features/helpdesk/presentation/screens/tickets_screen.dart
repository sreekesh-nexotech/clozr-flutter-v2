import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_header_bar.dart';
import '../../../../core/widgets/list_header.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/tickets_providers.dart';
import '../components/ticket_card.dart';

/// Tickets list — brand header, title + search + filter, status tabs and the
/// My Tickets / Breaching soon chip row over a scrolling card list.
class TicketsScreen extends ConsumerStatefulWidget {
  const TicketsScreen({super.key});

  @override
  ConsumerState<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends ConsumerState<TicketsScreen> {
  final _searchCtrl = TextEditingController();

  static const _tabOrder = ['all', 'new', 'open', 'pending', 'resolved', 'closed'];

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(ticketSearchProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(ticketsProvider).valueOrNull ?? const [];
    final visible = ref.watch(visibleTicketsProvider);
    final tab = ref.watch(ticketTabProvider);
    final searchOpen = ref.watch(ticketSearchOpenProvider);
    final query = ref.watch(ticketSearchProvider);
    final mine = ref.watch(ticketMineProvider);
    final breach = ref.watch(ticketBreachingProvider);

    return Column(
      children: [
        ListHeader(
          children: [
            const AppHeaderBar(),
            SizedBox(height: 14.h),
            const HeaderHairline(),
            SizedBox(height: 14.h),
            ScreenTitleRow(
              title: 'Tickets',
              hasSearchQuery: query.isNotEmpty,
              onSearch: () => ref.read(ticketSearchOpenProvider.notifier).state = !searchOpen,
              onFilter: () => ref.read(toastProvider.notifier).show('Filters — full helpdesk filter engine'),
            ),
            if (searchOpen) ...[
              SizedBox(height: 10.h),
              SearchField(
                controller: _searchCtrl,
                hint: 'Search tickets…',
                onChanged: (v) => ref.read(ticketSearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(ticketSearchProvider.notifier).state = '';
                  ref.read(ticketSearchOpenProvider.notifier).state = false;
                },
              ),
            ],
            SizedBox(height: 12.h),
            SizedBox(
              height: 40.h,
              child: TabChipRow(
                children: [
                  for (final k in _tabOrder)
                    TabChip(
                      label: '${_label(k)} (${ticketTabCount(all, mine, breach, k)})',
                      active: tab == k,
                      onTap: () => ref.read(ticketTabProvider.notifier).state = k,
                    ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            _chipRow(mine, breach),
            SizedBox(height: 14.h),
          ],
        ),
        Expanded(
          child: visible.isEmpty
              ? _empty()
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => SizedBox(height: 12.h),
                  itemBuilder: (context, i) {
                    final t = visible[i];
                    return TicketCard(
                      ticket: t,
                      onTap: () => context.push('${Routes.ticketDetail}?id=${t.id}'),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _label(String key) => key == 'all' ? 'All' : StatusMeta$.ticket[key]!.label;

  Widget _chipRow(bool mine, bool breach) {
    return SizedBox(
      height: 34.h,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _chip(
              label: 'My Tickets',
              icon: PhosphorIconsFill.userCircle,
              active: mine,
              filled: true,
              onTap: () => ref.read(ticketMineProvider.notifier).state = !mine,
            ),
            SizedBox(width: 8.w),
            _chip(
              label: 'Breaching soon',
              icon: PhosphorIconsFill.timer,
              active: breach,
              filled: false,
              iconColorOff: AppColors.warningDeep,
              onTap: () => ref.read(ticketBreachingProvider.notifier).state = !breach,
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required IconData icon,
    required bool active,
    required bool filled,
    required VoidCallback onTap,
    Color? iconColorOff,
  }) {
    // Filled chip (My Tickets): navy when active. Outline chip (Breaching soon):
    // blue-subtle when active, white border when off.
    final Color bg;
    final Color fg;
    final Color iconColor;
    if (filled) {
      bg = active ? AppColors.navy : AppColors.white;
      fg = active ? AppColors.white : AppColors.textLabelAlt;
      iconColor = active ? AppColors.white : AppColors.textMuted2;
    } else {
      bg = active ? AppColors.blueSubtle : AppColors.white;
      fg = active ? AppColors.navy : AppColors.textLabelAlt;
      iconColor = active ? AppColors.blueBright : (iconColorOff ?? AppColors.textMuted2);
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34.h,
        padding: EdgeInsets.symmetric(horizontal: 11.w),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10.r),
          border: active ? null : Border.all(color: AppColors.borderCard),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13.sp, color: iconColor),
            SizedBox(width: 6.w),
            Text(label, style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: fg)),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return ListView(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 56.h),
          child: Column(
            children: [
              Container(
                width: 66.r,
                height: 66.r,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.borderCardSoft, borderRadius: BorderRadius.circular(19.r)),
                child: Icon(PhosphorIconsRegular.ticket, size: 30.sp, color: AppColors.textPlaceholder),
              ),
              SizedBox(height: 16.h),
              Text('No tickets found', style: AppText.sectionTitle(), textAlign: TextAlign.center),
              SizedBox(height: 6.h),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 240.w),
                child: Text(
                  'Try a different status, or turn off the active filter to see all tickets.',
                  textAlign: TextAlign.center,
                  style: AppText.body(color: AppColors.textMuted).copyWith(height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
