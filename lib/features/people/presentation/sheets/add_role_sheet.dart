import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../domain/entities/role.dart';
import '../../application/providers/people_providers.dart';
import '../../domain/entities/module_catalog.dart';

/// Opens the Add role sheet. Used by both the Roles screen create button and
/// the contextual `+`.
///
/// The scope chips and capability rows come from
/// `GET /management/permissions/module-catalog/` — they were a prototype list
/// ("User Management", "Reports & Dashboards") that matched no grantable group,
/// and neither the scope nor the ticks were ever sent: every role was created
/// as CRM-at-hierarchy regardless of what the form said.
Future<void> showAddRoleSheet(BuildContext context) {
  return showClozrSheet<void>(
    context: context,
    builder: (_) => const _AddRoleSheet(),
  );
}

/// The same sheet in edit mode (`roles.md` §5).
///
/// Only custom roles reach here: a seeded role rejects the `PATCH` with a 403,
/// and the list already refuses to open one.
Future<void> showEditRoleSheet(BuildContext context, Role role) {
  return showClozrSheet<void>(
    context: context,
    builder: (_) => _AddRoleSheet(role: role),
  );
}

class _AddRoleSheet extends ConsumerStatefulWidget {
  const _AddRoleSheet({this.role});

  /// Null to create; the role being edited otherwise.
  final Role? role;

  @override
  ConsumerState<_AddRoleSheet> createState() => _AddRoleSheetState();
}

class _AddRoleSheetState extends ConsumerState<_AddRoleSheet> {
  final _name = TextEditingController();
  final _desc = TextEditingController();

  /// The record-scope **code** (`all` / `hierarchy` / `team`), not its label —
  /// the label is display, the code is what `module_groups[].visibility` takes.
  late String _scope = widget.role?.scopeCode.isNotEmpty == true
      ? widget.role!.scopeCode
      : 'hierarchy';

  /// The module-group keys ticked (`crm`, `pmo`).
  late final Set<String> _groups = {
    ...?widget.role?.groupKeys,
    if (widget.role == null) 'crm',
  };

  bool get _isEdit => widget.role != null;

  /// A seeded role: the sheet opens so its scope and capabilities can be read,
  /// but nothing can be saved — `PATCH` answers
  /// `403 "Seeded roles cannot be edited."`
  bool get _locked => widget.role?.locked == true;

  bool _showErrors = false;

  /// True while the create is in flight, so a second tap cannot post twice.
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final role = widget.role;
    if (role != null) {
      _name.text = role.name;
      _desc.text = role.desc;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  bool get _nameOk => _name.text.trim().isNotEmpty;
  bool get _capsOk => _groups.isNotEmpty;

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _showErrors = true);
    final toast = ref.read(toastProvider.notifier);
    if (!_nameOk) {
      toast.show('Enter a role name');
      return;
    }
    // A role granting nothing can be created but does nothing — and the form
    // cannot say so afterwards, since the sheet closes on success.
    if (!_capsOk) {
      toast.show('Pick at least one capability');
      return;
    }
    final name = _name.text.trim();
    final done = _isEdit ? 'updated' : 'created';
    if (!ApiConfig.apiEnabled) {
      Navigator.of(context).pop();
      toast.show('Role "$name" $done');
      return;
    }

    final desc = _desc.text.trim();
    setState(() => _saving = true);
    try {
      final repo = ref.read(peopleRepositoryProvider);
      final role = widget.role;
      if (role != null) {
        await repo.updateRole(
          role.id,
          name: name,
          description: desc.isEmpty ? null : desc,
          groups: _groups,
          visibility: _scope,
        );
      } else {
        await repo.createRole(
          name: name,
          description: desc.isEmpty ? null : desc,
          groups: _groups,
          visibility: _scope,
        );
      }
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      // A seeded role 403s and a duplicate name 400s — the server's message is
      // the only thing that says which.
      toast.showError(e.message);
      return;
    }
    if (!mounted) return;
    ref.invalidate(rolesProvider);
    Navigator.of(context).pop();
    toast.show('Role "$name" $done');
  }

  @override
  Widget build(BuildContext context) {
    // The org-agnostic registry of grantable cards and scopes. Empty while it
    // loads, in mock mode and on failure — the built-in set then stands in, so
    // the form is never held behind a call that describes only its options.
    final fetched = ref.watch(moduleCatalogProvider).valueOrNull;
    final catalog =
        (fetched == null || fetched.isEmpty) ? ModuleCatalog.builtIn : fetched;
    final scopes = catalog.offerableScopes;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
            title: _isEdit ? 'Edit role' : 'Add role',
            onClose: () => Navigator.of(context).pop()),
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
                  for (final s in scopes) _scopeChip(s),
                ],
              ),
              SizedBox(height: 16.h),
              Text('Capabilities',
                  style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
              if (_showErrors && !_capsOk) ...[
                SizedBox(height: 4.h),
                Text('Pick at least one',
                    style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.error)),
              ],
              SizedBox(height: 6.h),
              for (final g in catalog.groups) _capRow(g),
              SizedBox(height: 20.h),
              if (_locked) ...[
                Text(
                  'This is a built-in role, so it cannot be changed. Create a '
                  'custom role to grant a different set of capabilities.',
                  style: AppText.custom(
                      size: 12, weight: FontWeight.w500, color: AppColors.textMuted),
                ),
                SizedBox(height: 10.h),
              ],
              PrimaryButton(
                label: _saving
                    ? (_isEdit ? 'Saving…' : 'Creating…')
                    : (_isEdit ? 'Save changes' : 'Create role'),
                icon: PhosphorIconsBold.plus,
                height: 48,
                // Null greys the button out and makes it inert — the sheet is a
                // viewer for a seeded role.
                onTap: _locked ? null : _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _scopeChip(RoleVisibilityScope scope) {
    final s = scope.displayLabel;
    final on = _scope == scope.value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _scope = scope.value),
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

  /// One capability card. A `coming_soon` group is shown but not selectable —
  /// the server rejects a grant for one outright (`roles.md` §3).
  Widget _capRow(RoleModuleGroup group) {
    final locked = group.comingSoon;
    final on = !locked && _groups.contains(group.key);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: locked
          ? () => ref
              .read(toastProvider.notifier)
              .show('${group.label} is not available yet')
          : () => setState(
              () => on ? _groups.remove(group.key) : _groups.add(group.key)),
      child: Opacity(
        opacity: locked ? 0.45 : 1,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 9.h),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(group.label,
                              style: AppText.custom(
                                  size: 13.5,
                                  weight: on ? FontWeight.w600 : FontWeight.w500,
                                  color: on ? AppColors.textPrimary : AppColors.textLabelAlt)),
                        ),
                        if (locked) ...[
                          SizedBox(width: 6.w),
                          Icon(PhosphorIconsRegular.lock,
                              size: 12.sp, color: AppColors.textPlaceholder),
                        ],
                      ],
                    ),
                    if (group.description.isNotEmpty) ...[
                      SizedBox(height: 2.h),
                      Text(group.description,
                          style: AppText.custom(
                              size: 11.5,
                              weight: FontWeight.w500,
                              color: AppColors.textPlaceholder)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
