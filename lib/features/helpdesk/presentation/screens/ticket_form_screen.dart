import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../accounting/presentation/components/acc_widgets.dart';
import '../../../auth/application/providers/module_perm_providers.dart';
import '../../../auth/presentation/components/permission_guard.dart';
import '../../../crm/application/providers/products_providers.dart';
import '../../../crm/domain/entities/crm_catalog.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/ticket_form_providers.dart';
import '../../application/providers/tickets_providers.dart';
import '../../application/ticket_form_rules.dart';
import '../../domain/entities/ticket.dart';
import '../../infrastructure/data_sources/remote/ticket_form_remote_ds.dart';
import '../components/ticket_form_fields.dart';
import '../util/ticket_errors.dart';
import '../util/ticket_sla.dart';

/// New Ticket / Edit Ticket — the webapp's `TicketFormScreen` on a phone:
/// "Ticket Information" (subject, description, reported for, searched
/// customer, contact, channel, category, product, project, billing) and
/// "Ticket Settings" (status, priority, assignee, SLA box). Validation errors
/// are listed in a box above the form, like the webapp's.
class TicketFormScreen extends ConsumerStatefulWidget {
  const TicketFormScreen({super.key, this.editId});

  /// The `issue_id` being edited; null for a new ticket.
  final String? editId;

  @override
  ConsumerState<TicketFormScreen> createState() => _TicketFormScreenState();
}

class _TicketFormScreenState extends ConsumerState<TicketFormScreen> {
  final _scroll = ScrollController();
  final _subjectCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  String _reportedFor = kReportedForClient;
  String? _custId;
  String _custLabel = '';
  String? _contactId;
  String? _contactLabel;
  String _channel = 'phone';
  String? _typeId;
  String? _productId;
  String? _productName;
  String? _projId;
  String? _projName;
  String _statusId = '';
  String _priority = kDefaultTicketPriority;

  /// A priority the user chose is never moved by a category change; an
  /// existing ticket's counts as chosen.
  bool _priorityPicked = false;
  String? _assigneeId;
  String? _assigneeName;
  bool _billable = false;
  String? _billableProductId;
  String? _billableProductName;

  /// Edit only: the ticket as loaded, its customer, and whether it is billed.
  Ticket? _ticket;
  String? _savedCustId;
  bool _billed = false;

  bool _seeded = false;
  bool _dirty = false;
  bool _saving = false;
  List<String> _errors = const [];

  bool get _isEditing => widget.editId != null;
  bool get _internal => _reportedFor == kReportedForInternal;

  @override
  void dispose() {
    _scroll.dispose();
    _subjectCtrl.dispose();
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  void _touch(VoidCallback change) => setState(() {
        change();
        _dirty = true;
      });

  /// Edit: seed every field from the loaded ticket, once.
  void _seed(Ticket t) {
    final f = t.facts;
    _ticket = t;
    _subjectCtrl.text = t.subject;
    _descCtrl.text = t.desc;
    _reportedFor = f?.reportedFor ?? kReportedForClient;
    _custId = t.custId.isEmpty ? null : t.custId;
    _savedCustId = _custId;
    _custLabel = f?.customerName ?? ref.read(ticketDirectoryProvider).customer(_custId)?.display ?? '';
    _contactId = f?.contactId;
    _contactLabel = f?.contactName;
    _channel = t.channel.toLowerCase().replaceAll('-', '');
    _typeId = t.typeId.isEmpty ? null : t.typeId;
    _productId = t.productId;
    _productName = t.product;
    _projId = t.projId;
    _projName = t.projName;
    _statusId = t.statusId;
    _priority = _orgPriority(t.priorityName.isNotEmpty ? t.priorityName : t.pri);
    _priorityPicked = true;
    _assigneeId = f?.assignedToId;
    _assigneeName = f?.assignedToName;
    _billable = t.billable;
    _amountCtrl.text = t.billableAmount ?? '';
    _billableProductId = t.billableProductId;
    _billed = t.isBilled;
    _seeded = true;
  }

  /// The org vocabulary (`Critical`) for a stored or display priority.
  static String _orgPriority(String p) {
    final n = p.toLowerCase();
    if (n.startsWith('crit') || n.startsWith('urg')) return 'Critical';
    if (n.startsWith('hi')) return 'High';
    if (n.startsWith('lo')) return 'Low';
    return 'Medium';
  }

  @override
  Widget build(BuildContext context) {
    final perm = ref.watch(modulePermProvider('issue'));
    final canSave = _isEditing ? perm.update : perm.create;
    final types = ref.watch(ticketTypeOptionsProvider);
    final statuses = ref.watch(ticketStatusOptionsProvider);

    if (_isEditing && !_seeded) {
      final detail = ApiConfig.apiEnabled ? ref.watch(ticketDetailProvider(widget.editId!)) : null;
      final t = detail?.valueOrNull ?? ref.watch(ticketByIdProvider(widget.editId!));
      if (t != null && (detail == null || !detail.isLoading)) {
        _seed(t);
      } else if (detail != null && detail.isLoading) {
        return _shell(child: const Center(child: CircularProgressIndicator()), canSave: false);
      } else {
        return _shell(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24.w),
              child: Text("This ticket couldn't be loaded. Go back and try again.",
                  textAlign: TextAlign.center, style: AppText.body(color: AppColors.textMuted)),
            ),
          ),
          canSave: false,
        );
      }
    }
    // A new ticket starts on the org's default status.
    if (!_isEditing && _statusId.isEmpty && statuses.isNotEmpty) {
      _statusId = (statuses.where((s) => s.isDefault).firstOrNull ?? statuses.first).id;
    }

    return _shell(canSave: canSave, child: _form(types, statuses));
  }

  Widget _shell({required Widget child, required bool canSave}) {
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
            Expanded(child: child),
            _footer(canSave),
          ],
        ),
      ),
    );
  }

  Widget _form(List<CatalogOption> types, List<CatalogOption> statuses) {
    final dir = ref.watch(ticketDirectoryProvider);
    // The customer search's first page also tells whether customers are
    // readable at all (a 403 explains itself under the field).
    final firstPage = ref.watch(ticketCustomerSearchProvider(''));
    final forbidden = firstPage.error is AppError && (firstPage.error! as AppError).type == AppErrorType.forbidden;
    final helper = customerFieldHelper(forbidden: forbidden, internal: _internal);

    final customerChanged = _isEditing && _custId != _savedCustId;
    final resolved = _ticket?.facts?.statusResolved ?? false;
    final wantSla = _custId != null && (!_isEditing || (customerChanged && !resolved));
    final sla = wantSla ? ref.watch(ticketCustomerSlaProvider(_custId!)).valueOrNull : null;
    final preview = slaPreviewCopy(
      isEditing: _isEditing,
      customerId: _custId,
      internal: _internal,
      customerSla: sla,
      now: DateTime.now(),
      customerChanged: customerChanged,
      resolved: resolved,
    );
    final hint = priorityHint(types: types, typeId: _typeId, priority: _priority, pickedByUser: _priorityPicked);
    final channels = [
      ...kTicketChannels,
      // A ticket that came in some other way (API, …) keeps its channel.
      if (!kTicketChannels.any((c) => c.$1 == _channel)) (_channel, _channel.isEmpty ? '—' : _channel.toUpperCase()),
    ];

    return ListView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
      children: [
        if (_errors.isNotEmpty) ...[SizedBox(height: 12.h), _errorBox()],
        _section('Ticket Information'),
        AppTextField(
          label: 'Subject',
          required: true,
          controller: _subjectCtrl,
          hint: 'e.g. Broken glass panel on display counter',
          onChanged: (_) => _dirty = true,
        ),
        SizedBox(height: 14.h),
        AppTextField(
          label: 'Description',
          controller: _descCtrl,
          hint: 'What happened, where, and what the customer expects…',
          multiline: true,
          onChanged: (_) => _dirty = true,
        ),
        SizedBox(height: 14.h),
        const TicketFieldLabel('Reported for'),
        SizedBox(height: 7.h),
        TicketChipWrap(
          options: const ['Customer', 'Internal'],
          selected: _internal ? 'Internal' : 'Customer',
          onSelect: (v) => _touch(() => _reportedFor = v == 'Internal' ? kReportedForInternal : kReportedForClient),
        ),
        SizedBox(height: 14.h),
        TicketFieldLabel('Customer', required: !_internal),
        SizedBox(height: 7.h),
        TicketPickerRow(
          label: _custId == null
              ? 'Search customers…'
              : (_custLabel.isNotEmpty ? _custLabel : (dir.customer(_custId)?.display ?? 'Selected customer')),
          placeholder: _custId == null,
          icon: PhosphorIconsRegular.magnifyingGlass,
          onTap: _pickCustomer,
        ),
        if (helper != null) _helper(helper),
        SizedBox(height: 14.h),
        const TicketFieldLabel('Contact'),
        SizedBox(height: 7.h),
        _contactField(),
        SizedBox(height: 14.h),
        const TicketFieldLabel('Channel'),
        SizedBox(height: 7.h),
        TicketChipWrap(
          options: [for (final c in channels) c.$2],
          selected: channels.firstWhere((c) => c.$1 == _channel, orElse: () => channels.first).$2,
          onSelect: (v) => _touch(() => _channel = channels.firstWhere((c) => c.$2 == v).$1),
        ),
        SizedBox(height: 14.h),
        const TicketFieldLabel('Category'),
        SizedBox(height: 7.h),
        TicketChipWrap(
          options: ['Uncategorised', for (final t in types) t.name],
          selected: types.where((t) => t.id == _typeId).firstOrNull?.name ?? 'Uncategorised',
          onSelect: (v) => _touch(() {
            _typeId = types.where((t) => t.name == v).firstOrNull?.id;
            _priority = priorityAfterCategoryChange(
                types: types, typeId: _typeId, current: _priority, pickedByUser: _priorityPicked);
          }),
        ),
        SizedBox(height: 14.h),
        const TicketFieldLabel('Product / Service'),
        SizedBox(height: 7.h),
        TicketPickerRow(
          label: _productName ?? 'Search the catalog…',
          placeholder: _productId == null,
          icon: PhosphorIconsRegular.magnifyingGlass,
          onTap: () async {
            final picked = await pickTicketProduct(context, ref, selectedId: _productId);
            if (picked == null || !mounted) return;
            _touch(() {
              _productId = picked.id;
              _productName = picked.name;
            });
          },
        ),
        _helper('Optional — links the ticket to a catalog item.'),
        SizedBox(height: 14.h),
        const TicketFieldLabel('Related Project'),
        SizedBox(height: 7.h),
        TicketPickerRow(
          label: _projName ?? dir.project(_projId)?.name ?? 'Search projects…',
          placeholder: _projId == null,
          icon: PhosphorIconsRegular.magnifyingGlass,
          onTap: () async {
            final picked = await pickTicketProject(context, ref, selectedId: _projId);
            if (picked == null || !mounted) return;
            _touch(() {
              _projId = picked.id;
              _projName = picked.name;
            });
          },
        ),
        _helper('Optional — connects Helpdesk to Operations.'),
        SizedBox(height: 16.h),
        _billing(),
        _section('Ticket Settings'),
        const TicketFieldLabel('Status'),
        SizedBox(height: 7.h),
        if (statuses.isEmpty)
          _placeholderBox('Loading statuses…')
        else
          TicketChipWrap(
            options: [for (final s in statuses) s.name],
            selected: statuses.where((s) => s.id == _statusId).firstOrNull?.name ?? '',
            dotColor: (name) => statuses.where((s) => s.name == name).firstOrNull?.color ?? AppColors.textMuted,
            onSelect: (v) => _touch(() => _statusId = statuses.firstWhere((s) => s.name == v).id),
          ),
        SizedBox(height: 14.h),
        const TicketFieldLabel('Priority'),
        SizedBox(height: 7.h),
        TicketChipWrap(
          options: kTicketPriorities,
          selected: _priority,
          dotColor: ticketPriDotColor,
          onSelect: (v) => _touch(() {
            _priority = v;
            _priorityPicked = true;
          }),
        ),
        if (hint != null) _helper(hint),
        SizedBox(height: 14.h),
        const TicketFieldLabel('Assignee'),
        SizedBox(height: 7.h),
        TicketPickerRow(
          label: _assigneeName ?? (_assigneeId == null ? 'Unassigned' : 'Assigned'),
          placeholder: _assigneeId == null,
          icon: PhosphorIconsBold.caretDown,
          onTap: _pickAssignee,
        ),
        SizedBox(height: 16.h),
        const TicketFieldLabel('SLA'),
        SizedBox(height: 7.h),
        _slaBox(preview),
      ],
    );
  }

  // ── Fields ──

  Widget _contactField() {
    if (_custId == null) return _placeholderBox('Pick a customer first');
    final contacts = ref.watch(ticketContactsProvider(_custId!));
    if (contacts.isLoading) return _placeholderBox('Loading contacts…');
    final options = contacts.valueOrNull ?? const <TicketPickOption>[];
    if (options.isEmpty) return _placeholderBox('No contacts on file for this customer');
    final label = options.where((c) => c.id == _contactId).firstOrNull?.name ?? _contactLabel;
    return TicketPickerRow(
      label: _contactId == null ? 'No contact' : (label ?? 'Selected contact'),
      placeholder: _contactId == null,
      icon: PhosphorIconsBold.caretDown,
      onTap: () async {
        final picked = await pickTicketLink(
          context,
          title: 'Contact',
          clearLabel: 'No contact',
          empty: 'No contacts on file for this customer',
          options: [for (final c in options) (c.id, c.name, '')],
          selectedId: _contactId,
        );
        if (picked == null || !mounted) return;
        _touch(() {
          _contactId = picked.id;
          _contactLabel = picked.name;
        });
      },
    );
  }

  Widget _billing() {
    if (_billed) {
      final basis = [
        if (_amountCtrl.text.trim().isNotEmpty) '₹${_amountCtrl.text.trim()}',
        if (_billableLabel() != null) _billableLabel()!,
      ].join(' + ');
      return AccInfoBanner(
        'Billed. This ticket is on a tax invoice${basis.isEmpty ? '' : ' ($basis)'}, so its billing can\'t be changed. '
        'Cancel the invoice in Accounting first.',
        icon: PhosphorIconsRegular.lockSimple,
      );
    }
    final defaults = _billable ? ref.watch(ticketBillingDefaultsProvider).valueOrNull : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccCheckRow(
          label: 'Billable — this ticket is chargeable to the customer',
          value: _billable,
          onChanged: (v) => _touch(() => _billable = v),
        ),
        if (_billable) ...[
          SizedBox(height: 12.h),
          MoneyField(
            label: billableAmountLabel(defaults),
            controller: _amountCtrl,
            hint: 'e.g. 2500',
            onChanged: (_) => setState(() => _dirty = true),
          ),
          _helper(billableAmountHint(defaults, hasProduct: _billableProductId != null)),
          SizedBox(height: 12.h),
          const TicketFieldLabel('Billable product'),
          SizedBox(height: 7.h),
          TicketPickerRow(
            label: _billableLabel() ?? 'Search the catalog…',
            placeholder: _billableProductId == null,
            icon: PhosphorIconsRegular.magnifyingGlass,
            onTap: () async {
              final picked = await pickTicketProduct(context, ref, selectedId: _billableProductId);
              if (picked == null || !mounted) return;
              _touch(() {
                _billableProductId = picked.id;
                _billableProductName = picked.name;
              });
            },
          ),
          _helper('What the customer is charged for.'),
        ],
      ],
    );
  }

  String? _billableLabel() {
    if (_billableProductId == null) return null;
    return _billableProductName ??
        ref.watch(allProductsProvider).where((p) => p.id == _billableProductId).firstOrNull?.name ??
        'Selected product';
  }

  // ── Pickers ──

  Future<void> _pickCustomer() async {
    final picked = await showClozrSheet<TicketLink>(
      context: context,
      builder: (_) => _CustomerSearchSheet(selectedId: _custId),
    );
    if (picked == null || !mounted) return;
    _touch(() {
      if (picked.id != _custId) {
        // A contact belongs to one customer.
        _contactId = null;
        _contactLabel = null;
      }
      _custId = picked.id;
      _custLabel = picked.name ?? '';
    });
  }

  Future<void> _pickAssignee() async {
    List<TicketPickOption> users;
    try {
      users = await ref.read(ticketAssignableUsersProvider.future);
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      users = const [];
    }
    if (!mounted) return;
    // An existing assignee who has since lost access stays selectable.
    final options = [
      for (final u in users) (u.id, u.name, ''),
      if (_assigneeId != null && !users.any((u) => u.id == _assigneeId)) (_assigneeId!, _assigneeName ?? 'Current assignee', ''),
    ];
    final picked = await pickTicketLink(
      context,
      title: 'Assignee',
      clearLabel: 'Unassigned',
      empty: 'No one can be assigned tickets yet',
      options: options,
      selectedId: _assigneeId,
    );
    if (picked == null || !mounted) return;
    _touch(() {
      _assigneeId = picked.id;
      _assigneeName = picked.name;
    });
  }

  // ── Save ──

  Future<void> _save() async {
    if (_saving) return;
    // Nothing is sent without the grant (webapp PermissionGate copy).
    if (!ensurePermission(ref, 'issue', _isEditing ? PermVerb.update : PermVerb.create)) return;
    final amount = moneyInput(_amountCtrl.text);
    final errors = validateTicketInput(
      subject: _subjectCtrl.text,
      customerId: _custId,
      reportedFor: _reportedFor,
      billable: _billable && !_billed,
      hasAmount: amount != null,
      hasBillableProduct: _billableProductId != null,
    );
    setState(() => _errors = errors);
    if (errors.isNotEmpty) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      return;
    }
    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show(_isEditing ? 'Ticket updated' : 'Ticket created');
      _dirty = false;
      _leave();
      return;
    }
    final fields = <String, dynamic>{
      'subject': _subjectCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'reported_for': _reportedFor,
      'customer_id': _custId,
      'contact_id': _custId == null ? null : _contactId,
      'channel': _channel,
      'issue_type': _typeId,
      'product_id': _productId,
      'project_id': _projId,
      if (_statusId.isNotEmpty) 'status_id': _statusId,
      'priority': _priority,
      'assigned_to': _assigneeId,
      // A billed ticket's billing is frozen on the invoice line.
      if (!_billed) ...{
        'billable': _billable,
        'billable_amount': _billable ? amount : null,
        'billable_product_id': _billable ? _billableProductId : null,
      },
    };
    setState(() => _saving = true);
    final repo = ref.read(ticketsRepositoryProvider);
    try {
      String message = 'Ticket updated';
      if (_isEditing) {
        await repo.updateTicket(widget.editId!, fields);
      } else {
        final created = await repo.createTicket(fields);
        final ref_ = created?.reference ?? '';
        message = ref_.isNotEmpty ? 'Ticket $ref_ created' : 'Ticket created';
      }
      refreshTickets(ref);
      ref.invalidate(ticketStatusCountsProvider);
      if (!mounted) return;
      _dirty = false;
      ref.read(toastProvider.notifier).show(message);
      _leave();
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      // The billing guard is a field-level refusal — inline, like the client check.
      if (isBillableBasisRefusal(fieldErrors: e.fieldErrors, message: e.message)) {
        ref.read(apiServiceProvider).handled(e);
        setState(() => _errors = [ticketErrorMessage(e)]);
        _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      } else {
        showTicketError(ref, e);
      }
    }
  }

  void _close() => _dirty ? _confirmDiscard() : _leave();

  /// Back to where the form was opened from — or the Tickets list when it was
  /// opened straight from a link and has nothing underneath.
  /// The shell navigator's own stack decides: a linked-to form is its only
  /// page there, while the router still reports something to pop.
  void _leave() => Navigator.of(context).canPop() ? context.pop() : context.go(Routes.tickets);

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
              child: Text(_isEditing ? 'Your edits to this ticket will be lost.' : 'This ticket will not be created.',
                  style: AppText.body(color: AppColors.textMuted)),
            ),
            SizedBox(height: 18.h),
            Row(
              children: [
                Expanded(child: _button('Keep editing', primary: false, onTap: () => Navigator.of(ctx).pop(false))),
                SizedBox(width: 10.w),
                Expanded(child: _button('Discard', danger: true, onTap: () => Navigator.of(ctx).pop(true))),
              ],
            ),
          ],
        ),
      ),
    );
    if (discard == true && mounted) {
      _dirty = false;
      _leave();
    }
  }

  // ── Chrome ──

  Widget _header() {
    final ref_ = _ticket?.displayRef ?? '';
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 54.h, 16.w, 14.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderCardSoft)),
      ),
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
              child: Icon(_isEditing ? PhosphorIconsBold.caretLeft : PhosphorIconsBold.x,
                  size: 17.sp, color: AppColors.textBody),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_isEditing ? 'Edit Ticket' : 'New Ticket',
                    style: AppText.custom(size: 19, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                Text(
                  _isEditing ? (ref_.isEmpty ? 'Helpdesk' : 'Helpdesk · $ref_') : 'Helpdesk',
                  style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(bool canSave) {
    final label = _saving ? 'Saving…' : (_isEditing ? 'Save changes' : 'Create Ticket');
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 22.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!canSave) ...[
            Text(_isEditing ? PermissionCopy.update : PermissionCopy.create,
                textAlign: TextAlign.center,
                style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
            SizedBox(height: 8.h),
          ],
          Row(
            children: [
              SizedBox(width: 100.w, child: _button('Cancel', primary: false, onTap: _saving ? null : _close)),
              SizedBox(width: 10.w),
              // Greyed without the grant — the webapp's disabled button; a tap
              // still explains why instead of sending anything.
              Expanded(child: _button(label, enabled: canSave && !_saving, onTap: _save)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _button(String label, {bool primary = true, bool danger = false, bool enabled = true, VoidCallback? onTap}) {
    final bg = danger ? AppColors.error : (primary ? (enabled ? AppColors.navy : AppColors.textPlaceholder) : AppColors.white);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12.r),
          border: primary || danger ? null : Border.all(color: AppColors.borderCard),
        ),
        child: Text(label,
            style: AppText.custom(
                size: 14.5,
                weight: FontWeight.w700,
                color: primary || danger ? AppColors.white : AppColors.textLabelAlt)),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: EdgeInsets.fromLTRB(2.w, 22.h, 2.w, 12.h),
        child: Text(title.toUpperCase(),
            style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
      );

  Widget _helper(String text) => Padding(
        padding: EdgeInsets.only(top: 6.h, left: 2.w),
        child: Text(text,
            style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted2).copyWith(height: 1.4)),
      );

  Widget _placeholderBox(String text) => Container(
        height: 46.h,
        width: double.infinity,
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.symmetric(horizontal: 14.w),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11.r),
          border: Border.all(color: AppColors.borderInput),
          color: AppColors.bgScreen,
        ),
        child: Text(text, style: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
      );

  Widget _errorBox() => Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 11.h),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.07),
          borderRadius: BorderRadius.circular(11.r),
          border: Border.all(color: AppColors.error),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in _errors)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 2.h),
                child: Text(e,
                    style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textPrimary).copyWith(height: 1.4)),
              ),
          ],
        ),
      );

  Widget _slaBox(SlaPreview p) => Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 12.h),
        decoration: BoxDecoration(color: AppColors.bgScreen, borderRadius: BorderRadius.circular(11.r)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(PhosphorIconsRegular.timer, size: 15.sp, color: AppColors.navy),
            SizedBox(width: 9.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.headline != null) ...[
                    Text(p.headline!,
                        style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(height: 3.h),
                  ],
                  Text(p.detail,
                      style: AppText.custom(
                              size: 12.5,
                              weight: FontWeight.w500,
                              color: p.headline != null ? AppColors.textMuted : AppColors.textBody)
                          .copyWith(height: 1.45)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// The customer picker, searched server-side as the user types (debounced),
/// with the webapp's loading / no-match / "Showing N of M" copy. Pops a
/// [TicketLink]: the pick, or `(id: null, name: null)` for "No customer".
class _CustomerSearchSheet extends ConsumerStatefulWidget {
  const _CustomerSearchSheet({required this.selectedId});
  final String? selectedId;

  @override
  ConsumerState<_CustomerSearchSheet> createState() => _CustomerSearchSheetState();
}

class _CustomerSearchSheetState extends ConsumerState<_CustomerSearchSheet> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _typed = '';
  String _search = '';

  /// The last page shown, kept on screen while the next search loads.
  (List<TicketPickOption>, int)? _last;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() => _typed = v.trim());
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _search = _typed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(ticketCustomerSearchProvider(_search));
    if (page.hasValue) _last = page.value;
    final err = page.error;
    final forbidden = err is AppError && err.type == AppErrorType.forbidden;
    final rows = _last?.$1 ?? const <TicketPickOption>[];
    final pending = _typed != _search || page.isLoading;
    final notice = customerPickerNotice(
      loading: pending && rows.isEmpty,
      forbidden: forbidden,
      failed: err != null && !forbidden,
      query: _typed,
    );
    final footer = page.hasValue ? customerResultsFooter(rows.length, _last!.$2, _search) : null;

    Widget row(String label, {required bool active, required VoidCallback onTap, bool muted = false}) =>
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 11.h),
            child: Row(
              children: [
                Expanded(
                  child: Text(label,
                      style: AppText.custom(
                          size: 14,
                          weight: FontWeight.w700,
                          color: muted ? AppColors.textMuted : AppColors.textPrimary)),
                ),
                if (active) Icon(PhosphorIconsBold.check, size: 16.sp, color: AppColors.blueBright),
              ],
            ),
          ),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: 24.h + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: 'Customer'),
          Padding(
            padding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 6.h),
            child: AppTextField(
              label: 'Search',
              controller: _ctrl,
              hint: 'Search customers…',
              onChanged: _onChanged,
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.symmetric(horizontal: 18.w),
              children: [
                if (widget.selectedId != null)
                  row('No customer', active: false, muted: true, onTap: () => Navigator.of(context).pop((id: null, name: null))),
                if (notice != null)
                  _note(notice)
                else if (rows.isEmpty)
                  _note(customerNoMatchText(_search))
                else ...[
                  for (final c in rows)
                    row(c.name,
                        active: c.id == widget.selectedId,
                        onTap: () => Navigator.of(context).pop((id: c.id, name: c.name))),
                  if (footer != null) _note(footer),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(String text) => Padding(
        padding: EdgeInsets.symmetric(vertical: 14.h),
        child: Text(text, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
      );
}
