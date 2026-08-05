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
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/tickets_providers.dart';
import '../../infrastructure/data_sources/local/tickets_mock_ds.dart';
import '../components/ticket_form_fields.dart';

/// New ticket — full-screen form. Chips are functional; the customer picker is a
/// real sheet so the required field is satisfiable; other pickers toast.
class CreateTicketScreen extends ConsumerStatefulWidget {
  const CreateTicketScreen({super.key});

  @override
  ConsumerState<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends ConsumerState<CreateTicketScreen> {
  final _subjectCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _custId;
  String _channel = 'Phone';
  String _cat = 'Complaint';
  String _pri = 'Medium';
  final Set<String> _assignees = {'me'};
  String? _product;
  String? _projId;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  bool get _valid => _subjectCtrl.text.trim().isNotEmpty && _custId != null;

  @override
  Widget build(BuildContext context) {
    final sla = TicketDirectory.sla[_pri] ?? TicketDirectory.sla['Medium']!;
    final dir = ref.watch(ticketDirectoryProvider);
    final cust = dir.customer(_custId);

    return Container(
      color: AppColors.bgApp,
      child: Column(
        children: [
          _formHeader(context, 'New Ticket', () => context.pop()),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 24.h),
              children: [
                AppTextField(
                  label: 'Subject',
                  required: true,
                  controller: _subjectCtrl,
                  hint: 'Summarize the issue…',
                  onChanged: (_) => setState(() {}),
                ),
                SizedBox(height: 14.h),
                TicketFieldLabel('Customer', required: true),
                SizedBox(height: 7.h),
                TicketPickerRow(
                  label: cust?.display ?? 'Select customer…',
                  placeholder: cust == null,
                  icon: PhosphorIconsRegular.magnifyingGlass,
                  onTap: _pickCustomer,
                ),
                SizedBox(height: 14.h),
                TicketFieldLabel('Contact'),
                SizedBox(height: 7.h),
                TicketPickerRow(
                  label: cust?.name ?? 'Pick a customer first',
                  placeholder: cust == null,
                  icon: PhosphorIconsBold.caretDown,
                  onTap: () => ref.read(toastProvider.notifier).show('Contact — from customer record'),
                ),
                SizedBox(height: 14.h),
                TicketFieldLabel('Channel'),
                SizedBox(height: 7.h),
                TicketChipWrap(
                  options: const ['Phone', 'Email', 'WhatsApp', 'Walk-in'],
                  selected: _channel,
                  onSelect: (v) => setState(() => _channel = v),
                ),
                SizedBox(height: 14.h),
                TicketFieldLabel('Category'),
                SizedBox(height: 7.h),
                TicketChipWrap(
                  options: const ['Complaint', 'Service Request', 'Question', 'Feedback'],
                  selected: _cat,
                  onSelect: (v) => setState(() => _cat = v),
                ),
                SizedBox(height: 14.h),
                TicketFieldLabel('Priority'),
                SizedBox(height: 7.h),
                TicketChipWrap(
                  options: const ['High', 'Medium', 'Low'],
                  selected: _pri,
                  onSelect: (v) => setState(() => _pri = v),
                ),
                SizedBox(height: 10.h),
                _slaInfo('Default SLA · Respond in ${sla.lineResp} · Resolve in ${sla.lineRes}'),
                SizedBox(height: 16.h),
                TicketFieldLabel('Assignees'),
                SizedBox(height: 7.h),
                TicketAssigneeWrap(
                  selected: _assignees,
                  onToggle: (id) => setState(() => _assignees.contains(id) ? _assignees.remove(id) : _assignees.add(id)),
                ),
                SizedBox(height: 14.h),
                TicketFieldLabel('Product or service'),
                SizedBox(height: 7.h),
                TicketPickerRow(
                  label: _product ?? 'Select (optional)…',
                  placeholder: _product == null,
                  icon: PhosphorIconsRegular.magnifyingGlass,
                  onTap: () => ref.read(toastProvider.notifier).show('Product picker'),
                ),
                SizedBox(height: 14.h),
                TicketFieldLabel('Related project'),
                SizedBox(height: 7.h),
                TicketPickerRow(
                  label: dir.project(_projId)?.name ?? 'Select (optional)…',
                  placeholder: _projId == null,
                  icon: PhosphorIconsRegular.magnifyingGlass,
                  onTap: () => ref.read(toastProvider.notifier).show('Project picker'),
                ),
                SizedBox(height: 14.h),
                AppTextField(
                  label: 'Description',
                  controller: _descCtrl,
                  hint: 'Describe the issue…',
                  multiline: true,
                ),
              ],
            ),
          ),
          _cta('Create Ticket', PhosphorIconsBold.plus, _valid, _submit),
        ],
      ),
    );
  }

  /// Mock mode keeps the original toast-and-pop; API mode persists the ticket
  /// and refreshes the list before popping.
  Future<void> _submit() async {
    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show('Ticket created');
      context.pop();
      return;
    }
    try {
      await ref.read(ticketsRepositoryProvider).createTicket({
        'subject': _subjectCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'priority': _pri,
        'channel': _channel,
        'category': _cat,
        if (_custId != null) 'customer_id': _custId,
      });
      ref.invalidate(ticketsProvider);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Ticket created');
      context.pop();
    } on AppError catch (e) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(e.message);
    }
  }

  Future<void> _pickCustomer() async {
    await showClozrSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: 24.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title: 'Select customer'),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.symmetric(horizontal: 18.w),
                children: [
                  for (final c in ref.read(ticketDirectoryProvider).customers.values)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() => _custId = c.id);
                        Navigator.of(ctx).pop();
                      },
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 11.h),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.company, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                                  SizedBox(height: 1.h),
                                  Text(c.name, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                                ],
                              ),
                            ),
                            if (_custId == c.id) Icon(PhosphorIconsBold.check, size: 16.sp, color: AppColors.blueBright),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slaInfo(String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 11.h),
      decoration: BoxDecoration(color: AppColors.bgScreen, borderRadius: BorderRadius.circular(11.r)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsRegular.info, size: 15.sp, color: AppColors.blueBright),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.navyMid)),
                SizedBox(height: 2.h),
                Text('A customer or project SLA overrides the default when configured.',
                    style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textMuted2).copyWith(height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _formHeader(BuildContext context, String title, VoidCallback onClose) {
    return Container(
      color: AppColors.bgApp,
      padding: EdgeInsets.fromLTRB(16.w, 54.h, 16.w, 12.h),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderCardSoft))),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: Padding(
              padding: EdgeInsets.only(right: 12.w),
              child: Icon(PhosphorIconsBold.x, size: 20.sp, color: AppColors.textPrimary),
            ),
          ),
          Text(title, style: AppText.custom(size: 20, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
        ],
      ),
    );
  }

  Widget _cta(String label, IconData icon, bool enabled, VoidCallback onTap) {
    return Container(
      padding: EdgeInsets.fromLTRB(18.w, 12.h, 18.w, 26.h),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderCardSoft))),
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          height: 52.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? AppColors.navy : AppColors.navy.withOpacity(0.4),
            borderRadius: BorderRadius.circular(14.r),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15.sp, color: AppColors.white),
              SizedBox(width: 8.w),
              Text(label, style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.white)),
            ],
          ),
        ),
      ),
    );
  }
}
