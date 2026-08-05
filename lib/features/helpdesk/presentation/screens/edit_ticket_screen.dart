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
import '../components/ticket_form_fields.dart';
import '../util/ticket_sla.dart';

/// Edit ticket — prefilled, Lead-form section layout. Shows an SLA-recalc note
/// when Priority/Customer changes and confirms before discarding edits on close.
class EditTicketScreen extends ConsumerStatefulWidget {
  const EditTicketScreen({super.key});

  @override
  ConsumerState<EditTicketScreen> createState() => _EditTicketScreenState();
}

class _EditTicketScreenState extends ConsumerState<EditTicketScreen> {
  final _subjectCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  bool _prefilled = false;
  String _id = '';
  String? _custId;
  String? _origCust;
  String _channel = 'Phone';
  String _cat = 'Complaint';
  String _pri = 'Medium';
  String _origPri = 'Medium';
  String? _product;
  String? _projId;
  bool _subjErr = false;
  bool _dirty = false;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _descCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  void _prefill() {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final t = ref.read(ticketByIdProvider(id));
    if (t == null) return;
    _id = t.id;
    _subjectCtrl.text = t.subject;
    _descCtrl.text = t.desc;
    _contactCtrl.text = t.contact;
    _custId = t.custId;
    _origCust = t.custId;
    _channel = t.channel;
    _cat = _normalizeCat(t.cat);
    _pri = t.pri;
    _origPri = t.pri;
    _product = t.product;
    _projId = t.projId;
    _prefilled = true;
  }

  // The edit form's category vocabulary is Complaint / Request / Query.
  String _normalizeCat(String c) => const ['Complaint', 'Request', 'Query'].contains(c) ? c : 'Request';

  bool get _slaNote => _pri != _origPri || _custId != _origCust;

  @override
  Widget build(BuildContext context) {
    if (!_prefilled) _prefill();
    final dir = ref.watch(ticketDirectoryProvider);
    final cust = dir.customer(_custId);

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Container(
        color: AppColors.bgDetail,
        child: Column(
          children: [
            _header(),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 20.h),
                children: [
                  _section('Basics'),
                  AppTextField(
                    label: 'Subject',
                    required: true,
                    controller: _subjectCtrl,
                    hint: 'What is the issue?',
                    errorText: _subjErr ? 'Please enter the ticket subject' : null,
                    onChanged: (_) => setState(() {
                      _dirty = true;
                      _subjErr = false;
                    }),
                  ),
                  SizedBox(height: 14.h),
                  AppTextField(
                    label: 'Description',
                    controller: _descCtrl,
                    hint: 'Describe the issue…',
                    multiline: true,
                    onChanged: (_) => _dirty = true,
                  ),
                  _section('Requester'),
                  TicketFieldLabel('Requester customer', required: true),
                  SizedBox(height: 7.h),
                  TicketPickerRow(
                    label: cust?.display ?? 'Select customer…',
                    placeholder: cust == null,
                    icon: PhosphorIconsBold.caretRight,
                    onTap: _pickCustomer,
                  ),
                  SizedBox(height: 14.h),
                  AppTextField(
                    label: 'Contact person',
                    controller: _contactCtrl,
                    hint: 'Who reported this?',
                    onChanged: (_) => _dirty = true,
                  ),
                  SizedBox(height: 14.h),
                  TicketFieldLabel('Channel'),
                  SizedBox(height: 7.h),
                  TicketChipWrap(
                    options: const ['Phone', 'WhatsApp', 'Email', 'Walk-in'],
                    selected: _channel,
                    onSelect: (v) => setState(() {
                      _channel = v;
                      _dirty = true;
                    }),
                  ),
                  _section('Classification'),
                  TicketFieldLabel('Category'),
                  SizedBox(height: 7.h),
                  TicketChipWrap(
                    options: const ['Complaint', 'Request', 'Query'],
                    selected: _cat,
                    onSelect: (v) => setState(() {
                      _cat = v;
                      _dirty = true;
                    }),
                  ),
                  SizedBox(height: 14.h),
                  TicketFieldLabel('Priority'),
                  SizedBox(height: 7.h),
                  TicketChipWrap(
                    options: const ['Urgent', 'High', 'Medium', 'Low'],
                    selected: _pri,
                    dotColor: ticketPriDotColor,
                    onSelect: (v) => setState(() {
                      _pri = v;
                      _dirty = true;
                    }),
                  ),
                  if (_slaNote) ...[
                    SizedBox(height: 14.h),
                    _slaRecalcNote(),
                  ],
                  SizedBox(height: 14.h),
                  TicketFieldLabel('Product or service'),
                  SizedBox(height: 7.h),
                  TicketPickerRow(
                    label: _product ?? 'Select product…',
                    placeholder: _product == null,
                    icon: PhosphorIconsBold.caretRight,
                    onTap: () => ref.read(toastProvider.notifier).show('Product picker'),
                  ),
                  SizedBox(height: 14.h),
                  TicketFieldLabel('Related project'),
                  SizedBox(height: 7.h),
                  TicketPickerRow(
                    label: dir.project(_projId)?.name ?? 'No project linked',
                    placeholder: _projId == null,
                    icon: PhosphorIconsBold.caretRight,
                    onTap: () => ref.read(toastProvider.notifier).show('Project picker'),
                  ),
                ],
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      color: AppColors.white,
      padding: EdgeInsets.fromLTRB(16.w, 54.h, 16.w, 14.h),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderCardSoft))),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: Container(
              width: 38.w,
              height: 38.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(11.r),
                border: Border.all(color: AppColors.borderCard),
              ),
              child: Icon(PhosphorIconsBold.caretLeft, size: 17.sp, color: AppColors.textBody),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Edit ticket', style: AppText.custom(size: 19, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                Text('$_id · changes apply on save', style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: EdgeInsets.fromLTRB(2.w, 22.h, 2.w, 12.h),
      child: Text(title.toUpperCase(),
          style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
    );
  }

  Widget _slaRecalcNote() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 11.h),
      decoration: BoxDecoration(color: AppColors.tintAmber, borderRadius: BorderRadius.circular(11.r)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsFill.timer, size: 14.sp, color: AppColors.warningDeep),
          SizedBox(width: 8.w),
          Expanded(
            child: Text('SLA targets will be recalculated.',
                style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.warningDeep).copyWith(height: 1.45)),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      color: AppColors.white,
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 22.h),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderCardSoft))),
      child: Row(
        children: [
          GestureDetector(
            onTap: _close,
            child: Container(
              width: 100.w,
              height: 48.h,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: AppColors.borderCard),
              ),
              child: Text('Cancel', style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: GestureDetector(
              onTap: _save,
              child: Container(
                height: 48.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(12.r)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsBold.check, size: 16.sp, color: AppColors.white),
                    SizedBox(width: 8.w),
                    Text('Save changes', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.white)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_subjectCtrl.text.trim().isEmpty) {
      setState(() => _subjErr = true);
      ref.read(toastProvider.notifier).show('Subject is required');
      return;
    }
    if (ApiConfig.apiEnabled) {
      try {
        await ref.read(ticketsRepositoryProvider).updateTicket(_id, {
          'subject': _subjectCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'priority': _pri,
        });
        ref.invalidate(ticketsProvider);
      } on AppError catch (e) {
        if (mounted) ref.read(toastProvider.notifier).show(e.message);
        return;
      }
      if (!mounted) return;
    }
    _dirty = false;
    ref.read(toastProvider.notifier).show('Ticket updated');
    context.pop();
  }

  void _close() {
    if (_dirty) {
      _confirmDiscard();
    } else {
      context.pop();
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await showClozrSheet<bool>(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(18.w, 6.h, 18.w, 26.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetHeader(title: 'Discard changes?'),
            SizedBox(height: 4.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 2.w),
              child: Text('Your edits to this ticket will be lost.',
                  style: AppText.body(color: AppColors.textMuted)),
            ),
            SizedBox(height: 18.h),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(false),
                    child: Container(
                      height: 48.h,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: AppColors.borderCard),
                      ),
                      child: Text('Keep editing', style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(true),
                    child: Container(
                      height: 48.h,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(12.r)),
                      child: Text('Discard', style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (discard == true && mounted) {
      _dirty = false;
      context.pop();
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
            SheetHeader(title: 'Requester customer'),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.symmetric(horizontal: 18.w),
                children: [
                  for (final c in ref.read(ticketDirectoryProvider).customers.values)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() {
                          _custId = c.id;
                          _dirty = true;
                        });
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
}
