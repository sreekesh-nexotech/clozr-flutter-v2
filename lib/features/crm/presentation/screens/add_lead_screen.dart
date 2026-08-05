import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/leads_providers.dart';

/// Add lead — a grouped form (Contact / Deal / Qualification / Schedule /
/// Pipeline). Static submit validates name + phone, then toasts and pops.
class AddLeadScreen extends ConsumerStatefulWidget {
  const AddLeadScreen({super.key});

  @override
  ConsumerState<AddLeadScreen> createState() => _AddLeadScreenState();
}

class _AddLeadScreenState extends ConsumerState<AddLeadScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _company = TextEditingController();
  final _project = TextEditingController();
  final _value = TextEditingController();
  final _industry = TextEditingController();
  final _website = TextEditingController();
  final _employees = TextEditingController();
  final _revenue = TextEditingController();
  final _territory = TextEditingController();
  final _fitout = TextEditingController();
  final _nextFu = TextEditingController();
  final _expClose = TextEditingController();
  final _source = TextEditingController(text: 'Website');
  final _note = TextEditingController();

  String _owner = 'am';
  String _status = 'new';
  bool _showErrors = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _company, _project, _value, _industry, _website, _employees, _revenue, _territory, _fitout, _nextFu, _expClose, _source, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _nameOk => _name.text.trim().isNotEmpty;
  bool get _phoneOk => _phone.text.trim().length >= 6;
  bool get _projectOk => _project.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() => _showErrors = true);
    if (!_nameOk || !_phoneOk || !_projectOk) {
      ref.read(toastProvider.notifier).show('Please complete the required fields');
      return;
    }
    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show('Lead added');
      context.pop();
      return;
    }
    try {
      await ref.read(leadsRepositoryProvider).createLead({
        'lead_name': _name.text.trim(),
        'organization_name': _company.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'purpose': _project.text.trim(),
      });
      if (!mounted) return;
      ref.invalidate(leadsProvider);
      ref.read(toastProvider.notifier).show('Lead added');
      context.pop();
    } on AppError catch (e) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(e.message);
    }
  }

  void _pickOwner() {
    final roster = ref.read(rosterProvider);
    showClozrSheet<void>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: 'Assign to', onClose: () => Navigator.of(ctx).pop()),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(14.w, 4.h, 14.w, 28.h),
              children: [
                for (final r in roster)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() => _owner = r.id);
                      Navigator.of(ctx).pop();
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 6.w),
                      child: Row(
                        children: [
                          Container(
                            width: 38.w,
                            height: 38.w,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(11.r)),
                            child: Text(r.initials, style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.navy)),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.name, style: AppText.bodyStrong()),
                                SizedBox(height: 1.h),
                                Text(r.role, style: AppText.caption()),
                              ],
                            ),
                          ),
                          if (_owner == r.id) Icon(PhosphorIconsBold.check, size: 19.sp, color: AppColors.success),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(section: 'Add lead', onBack: () => context.pop()),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
              children: [
                FormSection(
                  title: 'Contact',
                  children: [
                    AppTextField(label: 'Full name', required: true, controller: _name, hint: 'e.g. Anagha Menon', errorText: _showErrors && !_nameOk ? "Please enter the contact's name" : null, onChanged: (_) => setState(() {})),
                    AppTextField(label: 'Phone', required: true, controller: _phone, hint: '+91 98470 00000', keyboardType: TextInputType.phone, errorText: _showErrors && !_phoneOk ? 'Enter a valid phone number' : null, onChanged: (_) => setState(() {})),
                    AppTextField(label: 'Email', controller: _email, hint: 'name@email.com', keyboardType: TextInputType.emailAddress),
                    AppTextField(label: 'Company', controller: _company, hint: 'e.g. Kalyan Silks'),
                  ],
                ),
                SizedBox(height: 22.h),
                FormSection(
                  title: 'Deal',
                  children: [
                    AppTextField(label: 'Product / Need', required: true, controller: _project, hint: 'e.g. Showroom interiors', errorText: _showErrors && !_projectOk ? 'Select the product or need' : null, onChanged: (_) => setState(() {})),
                    AppTextField(label: 'Deal value (₹)', controller: _value, hint: 'e.g. ₹36.5L or ₹1.2Cr'),
                    AppTextField(label: 'Industry', controller: _industry, hint: 'Select industry…'),
                    AppTextField(label: 'Website', controller: _website, hint: 'e.g. www.company.in'),
                  ],
                ),
                SizedBox(height: 22.h),
                FormSection(
                  title: 'Qualification',
                  children: [
                    AppTextField(label: 'Employees', controller: _employees, hint: 'Select employees…'),
                    AppTextField(label: 'Annual revenue', controller: _revenue, hint: 'Select annual revenue…'),
                    AppTextField(label: 'Territory', controller: _territory, hint: 'Select territory…'),
                    AppTextField(label: 'Fit-out type', controller: _fitout, hint: 'Select fit-out type…'),
                  ],
                ),
                SizedBox(height: 22.h),
                FormSection(
                  title: 'Schedule',
                  children: [
                    AppTextField(label: 'Next follow-up', controller: _nextFu, hint: 'e.g. 22 Jun 2026'),
                    AppTextField(label: 'Expected close', controller: _expClose, hint: 'e.g. 30 Aug 2026'),
                  ],
                ),
                SizedBox(height: 22.h),
                FormSection(
                  title: 'Pipeline',
                  children: [
                    AppTextField(label: 'Source', controller: _source, hint: 'e.g. Website'),
                    AppTextField(
                      label: 'Assign to',
                      readOnly: true,
                      onTap: _pickOwner,
                      value: MockUsers.of(_owner).name,
                    ),
                    _statusPicker(),
                    AppTextField(label: 'First note', controller: _note, hint: 'Add context about this enquiry…', multiline: true),
                  ],
                ),
              ],
            ),
          ),
          StickyActionBar(
            children: [
              PrimaryButton(label: 'Cancel', ghost: true, expand: false, height: 48, onTap: () => context.pop()),
              SizedBox(width: 10.w),
              Expanded(
                child: PrimaryButton(label: 'Add lead', icon: PhosphorIconsBold.check, height: 48, onTap: _submit),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusPicker() {
    const keys = ['new', 'qualified', 'quote', 'negotiation', 'won'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Status', style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
        SizedBox(height: 8.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            for (final k in keys)
              GestureDetector(
                onTap: () => setState(() => _status = k),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: _status == k ? AppColors.blueSubtle : AppColors.white,
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(
                      color: _status == k ? const Color(0xFFA6D1FF) : const Color(0xFFE6E7EA),
                      width: _status == k ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 9.w, height: 9.w, decoration: BoxDecoration(color: StatusMeta$.lead[k]!.color, shape: BoxShape.circle)),
                      SizedBox(width: 7.w),
                      Text(StatusMeta$.lead[k]!.label,
                          style: AppText.custom(
                            size: 13,
                            weight: _status == k ? FontWeight.w700 : FontWeight.w500,
                            color: _status == k ? AppColors.navy : AppColors.textLabelAlt,
                          )),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
