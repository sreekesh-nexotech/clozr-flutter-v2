import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../../crm/presentation/sheets/add_sheet_kit.dart' show initialsOf;
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/settlement_providers.dart';
import '../../domain/entities/acc_masters.dart';
import '../components/acc_widgets.dart';
import '../sheets/vendor_form_sheet.dart';

/// Vendors (plan §4.10) — the supplier list, searchable in memory, with
/// Active / All chips and an add action.
class AccVendorsScreen extends ConsumerStatefulWidget {
  const AccVendorsScreen({super.key});

  @override
  ConsumerState<AccVendorsScreen> createState() => _AccVendorsScreenState();
}

class _AccVendorsScreenState extends ConsumerState<AccVendorsScreen> {
  final _search = TextEditingController();
  String _q = '';
  bool _activeOnly = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = ref.watch(accPermProvider('acc_purchase')).create;
    final stateName = ref.watch(gstStateNameProvider);
    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: 'Vendors',
            onBack: () => context.pop(),
            trailing: canCreate
                ? DetailIconAction(
                    icon: PhosphorIconsBold.plus,
                    onTap: () async {
                      final v = await showVendorFormSheet(context);
                      if (v != null && context.mounted) context.push('${Routes.accVendorDetail}?id=${v.id}');
                    },
                  )
                : null,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
            child: Column(
              children: [
                SearchField(
                  controller: _search,
                  hint: 'Search vendors…',
                  autofocus: false,
                  onChanged: (v) => setState(() => _q = v),
                  onClose: () {
                    _search.clear();
                    setState(() => _q = '');
                  },
                ),
                SizedBox(height: 12.h),
                SizedBox(
                  height: 40.h,
                  child: TabChipRow(children: [
                    TabChip(label: 'Active', active: _activeOnly, onTap: () => setState(() => _activeOnly = true)),
                    TabChip(label: 'All', active: !_activeOnly, onTap: () => setState(() => _activeOnly = false)),
                  ]),
                ),
              ],
            ),
          ),
          Expanded(
            child: AccountingGate(
              child: AsyncStateView<List<Vendor>>(
                value: ref.watch(vendorsProvider),
                onRetry: () => ref.invalidate(vendorsProvider),
                onRefresh: () async {
                  ref.invalidate(vendorsProvider);
                  await settle([ref.read(vendorsProvider.future)]);
                },
                data: (all) {
                  final q = _q.trim().toLowerCase();
                  final rows = [
                    for (final v in all)
                      if ((!_activeOnly || v.isActive) &&
                          (q.isEmpty ||
                              v.name.toLowerCase().contains(q) ||
                              (v.legalName ?? '').toLowerCase().contains(q)))
                        v,
                  ];
                  if (rows.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        EmptyState(
                          icon: PhosphorIconsRegular.storefront,
                          title: all.isEmpty ? 'No vendors yet' : 'No matching vendor',
                          body: all.isEmpty ? 'Add the suppliers you buy from.' : 'Try a different search.',
                          ctaLabel: all.isEmpty && canCreate ? 'Add vendor' : null,
                          ctaIcon: PhosphorIconsBold.plus,
                          onCta: () => showVendorFormSheet(context),
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(16.w, 2.h, 16.w, 32.h),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => SizedBox(height: 10.h),
                    itemBuilder: (_, i) => _row(rows[i], stateName),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(Vendor v, String Function(String?) stateName) {
    return ClozrCard(
      radius: 14,
      padding: EdgeInsets.all(13.r),
      onTap: () => context.push('${Routes.accVendorDetail}?id=${v.id}'),
      child: Row(
        children: [
          Container(
            width: 40.w,
            height: 40.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(11.r)),
            child: Text(initialsOf(v.name), style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.navy)),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 3.h),
                Text(
                  [if ((v.legalName ?? '').isNotEmpty) v.legalName!, if (v.stateCode != null) stateName(v.stateCode)].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          if (!v.isActive) const StatusPill(label: 'Inactive', color: AppColors.textMuted),
          SizedBox(width: 6.w),
          Icon(PhosphorIconsBold.caretRight, size: 13.sp, color: AppColors.textPlaceholder),
        ],
      ),
    );
  }
}
