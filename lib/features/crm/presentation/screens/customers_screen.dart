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
import '../../application/providers/customers_providers.dart';
import '../components/customer_card.dart';

/// Customers list — same header + tabs + card-list pattern as Leads. Status
/// tabs come from [StatusMeta$.customerOrder] with colour dots.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(customerSearchProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(customersProvider).valueOrNull ?? const [];
    final visible = ref.watch(visibleCustomersProvider);
    final tab = ref.watch(customerTabProvider);
    final searchOpen = ref.watch(customerSearchOpenProvider);
    final query = ref.watch(customerSearchProvider);

    final tabDefs = <(String, String?)>[
      ('all', null),
      for (final k in StatusMeta$.customerOrder) (k, k),
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
              title: 'Customers',
              hasSearchQuery: query.isNotEmpty,
              onSearch: () => ref.read(customerSearchOpenProvider.notifier).state = !searchOpen,
              onFilter: () => ref.read(toastProvider.notifier).show('Filters — full CRM filter engine'),
            ),
            if (searchOpen) ...[
              SizedBox(height: 10.h),
              SearchField(
                controller: _searchCtrl,
                hint: 'Search customers…',
                onChanged: (v) => ref.read(customerSearchProvider.notifier).state = v,
                onClose: () {
                  _searchCtrl.clear();
                  ref.read(customerSearchProvider.notifier).state = '';
                  ref.read(customerSearchOpenProvider.notifier).state = false;
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
                      label: '${_label(k)} (${customerTabCount(all, k)})',
                      active: tab == k,
                      dotColor: dotKey == null ? null : StatusMeta$.customer[dotKey]!.color,
                      onTap: () => ref.read(customerTabProvider.notifier).state = k,
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
                      icon: PhosphorIconsRegular.userCircle,
                      title: 'No customers found',
                      body: 'Try a different status, clear filters, or convert a won lead into a customer.',
                    ),
                  ],
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 120.h),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => SizedBox(height: 14.h),
                  itemBuilder: (context, i) {
                    final c = visible[i];
                    return CustomerCard(
                      customer: c,
                      onTap: () => context.push('${Routes.customerDetail}?id=${c.id}'),
                      onCall: () => ref.read(toastProvider.notifier).show('Calling ${c.name.split(' ').first}…'),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _label(String key) => key == 'all' ? 'All' : StatusMeta$.customer[key]!.label;
}
