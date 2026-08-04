import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/customers_providers.dart';
import '../../domain/entities/customer.dart';
import 'add_sheet_kit.dart';

/// Add customer — a focused-but-faithful port of the prototype's `addCustomer`
/// sheet. On submit the new customer is prepended to [customerDraftsProvider]
/// so it appears immediately in the list, then a toast confirms.
Future<void> showAddCustomerSheet(BuildContext context, WidgetRef ref) {
  return showClozrSheet<void>(
    context: context,
    builder: (_) => _AddCustomerSheet(ref: ref),
  );
}

class _AddCustomerSheet extends StatefulWidget {
  const _AddCustomerSheet({required this.ref});
  final WidgetRef ref;

  @override
  State<_AddCustomerSheet> createState() => _AddCustomerSheetState();
}

class _AddCustomerSheetState extends State<_AddCustomerSheet> {
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _source = TextEditingController(text: 'Referral');
  final _value = TextEditingController();
  bool _showErrors = false;

  @override
  void dispose() {
    for (final c in [_name, _company, _phone, _email, _source, _value]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _nameOk => _name.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() => _showErrors = true);
    if (!_nameOk) {
      widget.ref.read(toastProvider.notifier).show('Enter a customer name');
      return;
    }
    final name = _name.text.trim();
    if (ApiConfig.apiEnabled) {
      try {
        await widget.ref.read(customersRepositoryProvider).createCustomer({
          'name': name,
          'organization_name': _company.text.trim(),
          'email': _email.text.trim(),
          'phone': _phone.text.trim(),
        });
        if (!mounted) return;
        widget.ref.invalidate(customersProvider);
        widget.ref.read(toastProvider.notifier).show('Customer added');
        Navigator.of(context).pop();
      } on AppError catch (e) {
        if (!mounted) return;
        widget.ref.read(toastProvider.notifier).show(e.message);
      }
      return;
    }
    final rawValue = _value.text.trim();
    final valueNum = int.tryParse(rawValue.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final cust = Customer(
      id: genId('C'),
      leadId: null,
      name: name,
      initials: initialsOf(name),
      company: _company.text.trim(),
      project: 'New engagement',
      value: rawValue.isEmpty ? '—' : rawValue,
      valueNum: valueNum,
      status: 'active',
      since: 'Jul 2026',
      statusDays: 0,
      score: 70,
      source: _source.text.trim().isEmpty ? 'Referral' : _source.text.trim(),
      owner: 'me',
      team: const ['me'],
      phone: _phone.text.trim().isEmpty ? '—' : _phone.text.trim(),
      email: _email.text.trim().isEmpty ? '—' : _email.text.trim(),
      website: '',
      industry: '—',
      location: '—',
      createdOn: '09 Jul 2026',
      time: 'Just now',
      lastFu: 'Customer created manually.',
      notif: 0,
    );
    final drafts = widget.ref.read(customerDraftsProvider);
    widget.ref.read(customerDraftsProvider.notifier).state = [cust, ...drafts];
    widget.ref.read(toastProvider.notifier).show('Customer added');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'New customer', onClose: () => Navigator.of(context).pop()),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 12.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: 'Customer name',
                  required: true,
                  controller: _name,
                  hint: 'e.g. Meera Nair',
                  errorText: _showErrors && !_nameOk ? 'Enter a customer name' : null,
                  onChanged: (_) => setState(() {}),
                ),
                SizedBox(height: 14.h),
                AppTextField(label: 'Company', controller: _company, hint: 'e.g. Meera Boutique'),
                SizedBox(height: 14.h),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppTextField(
                          label: 'Mobile',
                          controller: _phone,
                          hint: '+91 …',
                          keyboardType: TextInputType.phone),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: AppTextField(
                          label: 'Email',
                          controller: _email,
                          hint: 'name@company.in',
                          keyboardType: TextInputType.emailAddress),
                    ),
                  ],
                ),
                SizedBox(height: 14.h),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: AppTextField(label: 'Source', controller: _source, hint: 'Referral')),
                    SizedBox(width: 10.w),
                    Expanded(child: AppTextField(label: 'Deal value (₹)', controller: _value, hint: 'e.g. ₹12L')),
                  ],
                ),
              ],
            ),
          ),
        ),
        SheetSubmitBar(label: 'Create customer', icon: PhosphorIconsBold.plus, onTap: _submit),
      ],
    );
  }
}
