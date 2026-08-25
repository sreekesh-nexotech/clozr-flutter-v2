import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/crm_module_schema_providers.dart';
import '../../application/providers/customer_activity_providers.dart';
import '../../application/providers/customers_providers.dart';
import '../../domain/entities/crm_catalog.dart';
import '../components/lead_schema_form.dart';

/// Edit customer — the org's own Customer layout, rendered as a form.
///
/// Every field, its order and its label come from
/// `GET /crm/customers/schema/?view_type=detail`, and the values from the
/// customer's record. The twin of [EditCrmTaskScreen], on the same contract:
/// the config that describes this form is the config that trims the
/// serializer, so no box here accepts input the backend would discard.
class EditCustomerScreen extends ConsumerStatefulWidget {
  const EditCustomerScreen({super.key});

  @override
  ConsumerState<EditCustomerScreen> createState() => _EditCustomerScreenState();
}

class _EditCustomerScreenState extends ConsumerState<EditCustomerScreen> {
  final _formKey = GlobalKey<LeadSchemaFormState>();
  bool _saving = false;

  Future<void> _save(String id) async {
    if (_saving) return;
    final payload = _formKey.currentState?.payload ?? const <String, dynamic>{};
    if (payload.isEmpty) {
      ref.read(toastProvider.notifier).show('Nothing to save');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(customersRepositoryProvider).updateCustomer(id, payload);
      if (!mounted) return;
      // The record and every list holding a copy are now stale.
      ref.invalidate(customerRowProvider(id));
      ref.invalidate(customersProvider);
      ref.read(toastProvider.notifier).show('Customer updated');
      context.pop();
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ref.read(toastProvider.notifier).showError(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final schema = ref.watch(customerDetailSchemaProvider);
    final row = ref.watch(customerRowProvider(id));
    // The status picker reads this; watched here so it is loading by the time
    // the user opens it rather than starting on first tap.
    ref.watch(customerStatusCatalogProvider);
    final statuses = ref.watch(customerStatusesProvider);

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: 'Customer',
            name: 'Edit customer',
            onBack: () => context.pop(),
          ),
          Expanded(
            child: switch (row) {
              AsyncValue(hasError: true) => Center(
                  child: Text('Could not load this customer',
                      style: AppText.body(color: AppColors.textMuted)),
                ),
              AsyncValue(value: null, isLoading: true) => const DetailSkeleton(),
              _ => ListView(
                  padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 24.h),
                  children: [
                    if (schema.editableColumns.isEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 32.h),
                        child: Text(
                          'This workspace has not configured any editable '
                          'customer fields yet.',
                          textAlign: TextAlign.center,
                          style: AppText.body(color: AppColors.textMuted),
                        ),
                      )
                    else
                      LeadSchemaForm(
                        key: _formKey,
                        schema: schema,
                        row: row.valueOrNull,
                        // The same two overrides the Add customer sheet needs.
                        // A customer writes its status as plain `status`, where
                        // the Lead default renames it to `status_id` — the wrong
                        // key is accepted and ignored, so the status would
                        // silently never change.
                        writeKey: (c) => c.name,
                        // `products` is a list of **objects**: the serializer
                        // wants `{product_id, quantity}` and answers "Expected a
                        // dictionary, but got str" for a bare id.
                        writeMulti: (c, ids) => c.name == 'products'
                            ? [for (final id in ids) {'product_id': id, 'quantity': 1}]
                            : ids,
                        // The shared form resolves a foreign key by its
                        // `relatedModel`, and it knows `LeadStatus` but not
                        // `CustomerStatus` — without this the picker opens empty
                        // on the field most likely to be edited.
                        optionsByColumn: {
                          if (statuses.isNotEmpty)
                            'status': [
                              for (final s in statuses) CatalogOption(id: s.id, name: s.name),
                            ],
                        },
                      ),
                  ],
                ),
            },
          ),
          _actionBar(id),
        ],
      ),
    );
  }

  Widget _actionBar(String id) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 22.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 100.w,
              height: 48.h,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: const Color(0xFFE6E7EA)),
              ),
              child: Text('Cancel',
                  style: AppText.custom(
                      size: 14, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: GestureDetector(
              onTap: _saving ? null : () => _save(id),
              child: Container(
                height: 48.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _saving ? AppColors.textPlaceholder : AppColors.navy,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: _saving
                    ? SizedBox(
                        width: 18.w,
                        height: 18.w,
                        child: const CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.white),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsBold.check, size: 16.sp, color: AppColors.white),
                          SizedBox(width: 8.w),
                          Text('Save changes',
                              style: AppText.custom(
                                  size: 15, weight: FontWeight.w700, color: AppColors.white)),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
