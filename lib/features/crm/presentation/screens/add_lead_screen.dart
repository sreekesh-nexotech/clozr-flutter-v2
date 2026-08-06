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
import '../../domain/entities/lead.dart';
import '../../infrastructure/data_sources/remote/leads_remote_ds.dart';

/// Add lead — a grouped form (Contact / Deal / Qualification / Schedule /
/// Pipeline). Static submit validates name + phone, then toasts and pops.
///
/// Doubles as **Edit lead** when opened with `?id=<lead_id>` (from the lead
/// detail screen's overflow menu and its sticky-bar edit affordance): the form
/// prefills from the record and saves with `PATCH` instead of creating a
/// second lead.
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

  /// True while a save is in flight, so the button can't be double-tapped into
  /// two writes.
  bool _saving = false;

  /// Whether the record has been copied into the fields yet. One-shot, so a
  /// late-arriving detail fetch never overwrites what the user has typed.
  bool _prefilled = false;

  /// The lead being edited — empty for the Add case.
  String get _editingId =>
      GoRouterState.of(context).uri.queryParameters['id'] ?? '';

  /// Copies the record into the form, once.
  ///
  /// Runs from build rather than initState because the lead comes from a
  /// provider that may still be loading, and the route's query parameters are
  /// not readable until the widget is in the tree.
  void _prefillFrom(Lead? lead) {
    if (_prefilled || lead == null) return;
    _prefilled = true;
    _name.text = lead.name;
    _phone.text = lead.phone;
    _email.text = lead.email;
    _company.text = lead.company ?? '';
    _project.text = lead.project;
    _value.text = lead.value == '—' ? '' : lead.value;
    _industry.text = lead.industry;
    _website.text = lead.website;
    _territory.text = lead.territory;
    _source.text = lead.source;
    _owner = lead.owner;
    _status = lead.status;
    // Painting is already under way; defer the rebuild past this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

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
    if (_saving) return;
    setState(() => _showErrors = true);
    if (!_nameOk || !_phoneOk || !_projectOk) {
      ref.read(toastProvider.notifier).show('Please complete the required fields');
      return;
    }

    final editingId = _editingId;
    final editing = editingId.isNotEmpty;
    final done = editing ? 'Lead updated' : 'Lead added';

    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show(done);
      context.pop();
      return;
    }

    // One field map for both paths, so create and update can never disagree
    // about what a field is called.
    final fields = LeadsRemoteDataSource.leadWriteFields(
      name: _name.text,
      company: _company.text,
      email: _email.text,
      phone: _phone.text,
      website: _website.text,
    );

    setState(() => _saving = true);
    try {
      final repo = ref.read(leadsRepositoryProvider);
      if (editing) {
        await repo.updateLead(editingId, fields);
      } else {
        await repo.createLead(fields);
      }
      if (!mounted) return;
      // Both ownership scopes can contain the lead — refresh either view.
      ref.invalidate(leadsScopedProvider);
      // An edit also moves the record the detail screen is showing behind us.
      if (editing) ref.invalidate(leadDetailProvider(editingId));
      ref.read(toastProvider.notifier).show(done);
      context.pop();
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
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
    final editingId = _editingId;
    if (editingId.isNotEmpty) {
      // The record is authoritative (it carries email, mobile, website and
      // territory); the list row stands in until it lands so the form is never
      // blank behind a spinner.
      _prefillFrom(ref.watch(leadDetailProvider(editingId)).valueOrNull ??
          ref.watch(leadByIdProvider(editingId)));
    }
    final editing = editingId.isNotEmpty;

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
              section: editing ? 'Edit lead' : 'Add lead',
              onBack: () => context.pop()),
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
                child: PrimaryButton(
                  label: _saving
                      ? 'Saving…'
                      : (editing ? 'Save changes' : 'Add lead'),
                  icon: PhosphorIconsBold.check,
                  height: 48,
                  onTap: _submit,
                ),
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
