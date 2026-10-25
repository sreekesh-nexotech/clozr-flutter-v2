import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers/record_presence_providers.dart';
import '../../../../core/network/api_endpoints.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../accounting/application/providers/accounting_providers.dart';
import '../../../accounting/presentation/components/customer_accounting.dart';
import '../../../accounting/presentation/sheets/party_tax_profile_sheet.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/notes_thread.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/crm_notes_providers.dart';
import '../../application/providers/crm_catalog_providers.dart';
import '../../application/providers/crm_tasks_providers.dart';
import '../../application/providers/crm_module_schema_providers.dart';
import '../../application/providers/customers_providers.dart';
import '../components/option_picker_sheet.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/repositories/customers_repository.dart';
import '../../../../data/api/user_directory.dart';
import '../../../../data/api/status_keys.dart';
import '../../../../core/network/app_error.dart';
import '../../application/providers/customer_activity_providers.dart';
import '../../application/providers/followups_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../../domain/entities/customer.dart';
import '../components/record_payment_sheet.dart';
import '../../domain/entities/audit_entry.dart';
import '../../../../core/utils/relative_time.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/invoice.dart';
import '../components/crm_async.dart';
import '../components/crm_detail_parts.dart';
import 'crm_status_sheet.dart';
import '../../../auth/presentation/components/permission_guard.dart';
import '../../application/providers/lead_lifecycle_providers.dart';
import '../components/customer_lost_dialog.dart';
import '../components/customer_activity_tabs.dart';
import '../components/customer_notes_card.dart';
import '../components/customer_detail/customer_accounting_panel.dart';
import '../components/customer_detail/customer_field_editor.dart';
import '../components/customer_detail/customer_products_sheet.dart';
import '../../application/customer_detail_rules.dart';
import '../../../auth/application/providers/module_perm_providers.dart';
import '../../../../core/network/network_providers.dart';

class CustomerDetailScreen extends ConsumerStatefulWidget {
  const CustomerDetailScreen({super.key});

  @override
  ConsumerState<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  bool _infoMore = false;


  /// True while an upsell POST is in flight. The action is reachable from three
  /// places — the overflow menu, the Upsell button and the Leads tab's CTA — and
  /// it creates a record, so a second tap during the round trip would raise a
  /// second lead. Two were observed in one audit trail, 29s apart.
  bool _upselling = false;

  /// A delete in flight, and the refusal banner (webapp `deleteError`).
  bool _deleting = false;
  String? _deleteError;

  /// The "Changed elsewhere — Reload" banner for a refused non-inline edit
  /// (webapp `useStaleRecordPrompt`).
  ({String message, String unsaved})? _stale;
  bool _staleReloading = false;
  bool _staleReloaded = false;
  final _notesKey = GlobalKey<NotesThreadState>();

  /// The record id whose row / activity tabs were refetched on open.
  /// `customerRowProvider` and the tab providers live for the session, so
  /// without this a customer reopened after a quote was accepted elsewhere
  /// kept its first load (e.g. Opportunities "0 quotes"); the webapp
  /// refetches the record every time its page opens.
  String? _openedId;

  /// Scrolls the notes card into view and focuses the composer (#13).
  void _focusNotes() {
    final ctx = _notesKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 300), alignment: 0.05, curve: Curves.easeOut);
    }
    _notesKey.currentState?.focusComposer();
  }

  void _openCustomerMenu(Customer cust) {
    final toast = ref.read(toastProvider.notifier);
    final first = cust.name.split(' ').first;
    // Webapp gating: quotes need quotation.create, a payment payment.create,
    // an upsell customer.update; removing the customer customer.delete.
    final canQuote = hasPermission(ref, 'quotation', PermVerb.create);
    final canPay = hasPermission(ref, 'payment', PermVerb.create);
    final canUpdate = hasPermission(ref, 'customer', PermVerb.update);
    final perm = ref.read(modulePermProvider('customer'));
    final deleteControl = customerDeleteControl(
      readOnly: isReadOnlyRole(read: perm.read, create: perm.create, update: perm.update, delete: perm.delete),
      canDelete: hasPermission(ref, 'customer', PermVerb.delete),
      row: ref.read(customerRowProvider(cust.id)).valueOrNull,
    );
    showActionMenu(
      context,
      actions: [
        MenuAction(icon: PhosphorIconsFill.phone, label: 'Call customer', onTap: () => toast.show('Calling $first…')),
        MenuAction(icon: PhosphorIconsRegular.whatsappLogo, label: 'WhatsApp chat', onTap: () => toast.show('Opening WhatsApp…')),
        MenuAction(
            icon: PhosphorIconsRegular.filePlus,
            label: 'Create quote',
            enabled: canQuote,
            sublabel: canQuote ? null : permissionCopy(PermVerb.create),
            onTap: () => _createQuote(cust)),
        MenuAction(
            icon: PhosphorIconsRegular.wallet,
            label: 'Record payment',
            enabled: canPay,
            sublabel: canPay ? null : permissionCopy(PermVerb.create),
            onTap: () => _recordPayment(cust)),
        MenuAction(
          icon: PhosphorIconsFill.trendUp,
          label: 'Create upsell lead',
          enabled: !_upselling && canUpdate,
          sublabel: !canUpdate
              ? permissionCopy(PermVerb.update)
              : _upselling
                  ? 'Already raising one…'
                  : null,
          onTap: () => _createUpsell(cust),
        ),
        // The bottom bar's pencil now opens the edit form, so the note
        // composer keeps its route to the user here — the same place the lead
        // and task screens offer it.
        MenuAction(
            icon: PhosphorIconsRegular.notePencil,
            label: 'Add note',
            onTap: _focusNotes),
        if (ref.read(accountingActiveProvider) && ref.read(accPermProvider('acc_setup')).read)
          MenuAction(
              icon: PhosphorIconsRegular.identificationCard,
              label: 'Tax profile',
              sublabel: 'GSTIN, PAN and registration',
              onTap: () => showPartyTaxProfileSheet(context, kind: 'customer', partyId: cust.id, title: cust.name)),
        // Webapp: Delete (no archive on the detail page). Hidden for a
        // read-only role; disabled with the reason without `delete` or when
        // the server says this customer can never be deleted.
        if (deleteControl.visible)
          MenuAction(
              icon: PhosphorIconsRegular.trash,
              label: _deleting ? 'Deleting…' : 'Delete',
              destructive: true,
              enabled: deleteControl.enabled && !_deleting,
              sublabel: deleteControl.reason,
              onTap: () => _deleteCustomer(cust)),
      ],
    );
  }


  // ── Create quote ──

  /// Opens the quote form against one of this customer's leads.
  ///
  /// A quote is raised against a **lead**, not a customer — the add-quote form
  /// requires one and rejects an empty `leadId`. And [Customer.leadId] is always
  /// null (the list rows carry no source-lead reference), so the lead has to come
  /// from the customer's own leads: one is adopted silently, several are offered,
  /// none is reported rather than opening a form that could not be submitted.
  Future<void> _createQuote(Customer cust) async {
    final toast = ref.read(toastProvider.notifier);
    List<Lead> leads;
    try {
      leads = await ref.read(customerLeadsProvider(cust.id).future);
    } on Object {
      leads = const [];
    }
    if (!mounted) return;

    if (leads.isEmpty) {
      toast.show('A quote is raised against a lead. Create an upsell lead first.');
      return;
    }
    var leadId = leads.first.id;
    if (leads.length > 1) {
      final picked = await showOptionPicker(
        context: context,
        title: 'Quote for which lead?',
        options: [for (final l in leads) CatalogOption(id: l.id, name: l.name)],
        selected: {leads.first.id},
      );
      if (picked == null || picked.isEmpty || !mounted) return;
      leadId = picked.first;
    }
    context.push('${Routes.addQuote}?leadId=$leadId');
  }

  // ── Record payment ──

  /// Records a payment against one of this customer's invoices.
  ///
  /// The sheet needs an invoice id: left to itself it defaults to the first
  /// unsettled invoice in the **org-wide** list, which from a customer's page
  /// would quietly settle somebody else's. So the invoice is chosen from this
  /// customer's own — preferring one still outstanding — and the action reports
  /// rather than opening the sheet when there are none.
  Future<void> _recordPayment(Customer cust) async {
    final toast = ref.read(toastProvider.notifier);
    List<Invoice> invoices;
    try {
      invoices = await ref.read(customerInvoicesProvider(cust.id).future);
    } on Object {
      invoices = const [];
    }
    if (!mounted) return;

    if (invoices.isEmpty) {
      toast.show('No invoice for this customer yet — a payment is recorded '
          'against one.');
      return;
    }
    final outstanding = invoices.where((i) => i.status != 'completed');
    final target = outstanding.isNotEmpty ? outstanding.first : invoices.first;

    await showRecordPaymentSheet(context, invoiceId: target.id);
    if (!mounted) return;
    // The sheet writes through the payments repository, so this page's own
    // scoped fetch has to be dropped too — it is not one of the providers the
    // sheet knows about.
    ref.invalidate(customerInvoicesProvider(cust.id));
  }

  // ── Delete ──

  /// Deletes the customer — `DELETE /crm/customers/{id}/` (webapp SL 56).
  ///
  /// Behind the webapp's confirm. On success: "Customer deleted" and back to
  /// the customers list. A refusal (409 PARTY_HAS_BOOKS, 403, 404) keeps the
  /// customer and shows the reason in a banner under the header.
  Future<void> _deleteCustomer(Customer cust) async {
    if (_deleting) return;
    final name = _nameOf(cust);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this customer?'),
        content: Text('$name and its details will be permanently removed. A customer that accounting '
            'records (invoices, receipts or payments) reference can’t be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete customer', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _deleting = true;
      _deleteError = null;
    });
    final api = ref.read(apiServiceProvider);
    try {
      await api.delete(ApiEndpoints.customer(cust.id));
    } on AppError catch (e) {
      api.handled(e);
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _deleteError = customerDeleteErrorCopy(e);
      });
      return;
    }
    if (!mounted) return;
    setState(() => _deleting = false);
    ref.invalidate(customersScopedProvider);
    ref.read(toastProvider.notifier).show('Customer deleted');
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.customers);
    }
  }

  // ── Writes ──

  /// The record's version (`updated_at` as last read), sent as `If-Match`.
  String? _versionOf(String id) {
    final v = ref.read(customerRowProvider(id)).valueOrNull?['updated_at'];
    return v is String && v.trim().isNotEmpty ? v : null;
  }

  /// Re-reads the record (the stale-record "Reload"), so the next save
  /// carries the latest version.
  Future<void> _reloadRecord(String id) async {
    ref.invalidate(customerRowProvider(id));
    ref.invalidate(customersScopedProvider);
    await ref.read(customerRowProvider(id).future);
  }

  /// One customer PATCH with `If-Match`. Null on success (the record is then
  /// re-read before returning, so a second quick edit carries the new
  /// version); otherwise the error, already withdrawn from the shell's raw
  /// toast so the caller can explain it in place.
  Future<AppError?> _patch(Customer cust, Map<String, dynamic> body) async {
    try {
      await ref.read(customersRepositoryProvider).updateCustomer(cust.id, body, version: _versionOf(cust.id));
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      return e;
    }
    ref.invalidate(customersScopedProvider);
    await _reloadRecord(cust.id);
    return null;
  }

  /// [_patch] for a non-inline edit (status, assignees): a stale refusal
  /// raises the page's "Changed elsewhere — Reload" banner naming what was
  /// not saved; anything else is the server's own sentence as a toast.
  Future<bool> _write(Customer cust, Map<String, dynamic> body,
      {required String success, required String unsaved}) async {
    final e = await _patch(cust, body);
    if (!mounted) return false;
    if (e == null) {
      ref.read(toastProvider.notifier).show(success);
      return true;
    }
    final err = customerWriteError(e);
    if (err.stale) {
      setState(() {
        _stale = (message: e.message, unsaved: unsaved);
        _staleReloaded = false;
      });
    } else {
      ref.read(toastProvider.notifier).showError(err.message);
    }
    return false;
  }

  /// An inline field save: "Customer updated", or the message for under the
  /// field (the editor stays open with the typed value).
  Future<({String message, bool stale})?> _saveFieldPatch(Customer cust, Map<String, dynamic> patch) async {
    if (!hasPermission(ref, 'customer', PermVerb.update)) {
      return (message: permissionCopy(PermVerb.update), stale: false);
    }
    final e = await _patch(cust, patch);
    if (!mounted) return null;
    if (e != null) return customerWriteError(e);
    ref.read(toastProvider.notifier).show('Customer updated');
    return null;
  }

  /// The display name — the record's when it has landed.
  String _nameOf(Customer cust) {
    final n = ref.read(customerRowProvider(cust.id)).valueOrNull?['name'];
    return n is String && n.trim().isNotEmpty ? n.trim() : cust.name;
  }

  /// The pill colour for an org status. Derived from its **type** — the
  /// backend-fixed code — never its name, which an admin can rename freely.
  static StatusMeta _metaFor(CustomerStatus status) {
    final key = customerStatusKey(name: status.name, type: status.statusType);
    final base = StatusMeta$.customer[key] ?? StatusMeta$.customer['active']!;
    return StatusMeta(status.name, base.color);
  }

  /// The org status currently on this customer, matched by folding each catalog
  /// entry to the same key the record was mapped to. The record echoes a status
  /// *name*, not an id, so this is the only way back to the id a write needs.
  static String _currentStatusId(List<CustomerStatus> statuses, Customer cust) {
    for (final s in statuses) {
      if (customerStatusKey(name: s.name, type: s.statusType) == cust.status) {
        return s.id;
      }
    }
    return '';
  }

  // ── Status ──

  /// Opens the status picker.
  ///
  /// With the org catalog loaded the options are the org's own statuses and
  /// picking one writes it. Without it (mock mode, or a failed fetch) it falls
  /// back to the built-in vocabulary with no `onSelect` — the previous
  /// toast-only behaviour, because there is no id to persist.
  void _openStatusSheet(Customer cust) {
    if (!ensurePermission(ref, 'customer', PermVerb.update)) return;
    final statuses = ref.read(customerStatusesProvider);
    if (statuses.isEmpty) {
      showCrmStatusSheet(
        context: context,
        ref: ref,
        title: 'Update customer status',
        options: StatusMeta$.customerOrder,
        meta: StatusMeta$.customer,
        current: cust.status,
      );
      return;
    }
    showCrmStatusSheet(
      context: context,
      ref: ref,
      title: 'Update customer status',
      options: [for (final s in statuses) s.id],
      meta: {for (final s in statuses) s.id: _metaFor(s)},
      current: _currentStatusId(statuses, cust),
      onSelect: (statusId) => _setStatus(cust, statusId),
    );
  }

  /// Writes the new status (webapp `changeStatus` / `moveStatus`).
  ///
  /// Moving **into** a Lost status first opens "Move to <status>"
  /// (`CustomerLostModal`): the reason is required and the sheet lists the
  /// deals the move closes. A `409 LOST_HAS_OPEN_INVOICES` (an invoice issued
  /// after the sheet opened) re-opens it listing those invoices.
  Future<void> _setStatus(Customer cust, String statusId, {List<CustomerLostImpact> blocked = const []}) async {
    final statuses = ref.read(customerStatusesProvider);
    final target = statuses.where((s) => s.id == statusId).firstOrNull;
    final current = statuses.where((s) => s.id == _currentStatusId(statuses, cust)).firstOrNull;
    LostChoice? lost;
    if (target?.statusType == 'lost' && current?.statusType != 'lost') {
      lost = await showCustomerLostDialog(context,
          customerId: cust.id, statusName: target!.name, blocked: blocked);
      if (lost == null || !mounted) return;
    }
    final e = await _patch(cust, {'status': statusId, ...?lost?.toBody()});
    if (!mounted) return;
    if (e == null) {
      ref.invalidate(customerRowProvider(cust.id));
      ref.read(toastProvider.notifier).show(lost != null
          ? 'Marked ${target?.name ?? 'Lost'} — its open deals were closed'
          : 'Status updated');
      return;
    }
    if (e.code == lostHasOpenInvoicesCode && lost != null) {
      final impacts = customerLostImpactsFromCause(e.causeMap.isNotEmpty ? e.causeMap : e.extra);
      if (impacts.isNotEmpty) {
        await _setStatus(cust, statusId, blocked: impacts);
        return;
      }
    }
    final err = customerWriteError(e);
    if (err.stale) {
      setState(() {
        _stale = (message: e.message, unsaved: 'Status → ${target?.name ?? 'the new status'}');
        _staleReloaded = false;
      });
    } else {
      // A rejected write must not leave a status on screen that never saved.
      ref.read(toastProvider.notifier).showError(err.message);
    }
  }

  // ── Upsell ──

  /// Raises an upsell lead against this customer.
  ///
  /// Behind a confirmation: it creates a record *and* moves the customer into
  /// "Upsell in progress", which is too much to do on a stray tap. The new
  /// lead's id comes back when the response carries one, so the user lands on it
  /// rather than hunting through the Leads tab.
  Future<void> _createUpsell(Customer cust) async {
    if (_upselling) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Raise an upsell?'),
        content: Text('A new upsell lead will be created for ${cust.name}, and '
            'the customer moves to "Upsell in progress".'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (_upselling) return;
    setState(() => _upselling = true);

    final toast = ref.read(toastProvider.notifier);
    String? leadId;
    try {
      leadId = await ref.read(customersRepositoryProvider).createUpsell(cust.id);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _upselling = false);
      toast.showError(e is AppError ? e.message : 'Could not raise the upsell.');
      return;
    }
    if (!mounted) return;
    setState(() => _upselling = false);
    // The status, the linked leads, this page's Leads tab and every lead list
    // all moved.
    ref.invalidate(customersScopedProvider);
    ref.invalidate(customerRowProvider(cust.id));
    ref.invalidate(customerLeadsProvider(cust.id));
    ref.invalidate(leadsScopedProvider);
    toast.show('Upsell lead created');
    if (leadId != null && leadId.isNotEmpty) {
      context.push('${Routes.leadDetail}?id=$leadId');
    }
  }

  // ── Assignees ──
  //
  // Webapp "Assigned to": a customer has no single owner — `assignees` is a
  // flat set (embedded users on read, a UUID array on write), managed as one
  // add/remove list.

  /// "Add assignee": only assignable users (`/management/assignable-users/
  /// ?module=customer`) not already assigned.
  Future<void> _addAssignee(Customer cust) async {
    if (!ensurePermission(ref, 'customer', PermVerb.update)) return;
    final toast = ref.read(toastProvider.notifier);
    final current = [for (final a in customerAssignees(ref.read(customerRowProvider(cust.id)).valueOrNull)) a.id];
    List<CatalogOption> users;
    try {
      users = await ref.read(assignableUsersForModuleProvider('customer').future);
    } on Object catch (e) {
      if (!mounted) return;
      toast.showError(e is AppError ? e.message : 'Could not load the user list.');
      return;
    }
    if (!mounted) return;
    final picked = await showOptionPicker(
      context: context,
      title: 'Add assignee',
      options: assignableNotAssigned<CatalogOption>(users, (u) => u.id, current),
      selected: const {},
      emptyNote: 'Everyone who can be assigned already is.',
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final id = picked.first;
    if (current.contains(id)) return;
    final name = users.where((u) => u.id == id).map((u) => u.name).firstOrNull ?? '';
    await _write(cust, {'assignees': [...current, id]},
        success: 'Assignee added', unsaved: 'Add assignee $name'.trim());
  }

  /// The chip's ×.
  Future<void> _removeAssignee(Customer cust, ({String id, String name}) who) async {
    if (!ensurePermission(ref, 'customer', PermVerb.update)) return;
    final current = [for (final a in customerAssignees(ref.read(customerRowProvider(cust.id)).valueOrNull)) a.id];
    await _write(cust, {'assignees': [for (final i in current) if (i != who.id) i]},
        success: 'Assignee removed', unsaved: 'Remove assignee ${who.name}'.trim());
  }

  // ── Products ──

  /// The webapp's Products dialog — whole-number quantities, then
  /// `PATCH {products: [{product_id, quantity}]}` → "Products updated".
  Future<void> _editProducts(Customer cust) async {
    if (!ensurePermission(ref, 'customer', PermVerb.update)) return;
    List<CatalogOption> options;
    try {
      options = await ref.read(productCatalogProvider.future);
    } on Object {
      options = const [];
    }
    if (!mounted) return;
    await showCustomerProductsSheet(
      context,
      current: ref.read(customerRowProvider(cust.id)).valueOrNull?['products'],
      options: options,
      onSave: (patch) async {
        final e = await _patch(cust, patch);
        if (!mounted) return null;
        if (e != null) return customerWriteError(e);
        ref.read(toastProvider.notifier).show('Products updated');
        return null;
      },
    );
  }

  /// Opens the editor for one information row.
  Future<void> _editField(Customer cust, CustomerInfoField field) async {
    if (field.kind == InfoEditKind.products) {
      await _editProducts(cust);
      return;
    }
    await showCustomerFieldEditor(
      context,
      field: field,
      onSave: (patch) => _saveFieldPatch(cust, patch),
      onReload: () => _reloadRecord(cust.id),
    );
  }

  /// Wraps a loading / error / not-found state under the section app bar so the
  /// back control stays available in every state.
  Widget _stateScaffold(Widget child) => Container(
        color: AppColors.bgDetail,
        child: Column(
          children: [
            DetailAppBar(section: 'Customer', onBack: () => context.pop()),
            Expanded(child: child),
          ],
        ),
      );

  /// "Customer not found" with a way back to the list, which is refreshed so the stale
  /// row disappears too.
  Widget _notFound(BuildContext context) => EmptyState(
        icon: PhosphorIconsRegular.userCircle,
        title: 'Customer not found',
        body: 'It may have been deleted or moved.',
        ctaLabel: 'Go to customers',
        onCta: () {
          // The list screen watches its own family member, so drop them all.
          ref.invalidate(customersScopedProvider);
          context.pop();
        },
      );

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final async = ref.watch(customersProvider);
    return async.when(
      loading: () => _stateScaffold(const DetailSkeleton()),
      error: (e, _) => _stateScaffold(
        ErrorState.forError(crmAppError(e), onRetry: () => ref.invalidate(customersScopedProvider)),
      ),
      data: (_) => _buildCustomer(context, id),
    );
  }

  /// Pull-to-refresh: the customer list this record is read out of, plus the
  /// tasks, follow-ups and leads its activity tabs read. Those three are global
  /// lists filtered down to this customer, so none of them refetches on its own.
  Future<void> _refresh(String id) async {
    ref.invalidate(customersScopedProvider);
    ref.invalidate(customerDetailSchemaFutureProvider);
    ref.invalidate(customerRowProvider(id));
    ref.invalidate(crmTasksProvider);
    ref.invalidate(customerTasksProvider(id));
    ref.invalidate(customerFollowupsProvider(id));
    ref.invalidate(customerCallLogsProvider(id));
    ref.invalidate(customerFilesProvider(id));
    ref.invalidate(customerInvoicesProvider(id));
    ref.invalidate(customerLeadsProvider(id));
    ref.invalidate(customerStatusCatalogProvider);
    ref.invalidate(customerActivityLogProvider(id));
    refreshFollowups(ref);
    refreshCustomerActivityTabs(ref, id);
    ref.invalidate(leadsScopedProvider);
    ref.invalidate(crmNotesProvider);
    await settle([
      ref.read(customersProvider.future),
      ref.read(crmTasksProvider.future),
      ref.read(followupsProvider.future),
      ref.read(leadsProvider.future),
      ref.read(customerDetailSchemaFutureProvider.future),
      ref.read(customerRowProvider(id).future),
      ref.read(customerTasksProvider(id).future),
      ref.read(customerCallLogsProvider(id).future),
      ref.read(customerFollowupsProvider(id).future),
      ref.read(customerInvoicesProvider(id).future),
      ref.read(customerLeadsProvider(id).future),
      ref.read(customerFilesProvider(id).future),
    ]);
  }

  Widget _buildCustomer(BuildContext context, String id) {
    final cust = ref.watch(customerByIdProvider(id));
    if (cust == null) return _stateScaffold(_notFound(context));
    // The row above comes from the loaded list, which can outlive the record:
    // ask the record endpoint, and show the webapp's not-found state on a 404.
    final gone = ref.watch(recordGoneProvider(RecordProbe(ApiEndpoints.customer(cust.id)))).valueOrNull ?? false;
    if (gone) return _stateScaffold(_notFound(context));

    if (_openedId != cust.id) {
      _openedId = cust.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.invalidate(customerRowProvider(cust.id));
        refreshCustomerActivityTabs(ref, cust.id);
      });
    }

    final meta = StatusMeta$.customer[cust.status] ?? StatusMeta$.customer['active']!;


    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: 'Customer',
            name: cust.name,
            onBack: () => context.pop(),
            trailing: DetailIconAction(
              icon: PhosphorIconsBold.dotsThreeVertical,
              onTap: () => _openCustomerMenu(cust),
            ),
          ),
          Expanded(
            child: AppRefresh(
              onRefresh: () => _refresh(cust.id),
              child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 140.h),
              children: [
                if (_stale != null) ...[_staleBanner(cust), SizedBox(height: 14.h)],
                _profileCard(cust, meta),
                SizedBox(height: 14.h),
                if (_deleteError != null) ...[
                  _banner(
                    icon: PhosphorIconsRegular.warning,
                    tone: AppColors.error,
                    bg: AppColors.tintRed,
                    child: Text(_deleteError!, style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textBody)),
                    onDismiss: () => setState(() => _deleteError = null),
                  ),
                  SizedBox(height: 14.h),
                ],
                if (CustomerHeaderFacts.fromRow(ref.watch(customerRowProvider(cust.id)).valueOrNull).isConverted) ...[
                  _banner(
                    icon: PhosphorIconsRegular.lock,
                    tone: AppColors.success,
                    bg: AppColors.tintGreen,
                    child: Text.rich(TextSpan(children: [
                      TextSpan(
                          text: convertedBannerLead,
                          style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary)),
                      TextSpan(
                          text: convertedBannerBody,
                          style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textBody)),
                    ])),
                  ),
                  SizedBox(height: 14.h),
                ],
                _scoreCard(cust),
                SizedBox(height: 14.h),
                _infoCard(cust),
                SizedBox(height: 14.h),
                CustomerActivityTabs(
                  customer: cust,
                  onUpsell: () => _createUpsell(cust),
                  onRecordPayment: () => _recordPayment(cust),
                ),
                SizedBox(height: 14.h),
                CustomerNotesCard(customer: cust, threadKey: _notesKey),
                SizedBox(height: 14.h),
                // Webapp `CustomerAccountingPanel`: only while accounting is
                // active, and only with at least one acc_* grant.
                CustomerAccountingPanel(customerId: cust.id, customerName: cust.name),
                _activityLogCard(cust),
              ],
              ),
            ),
          ),
          _bottomBar(cust),
        ],
      ),
    );
  }

  Widget _profileCard(Customer cust, StatusMeta meta) {
    // The header reads the **detail record** (webapp header): the list row is
    // trimmed to the org's mobile config and carries none of these facts.
    final row = ref.watch(customerRowProvider(cust.id)).valueOrNull;
    final facts = CustomerHeaderFacts.fromRow(row);
    final name = (row?['name'] is String && (row!['name'] as String).trim().isNotEmpty)
        ? (row['name'] as String).trim()
        : cust.name;
    final initials = UserDirectory.initialsOf(name);
    final canUpdate = hasPermission(ref, 'customer', PermVerb.update);

    Widget stat(String label, num value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: AppText.custom(size: 10, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.4)),
            SizedBox(height: 2.h),
            Text(webMoney(value),
                style: AppText.custom(size: 18, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
          ],
        );

    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.all(18.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 62.w,
                height: 62.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(15.r)),
                child: Text(initials, style: AppText.custom(size: 17, weight: FontWeight.w700, color: AppColors.navy, letterSpacing: 0.4)),
              ),
              SizedBox(width: 13.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.custom(size: 20, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
                    if (facts.isConverted || facts.isUpsell || cust.isUpsell) ...[
                      SizedBox(height: 5.h),
                      Wrap(
                        spacing: 6.w,
                        runSpacing: 4.h,
                        children: [
                          if (facts.isConverted) _textBadge('CONVERTED', AppColors.success, AppColors.tintGreen),
                          if (facts.isUpsell || cust.isUpsell) _upsellBadge(),
                        ],
                      ),
                    ],
                    // "B2B · <GSTIN>" — accounting active + acc_setup only.
                    CustomerB2bBadge(customerId: cust.id),
                    if (facts.subtitle.isNotEmpty) ...[
                      SizedBox(height: 4.h),
                      Text(facts.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                    ],
                    if (facts.since.isNotEmpty) ...[
                      SizedBox(height: 5.h),
                      Row(
                        children: [
                          Icon(PhosphorIconsRegular.calendarBlank, size: 13.sp, color: AppColors.textPlaceholder),
                          SizedBox(width: 5.w),
                          Text('Customer since ${facts.since}',
                              style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textMuted2)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (facts.dealValue != null || facts.received != null) ...[
            SizedBox(height: 14.h),
            Row(
              children: [
                if (facts.dealValue != null) Expanded(child: stat('Value (excl. GST)', facts.dealValue!)),
                if (facts.received != null) Expanded(child: stat('Received (incl. GST)', facts.received!)),
              ],
            ),
          ],
          if (facts.isLost) ...[
            SizedBox(height: 10.h),
            Text('Lost: ${facts.lostReason}',
                style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.error)),
          ],
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 15)),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _openStatusSheet(cust),
                  child: Container(
                    height: 44.h,
                    padding: EdgeInsets.symmetric(horizontal: 12.w),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(11.r),
                      border: Border.all(color: const Color(0xFFE6E7EA)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(width: 9.w, height: 9.w, decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle)),
                        SizedBox(width: 8.w),
                        Flexible(child: Text(meta.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textBody))),
                        if (canUpdate) ...[
                          SizedBox(width: 6.w),
                          Icon(PhosphorIconsBold.caretDown, size: 11.sp, color: AppColors.textMuted2),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (ensurePermission(ref, 'customer', PermVerb.update)) _createUpsell(cust);
                  },
                  child: Container(
                    height: 44.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(11.r)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(PhosphorIconsFill.trendUp, size: 16.sp, color: AppColors.white),
                        SizedBox(width: 8.w),
                        Text('Upsell', style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _textBadge(String label, Color fg, Color bg) => Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7.r)),
        child: Text(label, style: AppText.custom(size: 11, weight: FontWeight.w700, color: fg)),
      );

  /// A full-width notice card (delete refusal, converted, stale record).
  Widget _banner({
    required IconData icon,
    required Color tone,
    required Color bg,
    required Widget child,
    VoidCallback? onDismiss,
    Widget? action,
  }) {
    return Container(
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: tone.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16.sp, color: tone),
          SizedBox(width: 8.w),
          Expanded(child: child),
          if (action != null) ...[SizedBox(width: 8.w), action],
          if (onDismiss != null)
            GestureDetector(
              onTap: onDismiss,
              child: Padding(
                padding: EdgeInsets.only(left: 8.w),
                child: Icon(PhosphorIconsBold.x, size: 14.sp, color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  /// Webapp `StaleRecordNotice`: a status / assignee change refused because
  /// the customer changed elsewhere. Names what was not saved; Reload re-reads.
  Widget _staleBanner(Customer cust) {
    final s = _stale!;
    return _banner(
      icon: PhosphorIconsRegular.arrowsClockwise,
      tone: AppColors.warningDeep,
      bg: AppColors.tintAmber,
      onDismiss: () => setState(() => _stale = null),
      action: _staleReloaded
          ? null
          : GestureDetector(
              onTap: _staleReloading
                  ? null
                  : () async {
                      setState(() => _staleReloading = true);
                      await _reloadRecord(cust.id);
                      if (!mounted) return;
                      setState(() {
                        _staleReloading = false;
                        _staleReloaded = true;
                      });
                    },
              child: Text(_staleReloading ? 'Reloading…' : 'Reload',
                  style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.blueBright)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Changed elsewhere — ${s.message}',
              style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textPrimary)),
          if (s.unsaved.isNotEmpty) ...[
            SizedBox(height: 3.h),
            Text('Not saved: ${s.unsaved}', style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textBody)),
          ],
          if (_staleReloaded) ...[
            SizedBox(height: 3.h),
            Text('Latest version loaded — make the change again.',
                style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }

  Widget _upsellBadge() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(color: AppColors.tintPurple, borderRadius: BorderRadius.circular(7.r)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsFill.trendUp, size: 11.sp, color: AppColors.pending),
          SizedBox(width: 4.w),
          Text('UPSELL', style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.pending)),
        ],
      ),
    );
  }

  Widget _scoreCard(Customer cust) {
    // `score` is not in this org's list config, so the entity carries 0 and the
    // card read "0 / 100" while the information row below it — fed by the
    // detail row — showed the real figure. One screen, two answers for the same
    // field. The detail row wins; the entity stays the fallback.
    final row = ref.watch(customerRowProvider(cust.id)).valueOrNull;
    final score = (row?['score'] as num?)?.toInt() ?? cust.score;
    final color = score >= 75 ? AppColors.success : (score >= 45 ? AppColors.warningDeep : AppColors.error);
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Customer score', style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 2.h),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(7.r)),
                child: Text('$score / 100', style: AppText.custom(size: 12, weight: FontWeight.w700, color: color)),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(999.r),
            child: LinearProgressIndicator(
              value: score / 100,
              minHeight: 7.h,
              backgroundColor: AppColors.borderCardSoft,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 15)),
          Row(
            children: [
              Container(
                width: 34.w,
                height: 34.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.tintPurple, borderRadius: BorderRadius.circular(10.r)),
                child: Icon(PhosphorIconsFill.sparkle, size: 18.sp, color: AppColors.pending),
              ),
              SizedBox(width: 11.w),
              Text('AI summary', style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
              SizedBox(width: 7.w),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
                decoration: BoxDecoration(color: AppColors.tintPurple, borderRadius: BorderRadius.circular(6.r)),
                child: Text('SOON', style: AppText.custom(size: 10, weight: FontWeight.w700, color: AppColors.pending)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The built-in information rows, used when the org's `detail` layout has not
  /// loaded (and in mock mode). Read-only: nothing names the API fields.
  List<(String, String)> _fallbackInfoRows(Customer cust) => [
        ('Email', cust.email),
        ('Mobile', cust.phone),
        ('Location', cust.location),
        ('Source', cust.source),
        ('Customer since', cust.since),
        ('Product / Need', cust.project),
        ('Deal value', cust.value),
        ('Industry', cust.industry),
        ('Website', cust.website),
      ];

  /// One information row: tap to edit when the field is editable (webapp
  /// `InfoFieldList`); Source explains why it is read-only.
  Widget _fieldRow(Customer cust, CustomerInfoField f, {bool last = false}) {
    final row = DetailInfoRow(label: f.label, value: f.value, last: last);
    if (f.hint != null) {
      return Tooltip(message: f.hint!, triggerMode: TooltipTriggerMode.tap, child: row);
    }
    if (!f.editable) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _editField(cust, f),
      child: row,
    );
  }

  Widget _eyebrow(String t) => Text(t,
      style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.6));

  Widget _infoCard(Customer cust) {
    final schema = ref.watch(customerDetailSchemaProvider);
    final row = ref.watch(customerRowProvider(cust.id)).valueOrNull;
    // Without `update` nothing is editable (webapp `perms.can('update')`).
    final canUpdate = ref.watch(modulePermProvider('customer')).update;
    final industries = canUpdate ? ref.watch(industryCatalogProvider).valueOrNull : null;

    final List<Widget> infoRows;
    List<CustomerInfoField> billing = const [];
    if (schema.isEmpty || row == null) {
      final all = _fallbackInfoRows(cust);
      infoRows = [for (final r in all) DetailInfoRow(label: r.$1, value: r.$2.isEmpty ? '—' : r.$2)];
    } else {
      final built = buildCustomerInfoFields(
        row: row,
        columns: schema.columns,
        editable: canUpdate,
        industryOptions: industries == null ? null : [for (final o in industries) (o.id, o.name)],
        hasProductsEditor: true,
      );
      billing = built.billing;
      infoRows = [for (final f in built.info) _fieldRow(cust, f)];
    }
    // Long layouts stay behind "Show more"; a short one shows whole.
    const collapseAt = 8;
    final collapsible = infoRows.length > collapseAt;
    final rows = (_infoMore || !collapsible) ? infoRows : infoRows.take(collapseAt).toList();
    final assignees = customerAssignees(row);
    final teamName = _teamNameOf(row?['assigned_team']);

    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.all(18.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Customer information', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 6.h),
          ...rows,
          if (collapsible)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _infoMore = !_infoMore),
              child: Container(
                margin: EdgeInsets.only(top: 6.h),
                padding: EdgeInsets.only(top: 11.h, bottom: 2.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_infoMore ? 'Show less' : 'Show more', style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.blueBright)),
                    SizedBox(width: 6.w),
                    Icon(_infoMore ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown, size: 12.sp, color: AppColors.blueBright),
                  ],
                ),
              ),
            ),
          if (billing.isNotEmpty) ...[
            SizedBox(height: 18.h),
            _eyebrow('BILLING & DELIVERY'),
            SizedBox(height: 4.h),
            for (final f in billing) _fieldRow(cust, f),
          ],
          SizedBox(height: 18.h),
          Row(
            children: [
              Expanded(child: _eyebrow('ASSIGNED TO')),
              if (canUpdate) _roundAction(PhosphorIconsRegular.userPlus, () => _addAssignee(cust)),
            ],
          ),
          SizedBox(height: 8.h),
          if (assignees.isEmpty)
            Text('Unassigned', style: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textPlaceholder))
          else
            Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: [for (final a in assignees) _assigneeChip(cust, a, removable: canUpdate)],
            ),
          if (teamName.isNotEmpty) ...[
            SizedBox(height: 14.h),
            Text('Assigned team', style: AppText.caption(color: AppColors.textMuted)),
            SizedBox(height: 5.h),
            Row(
              children: [
                Icon(PhosphorIconsRegular.usersThree, size: 15.sp, color: AppColors.textLabelAlt),
                SizedBox(width: 7.w),
                Text(teamName, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// An assignee chip — initials, full name and ×.
  Widget _assigneeChip(Customer cust, ({String id, String name}) a, {required bool removable}) {
    final name = a.name.isEmpty ? 'User' : a.name;
    return Container(
      padding: EdgeInsets.fromLTRB(4.w, 4.h, removable ? 4.w : 10.w, 4.h),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(999.r),
        border: Border.all(color: const Color(0xFFE6E7EA)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24.w,
            height: 24.w,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
            child: Text(UserDirectory.initialsOf(name),
                style: AppText.custom(size: 10, weight: FontWeight.w700, color: AppColors.white)),
          ),
          SizedBox(width: 7.w),
          Text(name, style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textSecondary)),
          if (removable)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _removeAssignee(cust, a),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                child: Icon(PhosphorIconsBold.x, size: 12.sp, color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  /// The team's display name from `assigned_team`, which arrives either as a
  /// nested object or as the bare id the schema describes (`foreignkey` →
  /// `Team`). An id is resolved against the org's own team catalog; an id with
  /// no match, and an unset field, both answer empty — the caller says "no team
  /// assigned" rather than inventing one.
  String _teamNameOf(Object? value) {
    if (value == null) return '';
    if (value is Map) {
      for (final key in const ['name', 'team_name', 'title', 'label']) {
        final v = value[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return '';
    }
    final id = value.toString().trim();
    if (id.isEmpty) return '';
    for (final option in ref.watch(teamOptionsProvider)) {
      if (option.id == id) return option.name;
    }
    return '';
  }

  Widget _roundAction(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38.w,
        height: 38.w,
        alignment: Alignment.center,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(11.r), border: Border.all(color: const Color(0xFFE6E7EA))),
        child: Icon(icon, size: 17.sp, color: AppColors.textSecondary),
      ),
    );
  }

  /// The row styling for one kind of audit event.
  static ActivityItem _activityRow(AuditEntry e) {
    final (icon, tone, bg) = switch (e.kind) {
      AuditEventKind.created =>
        (PhosphorIconsRegular.handshake, AppColors.textMuted2, AppColors.bgChipGrey),
      AuditEventKind.statusChanged =>
        (PhosphorIconsRegular.flag, AppColors.blueBright, AppColors.tintBlue),
      AuditEventKind.noteAdded =>
        (PhosphorIconsRegular.note, AppColors.success, AppColors.tintGreen),
      AuditEventKind.childAdded =>
        (PhosphorIconsRegular.paperclip, AppColors.warningDeep, AppColors.tintAmber),
      AuditEventKind.deleted =>
        (PhosphorIconsRegular.trash, AppColors.error, AppColors.bgChipGrey),
      _ => (PhosphorIconsRegular.pencilSimple, AppColors.textMuted2, AppColors.bgChipGrey),
    };
    return ActivityItem(
      icon: icon,
      tone: tone,
      bg: bg,
      title: e.title,
      sub: e.subtitle,
      time: relativeTime(e.at),
    );
  }

  /// The customer's real audit trail.
  ///
  /// It refetches off the API write tick, so **every** successful POST/PUT/PATCH/
  /// DELETE the app makes lands here — a status change, an upsell, a
  /// reassignment, a ticked task, a note, an upload — without each of those call
  /// sites having to remember this card exists.
  ///
  /// Empty in mock mode, on failure, and for a user without `view_audit_log`
  /// (which 403s), in which case the card is not rendered at all rather than
  /// showing an invented history. That is a deliberate change: it used to render
  /// four hard-coded events that looked like real ones.
  Widget _activityLogCard(Customer cust) {
    final entries =
        ref.watch(customerActivityLogProvider(cust.id)).valueOrNull ?? const [];
    if (entries.isEmpty) return const SizedBox.shrink();
    final items = [for (final e in entries) _activityRow(e)];
    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.fromLTRB(16.r, 16.r, 16.r, 6.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.clockCounterClockwise,
                  size: 16.sp, color: AppColors.textLabelAlt),
              SizedBox(width: 7.w),
              Text('Activity log',
                  style: AppText.custom(
                      size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          SizedBox(height: 12.h),
          ActivityTimeline(items: items),
        ],
      ),
    );
  }

  Widget _bottomBar(Customer cust) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 28.h),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderCardSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => ref.read(toastProvider.notifier).show('Calling ${cust.name.split(' ').first}…'),
              child: Container(
                height: 52.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(13.r)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsRegular.phone, size: 19.sp, color: AppColors.white),
                    SizedBox(width: 9.w),
                    Text('Call', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.white)),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: 10.w),
          _squareAction(PhosphorIconsRegular.whatsappLogo, AppColors.blueCta, () => ref.read(toastProvider.notifier).show('Opening WhatsApp…'), border: const Color(0xFFC9DCF5)),
          SizedBox(width: 10.w),
          // The pencil beside WhatsApp opens the customer's edit form — the
          // same schema-driven form the org configures, not a note composer.
          _squareAction(PhosphorIconsBold.pencilSimple, AppColors.white,
              () {
                if (ensurePermission(ref, 'customer', PermVerb.update)) {
                  context.push('${Routes.editCustomer}?id=${cust.id}');
                }
              },
              border: const Color(0xFFB9C2D8), borderWidth: 1.5),
        ],
      ),
    );
  }

  Widget _squareAction(IconData icon, Color bg, VoidCallback onTap, {required Color border, double borderWidth = 1}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52.w,
        height: 52.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(13.r),
          border: Border.all(color: border, width: borderWidth),
        ),
        child: Icon(icon, size: 22.sp, color: AppColors.navy),
      ),
    );
  }
}
