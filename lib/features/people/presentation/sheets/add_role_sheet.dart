import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../shell/application/providers/shell_providers.dart';

/// Visibility scopes a custom role can carry (prototype `roleScopeChips`).
const _scopeChips = <String>[
  'Organization-wide',
  'Self + Reporting Hierarchy',
  'Team-based + Reporting Hierarchy',
];

/// Capabilities a custom role can grant (prototype `roleCapRows`).
const _capOpts = <String>[
  'User Management',
  'CRM',
  'Reports & Dashboards',
  'Record payments',
];

/// Opens the Add role sheet — a faithful port of the prototype's `addRole`
/// sheet. Used by both the Roles screen create button and the contextual `+`.
Future<void> showAddRoleSheet(BuildContext context) {
  return showClozrSheet<void>(
    context: context,
    builder: (_) => const _AddRoleSheet(),
  );
}

class _AddRoleSheet extends ConsumerStatefulWidget {
  const _AddRoleSheet();

  @override
  ConsumerState<_AddRoleSheet> createState() => _AddRoleSheetState();
}

class _AddRoleSheetState extends ConsumerState<_AddRoleSheet> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  String _scope = 'Self + Reporting Hierarchy';
  final Set<String> _caps = {'CRM'};
  bool _showErrors = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  bool get _nameOk => _name.text.trim().isNotEmpty;

  void _submit() {
    setState(() => _showErrors = true);
    if (!_nameOk) {
      ref.read(toastProvider.notifier).show('Enter a role name');
      return;
    }
    Navigator.of(context).pop();
    ref.read(toastProvider.notifier).show('Role "${_name.text.trim()}" created');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'Add role', onClose: () => Navigator.of(context).pop()),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 18.h),
            children: [
              AppTextField(
                label: 'Role name',
                required: true,
                controller: _name,
                hint: 'e.g. Regional Lead',
                errorText: _showErrors && !_nameOk ? 'Enter a role name' : null,
                onChanged: (_) => setState(() {}),
              ),
              SizedBox(height: 14.h),
              AppTextField(
                label: 'Description',
                controller: _desc,
                hint: 'What is this role for?',
              ),
              SizedBox(height: 16.h),
              Text('Visibility scope',
                  style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
              SizedBox(height: 8.h),
              Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: [
                  for (final s in _scopeChips) _scopeChip(s),
                ],
              ),
              SizedBox(height: 16.h),
              Text('Capabilities',
                  style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
              SizedBox(height: 6.h),
              for (final c in _capOpts) _capRow(c),
              SizedBox(height: 20.h),
              PrimaryButton(
                label: 'Create role',
                icon: PhosphorIconsBold.plus,
                height: 48,
                onTap: _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _scopeChip(String s) {
    final on = _scope == s;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _scope = s),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: on ? AppColors.navy : AppColors.white,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: on ? AppColors.navy : AppColors.borderInput, width: 1.5),
        ),
        child: Text(s,
            style: AppText.custom(
                size: 12.5,
                weight: on ? FontWeight.w700 : FontWeight.w500,
                color: on ? AppColors.white : AppColors.textLabelAlt)),
      ),
    );
  }

  Widget _capRow(String c) {
    final on = _caps.contains(c);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => on ? _caps.remove(c) : _caps.add(c)),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 9.h),
        child: Row(
          children: [
            Container(
              width: 20.w,
              height: 20.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.navy : AppColors.white,
                borderRadius: BorderRadius.circular(6.r),
                border: on ? null : Border.all(color: AppColors.borderInput, width: 1.5),
              ),
              child: on ? Icon(PhosphorIconsBold.check, size: 13.sp, color: AppColors.white) : null,
            ),
            SizedBox(width: 10.w),
            Text(c,
                style: AppText.custom(
                    size: 13.5,
                    weight: on ? FontWeight.w600 : FontWeight.w500,
                    color: on ? AppColors.textPrimary : AppColors.textLabelAlt)),
          ],
        ),
      ),
    );
  }
}
