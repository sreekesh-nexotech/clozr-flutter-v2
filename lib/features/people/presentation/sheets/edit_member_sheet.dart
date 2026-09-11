import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/phone_rules.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/phone_controller.dart';
import '../../../../core/widgets/phone_input_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/people_providers.dart';
import '../../domain/entities/member.dart';

/// Edit member — `PATCH /management/users/{user_id}/` (`members.md` §Edit
/// member).
///
/// Deliberately **partial**: only fields the user actually changed are sent, so
/// an untouched value is never rewritten with a stale copy of itself. That also
/// keeps two documented side effects from firing by accident — `role_id`
/// replaces the member's role, and `manager_id` rewrites the hierarchy subtree.
Future<void> showEditMemberSheet(BuildContext context, Member member) {
  return showClozrSheet<void>(
    context: context,
    builder: (_) => _EditMemberSheet(member: member),
  );
}

class _EditMemberSheet extends ConsumerStatefulWidget {
  const _EditMemberSheet({required this.member});

  final Member member;

  @override
  ConsumerState<_EditMemberSheet> createState() => _EditMemberSheetState();
}

class _EditMemberSheetState extends ConsumerState<_EditMemberSheet> {
  late final _name = TextEditingController(text: widget.member.name);
  late final _email = TextEditingController(text: widget.member.email);

  /// Stored E.164 (`+919847011001`); split into the member's own country +
  /// national digits.
  late final _phone = PhoneController(initialE164: widget.member.phone);

  late String _role = widget.member.role;
  late String _managerId = widget.member.managerId;

  bool _showErrors = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _nameOk => _name.text.trim().isNotEmpty;
  bool get _emailOk => _email.text.trim().contains('@');
  bool get _phoneOk => _phone.isBlank || _phone.isComplete;

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _showErrors = true);
    final toast = ref.read(toastProvider.notifier);
    if (!_nameOk) return toast.show('Enter a full name');
    if (!_emailOk) return toast.show('Enter a valid email');
    if (!_phoneOk) return toast.show(phoneDigitsMessage(_phone.rule));

    final m = widget.member;
    final name = _name.text.trim();
    final email = _email.text.trim();
    final phone = _phone.toE164() ?? '';

    // Only what changed. Sending the whole form would rewrite a role and a
    // manager the user never touched — and `manager_id` recalculates the
    // reporting subtree, so that is not a harmless no-op.
    final roles = ref.read(rolesProvider).valueOrNull ?? const [];
    final roleId = _role == m.role
        ? null
        : roles.where((r) => r.name == _role).map((r) => r.id).firstOrNull;

    if (!ApiConfig.apiEnabled) {
      Navigator.of(context).pop();
      toast.show('Member updated');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(peopleRepositoryProvider).updateMember(
            m.id,
            name: name == m.name ? null : name,
            email: email == m.email ? null : email,
            phone: phone == m.phone ? null : phone,
            roleId: roleId,
            managerId: _managerId == m.managerId ? null : _managerId,
          );
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      // A duplicate email is a 400 on the `email` key — the server's message is
      // the only thing that says which field was refused.
      toast.showError(e.message);
      return;
    }
    if (!mounted) return;
    ref.invalidate(membersProvider);
    ref.invalidate(memberDetailProvider(m.id));
    // A role's card shows the count of members holding it, and the delete
    // guard on Roles & Permissions is keyed off that same stale count — leave
    // it uninvalidated and a role just vacated here still reports its old
    // occupant and refuses to delete.
    if (roleId != null) ref.invalidate(rolesProvider);
    Navigator.of(context).pop();
    toast.show('Member updated');
  }

  @override
  Widget build(BuildContext context) {
    final roles = ref.watch(rolesProvider).valueOrNull ?? const [];
    final roleOpts = [for (final r in roles) (r.name, r.name)];

    // Any org user can be a manager, keyed by `user_id` — what `manager_id`
    // takes. The member cannot report to themselves.
    final members = ref.watch(membersProvider).valueOrNull ?? const [];
    final managerOpts = <(String, String)>[
      ('', 'No manager'),
      for (final m in members)
        if (m.id != widget.member.id) (m.id, m.name),
    ];
    final managerLabel = _managerId.isEmpty
        ? 'No manager'
        : members.where((m) => m.id == _managerId).map((m) => m.name).firstOrNull ??
            widget.member.reportsTo;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'Edit member', onClose: () => Navigator.of(context).pop()),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 18.h),
            children: [
              AppTextField(
                label: 'Full name',
                required: true,
                controller: _name,
                errorText: _showErrors && !_nameOk ? 'Enter a full name' : null,
                onChanged: (_) => setState(() {}),
              ),
              SizedBox(height: 14.h),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'Email',
                      required: true,
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      errorText: _showErrors && !_emailOk ? 'Enter an email' : null,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: PhoneInputField(
                      label: 'Phone',
                      controller: _phone,
                      errorText: _showErrors && !_phoneOk ? phoneDigitsMessage(_phone.rule) : null,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14.h),
              AppTextField(
                label: 'Role',
                readOnly: true,
                value: _role,
                onTap: roleOpts.isEmpty
                    ? null
                    : () => _pickOne(
                          title: 'Role',
                          options: roleOpts,
                          current: _role,
                          onPick: (v) => setState(() => _role = v),
                        ),
              ),
              SizedBox(height: 6.h),
              _hint('Changing the role replaces the member’s current one.'),
              SizedBox(height: 14.h),
              AppTextField(
                label: 'Reporting manager',
                readOnly: true,
                value: managerLabel,
                onTap: () => _pickOne(
                  title: 'Reporting manager',
                  options: managerOpts,
                  current: _managerId,
                  onPick: (v) => setState(() => _managerId = v),
                ),
              ),
              SizedBox(height: 6.h),
              _hint('Moving a manager re-parents everyone reporting to them.'),
              SizedBox(height: 20.h),
              PrimaryButton(
                label: _saving ? 'Saving…' : 'Save changes',
                icon: PhosphorIconsBold.check,
                height: 48,
                onTap: _saving ? null : _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _hint(String text) => Text(text,
      style: AppText.custom(
          size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder));

  void _pickOne({
    required String title,
    required List<(String, String)> options,
    required String current,
    required ValueChanged<String> onPick,
  }) {
    showClozrSheet<void>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(title: title, onClose: () => Navigator.of(ctx).pop()),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 26.h),
              child: Column(
                children: [
                  for (final (value, label) in options)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        onPick(value);
                        Navigator.of(ctx).pop();
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 14.h),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: AppColors.bgLight)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(label,
                                  style: AppText.custom(
                                      size: 15,
                                      weight: FontWeight.w600,
                                      color: AppColors.textBody)),
                            ),
                            if (current == value)
                              Icon(PhosphorIconsBold.check,
                                  size: 17.sp, color: AppColors.success),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
