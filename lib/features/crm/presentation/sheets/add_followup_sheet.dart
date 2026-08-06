import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/filters/followups_filter_spec.dart';
import '../../application/providers/crm_catalog_providers.dart';
import '../../application/providers/followups_providers.dart';
import '../../domain/entities/followup.dart';
import '../../domain/entities/lead.dart';
import 'add_sheet_kit.dart';

/// Add follow-up — a focused-but-faithful port of the prototype's `addFollowup`
/// sheet. On submit the new follow-up is prepended to [followupDraftsProvider]
/// so it appears immediately in the list, then a toast confirms.
///
/// Pass [lead] when opening from a lead's Follow-ups tab: company and contact
/// are prefilled from it, and the created follow-up carries `related_to=lead`
/// so it comes back in that lead's scoped fetch.
Future<void> showAddFollowupSheet(BuildContext context, WidgetRef ref,
    {Lead? lead}) {
  return showClozrSheet<void>(
    context: context,
    builder: (_) => _AddFollowupSheet(ref: ref, lead: lead),
  );
}

class _AddFollowupSheet extends StatefulWidget {
  const _AddFollowupSheet({required this.ref, this.lead});
  final WidgetRef ref;

  /// The lead this follow-up is being scheduled against, when opened from one.
  final Lead? lead;

  @override
  State<_AddFollowupSheet> createState() => _AddFollowupSheetState();
}

class _AddFollowupSheetState extends State<_AddFollowupSheet> {
  final _company = TextEditingController();
  final _contact = TextEditingController();
  final _date = TextEditingController();
  final _time = TextEditingController();
  final _note = TextEditingController();
  String _kind = 'Call';
  bool _showErrors = false;

  /// The org's own follow-up types, falling back to the built-in vocabulary
  /// before the catalog loads. `task_type` is submitted as the type **name**,
  /// so offering a type this org does not have would be rejected on save.
  ///
  /// Read rather than watched so it is valid from the submit callback too; the
  /// build below watches the catalog to keep the chips fresh.
  List<String> get _kinds {
    final catalog = widget.ref.read(followupTypeOptionsProvider);
    return catalog.isNotEmpty
        ? [for (final t in catalog) t.name]
        : kBuiltinFollowupTypes;
  }

  /// The chosen type, corrected to one this org actually has — the default
  /// ('Call') is a guess until the catalog says otherwise.
  String get _selectedKind {
    final kinds = _kinds;
    if (kinds.isEmpty || kinds.contains(_kind)) return _kind;
    return kinds.first;
  }

  @override
  void initState() {
    super.initState();
    // Prefilled, not locked — the lead's name is the likely contact, but the
    // person you are actually following up with may be someone else there.
    final lead = widget.lead;
    if (lead != null) {
      _contact.text = lead.name;
      _company.text = lead.company ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [_company, _contact, _date, _time, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _contactOk => _contact.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() => _showErrors = true);
    if (!_contactOk) {
      widget.ref.read(toastProvider.notifier).show('Enter a contact name');
      return;
    }
    final lead = widget.lead;
    if (ApiConfig.apiEnabled) {
      try {
        await widget.ref.read(followupsRepositoryProvider).createFollowup({
          'title': _contact.text.trim(),
          'task_type': _selectedKind,
          'due_date': _date.text.trim(),
          'due_time': _time.text.trim(),
          'description': _note.text.trim(),
          if (lead != null) 'related_to': 'lead',
          if (lead != null) 'related_to_id': lead.id,
        });
      } on AppError catch (e) {
        widget.ref.read(toastProvider.notifier).show(e.message);
        return;
      }
      widget.ref.invalidate(followupsProvider);
      // Every lead's Follow-ups tab reads its own scoped fetch, so the org-wide
      // list alone going stale is not enough to refresh them.
      widget.ref.invalidate(leadFollowupsProvider);
      widget.ref.read(toastProvider.notifier).show('Follow-up scheduled');
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final contact = _contact.text.trim();
    final company = _company.text.trim();
    final fu = Followup(
      id: genId('F'),
      kind: _selectedKind,
      contact: contact,
      custId: null,
      leadId: lead?.id,
      company: company.isEmpty ? contact : company,
      due: _date.text.trim().isEmpty ? '09 Jul 2026' : _date.text.trim(),
      time: _time.text.trim().isEmpty ? '10:00' : _time.text.trim(),
      status: 'due',
      owner: 'me',
      agenda: _note.text.trim().isEmpty ? 'Follow-up' : _note.text.trim(),
    );
    final drafts = widget.ref.read(followupDraftsProvider);
    widget.ref.read(followupDraftsProvider.notifier).state = [fu, ...drafts];
    widget.ref.read(toastProvider.notifier).show('Follow-up scheduled');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Watched here so the type chips swap from the built-in list to the org's
    // own the moment the catalog resolves, even with the sheet already open.
    widget.ref.watch(followupTypeOptionsProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'New follow-up', onClose: () => Navigator.of(context).pop()),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 12.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.lead != null) ...[
                  LinkedLeadField(lead: widget.lead!),
                  SizedBox(height: 16.h),
                ],
                const SheetFieldLabel('Type'),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    for (final k in _kinds)
                      SelectChip(label: k, selected: _selectedKind == k, onTap: () => setState(() => _kind = k)),
                  ],
                ),
                SizedBox(height: 16.h),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: AppTextField(label: 'Company', controller: _company, hint: 'e.g. Kalyan Silks')),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: AppTextField(
                        label: 'Contact',
                        required: true,
                        controller: _contact,
                        hint: 'e.g. Sneha Kulkarni',
                        errorText: _showErrors && !_contactOk ? 'Enter a contact name' : null,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14.h),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: AppTextField(label: 'Date', controller: _date, hint: 'e.g. 22 Jun 2026')),
                    SizedBox(width: 10.w),
                    Expanded(child: AppTextField(label: 'Time', controller: _time, hint: '10:00')),
                  ],
                ),
                SizedBox(height: 14.h),
                AppTextField(label: 'Note', controller: _note, hint: "What's this follow-up about?"),
                SizedBox(height: 8.h),
                Text('Reminders need a due date.',
                    style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
              ],
            ),
          ),
        ),
        SheetSubmitBar(label: 'Add follow-up', icon: PhosphorIconsBold.plus, onTap: _submit),
      ],
    );
  }
}
