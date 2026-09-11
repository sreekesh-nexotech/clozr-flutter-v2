import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/api/roster.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/models/note.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/notes_thread.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/crm_notes_providers.dart';
import '../../application/providers/crm_catalog_providers.dart';
import '../../application/providers/crm_tasks_providers.dart';
import '../../application/providers/crm_module_schema_providers.dart';
import '../../application/record_rows.dart';
import '../../application/providers/customers_providers.dart';
import '../sheets/reassign_owner_sheet.dart';
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
import '../../application/providers/attachments_providers.dart';
import 'package:file_picker/file_picker.dart';
import '../../domain/entities/audit_entry.dart';
import '../../../../core/utils/relative_time.dart';
import '../sheets/add_followup_sheet.dart';
import '../sheets/add_task_sheet.dart';
import '../../../../core/utils/attachment_link.dart';
import '../../../../core/config/api_config.dart';
import '../../domain/entities/lead_file.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/invoice.dart';
import '../../domain/entities/followup.dart';
import '../../domain/entities/crm_task.dart';
import '../../domain/entities/call_log.dart';
import '../components/crm_async.dart';
import '../components/crm_check_box.dart';
import '../components/crm_detail_parts.dart';
import '../components/inline_edit_row.dart';
import 'crm_status_sheet.dart';

class CustomerDetailScreen extends ConsumerStatefulWidget {
  const CustomerDetailScreen({super.key});

  @override
  ConsumerState<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  int _tab = 0;
  bool _infoMore = false;

  /// True while a file upload is in flight, so the CTA reports progress and
  /// refuses a second batch on top of the first.
  bool _uploading = false;

  /// True while an upsell POST is in flight. The action is reachable from three
  /// places — the overflow menu, the Upsell button and the Leads tab's CTA — and
  /// it creates a record, so a second tap during the round trip would raise a
  /// second lead. Two were observed in one audit trail, 29s apart.
  bool _upselling = false;
  final _notesKey = GlobalKey<NotesThreadState>();

  static const _tabLabels = ['Tasks', 'Call log', 'Follow-ups', 'Payments', 'Leads', 'Files'];

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
    showActionMenu(
      context,
      actions: [
        MenuAction(icon: PhosphorIconsFill.phone, label: 'Call customer', onTap: () => toast.show('Calling $first…')),
        MenuAction(icon: PhosphorIconsRegular.whatsappLogo, label: 'WhatsApp chat', onTap: () => toast.show('Opening WhatsApp…')),
        MenuAction(
            icon: PhosphorIconsRegular.filePlus,
            label: 'Create quote',
            onTap: () => _createQuote(cust)),
        MenuAction(
            icon: PhosphorIconsRegular.wallet,
            label: 'Record payment',
            onTap: () => _recordPayment(cust)),
        MenuAction(
          icon: PhosphorIconsFill.trendUp,
          label: 'Create upsell lead',
          enabled: !_upselling,
          sublabel: _upselling ? 'Already raising one…' : null,
          onTap: () => _createUpsell(cust),
        ),
        // The bottom bar's pencil now opens the edit form, so the note
        // composer keeps its route to the user here — the same place the lead
        // and task screens offer it.
        MenuAction(
            icon: PhosphorIconsRegular.notePencil,
            label: 'Add note',
            onTap: _focusNotes),
        MenuAction(
            icon: PhosphorIconsRegular.archive,
            label: 'Archive customer',
            destructive: true,
            onTap: () => _archiveCustomer(cust)),
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

  // ── Archive ──

  /// Archives the customer — `PATCH { is_archived: true }`.
  ///
  /// Behind a confirmation, and it leaves the screen on success: the list
  /// excludes archived customers by default (`?is_archived=true` to see them),
  /// so staying here would sit on a record that has dropped out of every list
  /// behind it.
  Future<void> _archiveCustomer(Customer cust) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive customer?'),
        content: Text('${cust.name} will be hidden from the customers list. '
            'Their quotes, payments and history are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Archive', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final toast = ref.read(toastProvider.notifier);
    try {
      await ref
          .read(customersRepositoryProvider)
          .updateCustomer(cust.id, {'is_archived': true});
    } on Object catch (e) {
      if (!mounted) return;
      toast.showError(e is AppError ? e.message : 'Could not archive the customer.');
      return;
    }
    if (!mounted) return;
    // The `customersScopedProvider` **family**, not the thin `customersProvider`
    // wrapper around one of its members — the family is what the Customers
    // list screen's own query (`customersListProvider`, a different member,
    // keyed by the drawer's filters) actually needs invalidated to refetch.
    ref.invalidate(customersScopedProvider);
    // Leave first: this record is gone from the list this screen was opened
    // from, and its own providers would keep refetching a row nothing lists.
    context.pop();
    toast.show('Customer archived');
  }

  /// The customer's owner.
  ///
  /// The mapped value first, then what this session last wrote. `assigned_to` is
  /// absent from both the list and the retrieve payload for an org that has not
  /// made it visible, so without the fallback a successful reassignment had
  /// nothing to show and the block read "Unknown" indefinitely. Server value
  /// wins whenever there is one, so this disappears on its own once the field is
  /// exposed.
  String _ownerOf(Customer cust) {
    if (cust.owner.isNotEmpty) return cust.owner;
    return ref.watch(customerOwnerOverrideProvider)[cust.id] ?? '';
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

  /// Writes the new status, then refreshes the record and the list so the pill
  /// here and the tab counts there follow.
  Future<void> _setStatus(Customer cust, String statusId) async {
    final toast = ref.read(toastProvider.notifier);
    try {
      await ref
          .read(customersRepositoryProvider)
          .updateCustomer(cust.id, {'status': statusId});
    } on Object catch (e) {
      if (!mounted) return;
      // A rejected write must not leave a status on screen that never saved.
      toast.showError(e is AppError ? e.message : 'Could not update the status.');
      return;
    }
    if (!mounted) return;
    ref.invalidate(customersScopedProvider);
    ref.invalidate(customerRowProvider(cust.id));
    toast.show('Status updated');
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

  // ── Owner & assignees ──

  /// Reassigns the account manager (`assigned_to`).
  ///
  /// Candidates come from the org roster: unlike a lead, a customer has no
  /// `assignable-users` endpoint, so there is no server-side opinion about who
  /// is eligible for *this* record.
  Future<void> _reassignOwner(Customer cust) async {
    final roster = ref.read(rosterProvider);
    final toast = ref.read(toastProvider.notifier);
    if (roster.isEmpty) {
      toast.show('No teammates have loaded yet — try again in a moment.');
      return;
    }
    final picked = await showReassignOwnerSheet(
      context: context,
      users: [for (final u in roster) CatalogOption(id: u.id, name: u.name)],
      currentOwnerId: _ownerOf(cust),
    );
    if (picked == null || !mounted) return;
    if (UserDirectory.mapUserId(picked) == _ownerOf(cust)) return; // unchanged

    final id = UserDirectory.realUserId(picked);
    if (id == null) {
      toast.showError('That user is not one the server knows.');
      return;
    }
    try {
      await ref
          .read(customersRepositoryProvider)
          .updateCustomer(cust.id, {'assigned_to': id});
    } on Object catch (e) {
      if (!mounted) return;
      toast.showError(e is AppError ? e.message : 'Could not reassign the owner.');
      return;
    }
    if (!mounted) return;
    // Remembered because the payload will not echo it back — see
    // [customerOwnerOverrideProvider].
    ref.read(customerOwnerOverrideProvider.notifier).update(
        (state) => {...state, cust.id: UserDirectory.mapUserId(id)});
    ref.invalidate(customersScopedProvider);
    ref.invalidate(customerRowProvider(cust.id));
    toast.show('Owner reassigned');
  }

  /// Adds or removes the customer's assignees.
  ///
  /// `assignees` is a many-to-many, so the write replaces the whole list — there
  /// is no add-one endpoint. Built from [Customer.team], **not** the display list
  /// in the row above: that one has the owner filtered out for readability, and
  /// saving it would silently unassign them.
  Future<void> _editAssignees(Customer cust) async {
    final roster = ref.read(rosterProvider);
    final picked = await showOptionPicker(
      context: context,
      title: 'Assignees',
      multi: true,
      options: [for (final u in roster) CatalogOption(id: u.id, name: u.name)],
      selected: {...cust.team},
      emptyNote: 'No teammates have loaded yet. Open a few records, or ask an '
          'admin to check your access to the members list.',
    );
    if (picked == null || !mounted) return;

    // Only ids the server knows; a prototype id is dropped rather than sent.
    final ids = [
      for (final id in picked)
        if (UserDirectory.realUserId(id) != null) UserDirectory.realUserId(id)!,
    ];
    if (ids.length == cust.team.length &&
        ids.toSet().containsAll(cust.team.map(UserDirectory.realUserId))) {
      return; // nothing actually changed
    }

    final toast = ref.read(toastProvider.notifier);
    try {
      await ref
          .read(customersRepositoryProvider)
          .updateCustomer(cust.id, {'assignees': ids});
    } on Object catch (e) {
      if (!mounted) return;
      toast.showError(e is AppError ? e.message : 'Could not update the assignees.');
      return;
    }
    if (!mounted) return;
    ref.invalidate(customersScopedProvider);
    ref.invalidate(customerRowProvider(cust.id));
    toast.show(ids.isEmpty ? 'Assignees cleared' : 'Assignees updated');
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
    if (cust == null) {
      return _stateScaffold(const EmptyState(
        icon: PhosphorIconsRegular.userCircle,
        title: 'Customer not found',
        body: 'This customer may have been removed or you no longer have access to it.',
      ));
    }

    final meta = StatusMeta$.customer[cust.status] ?? StatusMeta$.customer['active']!;

    // Notes thread (#13). `apiModel` is what wires it to the backend: without
    // it the thread stays local-only even in API mode, so a note — and any
    // file attached to it — was composed, shown, and never sent anywhere. The
    // builder below is the **mock-mode** seed; the remote notifier ignores it
    // and loads `GET /crm/notes/?related_to=customer&related_to_id=…` instead.
    final notesSeed = CrmNotesSeed(cust.id, () => [
          NoteEntry(
            id: '${cust.id}-n0',
            author: 'You',
            time: '2h ago',
            via: 'Call',
            body: 'Spoke with ${cust.name.split(' ').first}. Ongoing work on track; discussing an upsell.',
          ),
          NoteEntry(
            id: '${cust.id}-n1',
            author: 'Anjana Menon',
            time: '1d ago',
            via: 'Email',
            avatarColor: AppColors.blueBright,
            body: 'Shared the revised BOQ. Client happy with progress on ${cust.project}.',
          ),
          NoteEntry(
            id: '${cust.id}-n2',
            author: 'You',
            time: '3d ago',
            body: '${cust.industry} account since ${cust.since}. Value ${cust.value}.',
          ),
        ], apiModel: 'customer');
    final notes = ref.watch(crmNotesProvider(notesSeed));

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
                _profileCard(cust, meta),
                SizedBox(height: 14.h),
                _scoreCard(cust),
                SizedBox(height: 14.h),
                _infoCard(cust),
                SizedBox(height: 14.h),
                _activityCard(cust),
                SizedBox(height: 14.h),
                NotesThread(
                  author: ref.watch(noteAuthorProvider),
                  key: _notesKey,
                  notes: notes,
                  onAddNote: (body, atts) =>
                      ref.read(crmNotesProvider(notesSeed).notifier).addNote(body, atts, ref.read(noteAuthorProvider)),
                  onAddReply: (noteId, body) =>
                      ref.read(crmNotesProvider(notesSeed).notifier).addReply(noteId, body, ref.read(noteAuthorProvider)),
                ),
                SizedBox(height: 14.h),
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
    // Company when there is one, location otherwise.
    //
    // Both are read from the **detail row** first: `cust` comes from the list,
    // which is trimmed to the org's `list` config and need not carry
    // `organization_name` or `address` at all (this org's does not). The detail
    // row does, and it is already fetched for the information card below — so the
    // header fills in the moment it lands instead of staying blank.
    final row = ref.watch(customerRowProvider(cust.id)).valueOrNull;
    String fromRow(String key) => (row?[key] ?? '').toString().trim();
    final company = fromRow('organization_name').isNotEmpty
        ? fromRow('organization_name')
        : (cust.company ?? '').trim();
    final location = fromRow('address').isNotEmpty
        ? fromRow('address')
        : cust.location.trim();
    final subtitle = company.isNotEmpty ? company : location;

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
                child: Text(cust.initials, style: AppText.custom(size: 17, weight: FontWeight.w700, color: AppColors.navy, letterSpacing: 0.4)),
              ),
              SizedBox(width: 13.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(cust.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.custom(size: 20, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
                        ),
                        if (cust.isUpsell) ...[SizedBox(width: 8.w), _upsellBadge()],
                      ],
                    ),
                    // The id used to lead this line as "#C2001 · Kalyan Silks".
                    // Server ids are UUIDs, which read as noise and crowd out the
                    // company, so only the human-meaningful half is shown — and
                    // nothing at all when the customer carries neither company
                    // nor location. Same treatment as the lead header.
                    if (subtitle.isNotEmpty) ...[
                      SizedBox(height: 3.h),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                    ],
                    SizedBox(height: 5.h),
                    Row(
                      children: [
                        Icon(PhosphorIconsRegular.clock, size: 13.sp, color: AppColors.textPlaceholder),
                        SizedBox(width: 5.w),
                        Text('Customer since ${cust.since}', style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textMuted2)),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(cust.value, style: AppText.custom(size: 20, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
                  SizedBox(height: 1.h),
                  Text('VALUE', style: AppText.custom(size: 10, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.4)),
                ],
              ),
            ],
          ),
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
                        SizedBox(width: 6.w),
                        Icon(PhosphorIconsBold.caretDown, size: 11.sp, color: AppColors.textMuted2),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: GestureDetector(
                  onTap: () => _createUpsell(cust),
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
    final score = cust.score;
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
  /// loaded (and in mock mode). Keeps the screen looking exactly as it did
  /// before this became configurable.
  ///
  /// The two trailing placeholder rows are gone from the schema-driven path:
  /// "Warranty period" was always a hard `—`, and "Custom fields: Configured in
  /// web app" stood in for data the schema actually delivers, as
  /// `custom_fields.<name>` columns that [recordRows] renders like any other.
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
        ('Warranty period', '—'),
        ('Custom fields', 'Configured in web app'),
      ];

  /// Saves one edited field of the customer information card
  /// (`PATCH /crm/customers/{id}/`).
  ///
  /// The column name is the write key here: a customer's status is stored as
  /// plain `status`, unlike a lead's `status_id` — which is why the shared row
  /// takes the mapping from its caller rather than assuming the Lead one.
  Future<void> _saveField(
      Customer cust, String key, Object? value, String label) async {
    try {
      await ref
          .read(customersRepositoryProvider)
          .updateCustomer(cust.id, {key: value});
      if (!mounted) return;
      ref.invalidate(customerRowProvider(cust.id));
      ref.invalidate(customersScopedProvider);
      ref.read(toastProvider.notifier).show('$label updated');
    } on AppError catch (e) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).showError(e.message);
    }
  }

  Widget _infoCard(Customer cust) {
    // The org's own detail layout drives these rows: which fields, in what
    // order, under what labels. Empty schema (or a record that has not landed)
    // → the built-in list above.
    final schema = ref.watch(customerDetailSchemaProvider);
    final row = ref.watch(customerRowProvider(cust.id)).valueOrNull;
    final all = (schema.isEmpty || row == null)
        ? [for (final r in _fallbackInfoRows(cust)) (r.$1, r.$2, null)]
        : [
            // `name` is the page header and `status` is the pill above; the
            // people block below owns the owner/assignee columns.
            for (final r in recordRows(row, schema, skip: const {
              'name',
              'status',
              'lead_owner',
              'assignees',
              'assigned_team',
            }))
              (r.label, r.value, r.column),
          ];
    // Long layouts stay behind "Show more"; a short one shows whole. The
    // built-in list is always 11 rows so the toggle used to be unconditional —
    // an org layout can be shorter than the collapse point, and a "Show more"
    // that reveals nothing is worse than none.
    const collapseAt = 7;
    final collapsible = all.length > collapseAt;
    final rows = (_infoMore || !collapsible) ? all : all.take(collapseAt).toList();
    final ownerId = _ownerOf(cust);
    final owner = MockUsers.of(ownerId);
    final assignees = cust.team.where((t) => t != ownerId).toList();
    final teamName = () {
      final parts = owner.role.split('·');
      return parts.length > 1 ? parts[1].trim() : 'Team Kochi';
    }();

    return ClozrCard(
      radius: 18,
      padding: EdgeInsets.all(18.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Customer information', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 6.h),
          // Long-press a row to edit it in place; a row that cannot be edited
          // says why rather than ignoring the press.
          for (final r in rows)
            InlineEditRow(
              label: r.$1,
              display: r.$2,
              column: r.$3,
              rawValue: row?[r.$3?.name],
              editForm: 'Edit customer',
              onSave: (key, value) => _saveField(cust, key, value, r.$1),
              onBlocked: (msg) => ref.read(toastProvider.notifier).show(msg),
              child: DetailInfoRow(label: r.$1, value: r.$2),
            ),
          if (collapsible)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _infoMore = !_infoMore),
            child: Container(
              margin: EdgeInsets.only(top: 6.h),
              padding: EdgeInsets.only(top: 11.h, bottom: 2.h),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF3F4F5)))),
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
          SizedBox(height: 18.h),
          Text('OWNER & ASSIGNEES', style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.6)),
          SizedBox(height: 4.h),
          Container(
            padding: EdgeInsets.symmetric(vertical: 10.h),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
            child: Row(
              children: [
                Container(
                  width: 42.w,
                  height: 42.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: owner.color, borderRadius: BorderRadius.circular(12.r)),
                  child: Text(owner.initials, style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.white)),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(owner.name, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                      SizedBox(height: 1.h),
                      Text('Account owner', style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                _roundAction(PhosphorIconsRegular.arrowsClockwise, () => _reassignOwner(cust)),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(vertical: 10.h),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Assignees', style: AppText.caption(color: AppColors.textMuted)),
                      SizedBox(height: 4.h),
                      if (assignees.isEmpty)
                        Text('No assignees yet', style: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textPlaceholder))
                      else
                        Text(assignees.map((t) => MockUsers.of(t).name.split(' ').first).join(', '),
                            style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                _roundAction(PhosphorIconsRegular.userPlus, () => _editAssignees(cust)),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: 10.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
            ),
          ),
        ],
      ),
    );
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

  /// The activity card's CTA — one create path per tab, each carrying the
  /// customer so the new record comes back in this screen's own scoped fetch.
  ///
  /// Tasks and follow-ups reuse the shared sheets, which already take a `lead`.
  /// A customer has no equivalent parameter on them yet, so those two are raised
  /// against the customer's originating lead when it has one; without one the
  /// sheet would create an unattached record, so it says so instead of doing
  /// that silently.
  Future<void> _activityCta(Customer cust) async {
    final toast = ref.read(toastProvider.notifier);
    final lead = cust.leadId == null
        ? null
        : ref.read(leadByIdProvider(cust.leadId!));
    switch (_tab) {
      case 0:
        if (lead == null) {
          toast.show('Open the linked lead to add a task.');
          return;
        }
        await showAddTaskSheet(context, ref, lead: lead);
        ref.invalidate(customerTasksProvider(cust.id));
      case 1:
        toast.show('Log a call from the lead, or call from the bar below.');
      case 2:
        if (lead == null) {
          toast.show('Open the linked lead to schedule a follow-up.');
          return;
        }
        await showAddFollowupSheet(context, ref, lead: lead);
        ref.invalidate(customerFollowupsProvider(cust.id));
      case 3:
        toast.show('Payments are recorded against an invoice.');
      case 4:
        // "New lead" against a customer *is* an upsell.
        await _createUpsell(cust);
      default:
        await _uploadFiles(cust);
    }
  }

  /// Picks files off the device and posts them against this customer.
  ///
  /// One at a time, stopping at the first rejection — pushing the rest after a
  /// failure usually just repeats it, and a half-finished batch is easier to
  /// reason about when the count is reported.
  Future<void> _uploadFiles(Customer cust) async {
    if (_uploading) return;
    final toast = ref.read(toastProvider.notifier);

    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform
          .pickFiles(allowMultiple: true, withData: false);
    } on Object catch (e) {
      if (mounted) toast.showError('Could not open the file picker: $e');
      return;
    }
    if (picked == null || !mounted) return; // cancelled

    final files = [
      for (final f in picked.files)
        if (f.path != null) (path: f.path!, name: f.name),
    ];
    if (files.isEmpty) return;
    if (!ApiConfig.apiEnabled) {
      toast.show('Files upload once the app is connected to the API.');
      return;
    }

    setState(() => _uploading = true);
    final repo = ref.read(attachmentsRepositoryProvider);
    var stored = 0;
    String? failure;
    for (final f in files) {
      try {
        final saved = await repo.uploadFile(
          relatedTo: 'customer',
          relatedToId: cust.id,
          path: f.path,
          name: f.name,
        );
        if (saved != null) stored++;
      } on AppError catch (e) {
        failure = e.message;
        break;
      }
    }
    if (!mounted) return;
    setState(() => _uploading = false);

    if (stored > 0) ref.invalidate(customerFilesProvider(cust.id));
    if (failure != null) {
      // Say what landed before what didn't, so a partial batch is not read as a
      // total failure.
      toast.showError(stored == 0 ? failure : '$stored uploaded · $failure');
    } else {
      toast.show(stored == 1 ? 'File uploaded' : '$stored files uploaded');
    }
  }

  Widget _activityCard(Customer cust) {
    const ctaLabels = ['Add task', 'Log call', 'Add follow-up', 'Record payment', 'New lead', 'Upload file'];
    final ctaLabel = _uploading && _tab == 5 ? 'Uploading…' : ctaLabels[_tab];
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Customer activity', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary))),
              GestureDetector(
                onTap: () => _activityCta(cust),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(9.r), border: Border.all(color: const Color(0xFFE6E7EA))),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_tab == 5 ? PhosphorIconsRegular.uploadSimple : PhosphorIconsBold.plus, size: 13.sp, color: AppColors.textSecondary),
                      SizedBox(width: 6.w),
                      Text(ctaLabel, style: AppText.bodyStrong()),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          DetailUnderlineTabs(labels: _tabLabels, index: _tab, onChanged: (i) => setState(() => _tab = i)),
          SizedBox(height: 6.h),
          _tabContent(cust),
        ],
      ),
    );
  }

  Widget _tabContent(Customer cust) {
    switch (_tab) {
      case 0:
        return _tasksTab(cust);
      case 1:
        return _callLogTab(cust);
      case 2:
        return _followupsTab(cust);
      case 3:
        return _paymentsTab(cust);
      case 4:
        return _leadsTab(cust);
      default:
        return _filesTab(cust);
    }
  }

  /// Loading / error / empty / data for one activity tab.
  ///
  /// Every tab reads its own customer-scoped provider, so a failed fetch shows a
  /// retry rather than an empty state — "nothing logged yet" and "we couldn't
  /// load it" must not look the same.
  Widget _tabAsync<T>(
    AsyncValue<List<T>> async, {
    required Widget empty,
    required Widget Function(List<T> items) data,
    required VoidCallback onRetry,
  }) {
    return async.when(
      loading: () => ListSkeleton(
        itemCount: 3,
        itemHeight: 54.h,
        padding: EdgeInsets.symmetric(vertical: 14.h),
      ),
      error: (e, _) => ErrorState.forError(crmAppError(e), onRetry: onRetry),
      data: (items) => items.isEmpty ? empty : data(items),
    );
  }

  /// The pill a task's status renders as — the org's own lane name, not the
  /// built-in bucket it folds into. Twin of the lead detail's: an org running
  /// Open / In Progress / Completed / Cancelled read "To do" / "Done" /
  /// "Blocked" here, the last reversed in meaning rather than merely renamed.
  StatusMeta _taskMeta(CrmTask t) {
    final statuses = ref.watch(taskStatusCatalogProvider).valueOrNull ?? const [];
    final key = _taskStatus(t);
    if (key == t.status) return crmTaskStatusMeta(t, statuses);
    for (final s in statuses) {
      if (crmTaskStatusKey(name: s.name, type: s.statusType) == key) {
        return StatusMeta(s.name, crmTaskStatusColor(s));
      }
    }
    return StatusMeta$.task[key] ?? StatusMeta$.task['todo']!;
  }

  /// A task's status with any session override laid on top, so ticking one here
  /// and opening it on the task screen agree before either has refetched.
  String _taskStatus(CrmTask t) =>
      ref.watch(crmTaskStatusOverrideProvider)[t.id] ?? t.status;

  /// Ticks a task done, or reopens it. Optimistic, then rolled back if the write
  /// is refused — completing a task is not always allowed (an org can require a
  /// note first), and a tick that stayed ticked would be a lie.
  Future<void> _toggleTask(Customer cust, CrmTask t) async {
    final next = _taskStatus(t) == 'done' ? 'todo' : 'done';
    final prev = ref.read(crmTaskStatusOverrideProvider);
    ref.read(crmTaskStatusOverrideProvider.notifier).state = {...prev, t.id: next};

    if (ApiConfig.apiEnabled) {
      try {
        await ref.read(crmTasksRepositoryProvider).setTaskStatusByKey(t.id, next);
      } on AppError catch (e) {
        final rolled = {...ref.read(crmTaskStatusOverrideProvider)};
        if (prev.containsKey(t.id)) {
          rolled[t.id] = prev[t.id]!;
        } else {
          rolled.remove(t.id);
        }
        ref.read(crmTaskStatusOverrideProvider.notifier).state = rolled;
        if (mounted) ref.read(toastProvider.notifier).showError(e.message);
        return;
      }
      if (!mounted) return;
      ref.invalidate(customerTasksProvider(cust.id));
      ref.invalidate(crmTasksProvider);
      ref.invalidate(taskRowProvider(t.id));
    }
    if (mounted) {
      ref
          .read(toastProvider.notifier)
          .show(next == 'done' ? 'Task completed' : 'Task reopened');
    }
  }

  Widget _tasksTab(Customer cust) {
    return _tabAsync<CrmTask>(
      ref.watch(customerTasksProvider(cust.id)),
      onRetry: () => ref.invalidate(customerTasksProvider(cust.id)),
      empty: const DetailTabEmpty(
          icon: PhosphorIconsRegular.checkSquare,
          title: 'No tasks yet',
          body: 'Tasks linked to this customer will appear here.'),
      data: (tasks) => Column(
        children: [
          for (final t in tasks)
            Container(
              padding: EdgeInsets.symmetric(vertical: 13.h, horizontal: 2.w),
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CrmCheckBox(
                      done: _taskStatus(t) == 'done',
                      onTap: () => _toggleTask(cust, t)),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => context.push('${Routes.taskDetail}?id=${t.id}'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.titleClean,
                              style: AppText.custom(
                                      size: 14,
                                      weight: FontWeight.w600,
                                      color: _taskStatus(t) == 'done'
                                          ? AppColors.textPlaceholder
                                          : AppColors.textPrimary)
                                  .copyWith(
                                      decoration: _taskStatus(t) == 'done'
                                          ? TextDecoration.lineThrough
                                          : null)),
                          SizedBox(height: 3.h),
                          Text(
                              '${t.due} · ${MockUsers.of(t.assignee).name.split(' ').first} · ${t.priority}',
                              style: AppText.caption()),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  _miniPill(_taskMeta(t)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _callLogTab(Customer cust) {
    return _tabAsync<CallLog>(
      ref.watch(customerCallLogsProvider(cust.id)),
      onRetry: () => ref.invalidate(customerCallLogsProvider(cust.id)),
      empty: const DetailTabEmpty(
          icon: PhosphorIconsRegular.phone,
          title: 'No calls logged',
          body: 'Calls made to or received from this customer will appear here.'),
      data: (calls) => Column(children: [for (final c in calls) _callRow(c)]),
    );
  }

  /// One call row. The icon shows direction, the tint how it ended. A row with a
  /// recording is tappable — only ever the CDN copy, since the raw Exotel link
  /// 403s for anyone but Exotel.
  Widget _callRow(CallLog c) {
    final icon = c.isMissed
        ? PhosphorIconsRegular.phoneX
        : c.isIncoming
            ? PhosphorIconsRegular.phoneIncoming
            : PhosphorIconsRegular.phoneOutgoing;
    final tone = c.isMissed
        ? AppColors.error
        : !c.connected
            ? AppColors.textPlaceholder
            : c.isIncoming
                ? AppColors.blueBright
                : AppColors.success;
    final row = Container(
      padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 2.w),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38.w,
            height: 38.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: AppColors.bgChipGrey,
                borderRadius: BorderRadius.circular(11.r)),
            child: Icon(icon, size: 18.sp, color: tone),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(c.outcome, style: AppText.bodyStrong())),
                    if (c.hasRecording) ...[
                      SizedBox(width: 6.w),
                      Icon(PhosphorIconsFill.playCircle,
                          size: 16.sp, color: AppColors.blueBright),
                    ],
                  ],
                ),
                SizedBox(height: 2.h),
                Text(c.time, style: AppText.caption()),
                if (c.summary.isNotEmpty) ...[
                  SizedBox(height: 5.h),
                  Text(c.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(
                              size: 12.5,
                              weight: FontWeight.w500,
                              color: AppColors.textMuted)
                          .copyWith(height: 1.4)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (!c.hasRecording) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final failure = await openAttachment(c.recordingUrl);
        if (failure != null && mounted) {
          ref.read(toastProvider.notifier).showError(failure);
        }
      },
      child: row,
    );
  }

  Widget _followupsTab(Customer cust) {
    return _tabAsync<Followup>(
      ref.watch(customerFollowupsProvider(cust.id)),
      onRetry: () => ref.invalidate(customerFollowupsProvider(cust.id)),
      empty: const DetailTabEmpty(
          icon: PhosphorIconsRegular.clock,
          title: 'No follow-ups scheduled',
          body: 'Follow-ups scheduled for this customer will appear here.'),
      data: (fus) => Padding(
        padding: EdgeInsets.only(top: 12.h),
        child: Column(
          children: [
            for (final f in fus)
              Container(
                margin: EdgeInsets.only(bottom: 12.h),
                padding: EdgeInsets.all(14.r),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(color: AppColors.borderCardSoft)),
                child: GestureDetector(
                  onTap: () =>
                      context.push('${Routes.followupDetail}?id=${f.id}'),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42.w,
                        height: 42.w,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: const Color(0xFFEEF1F4),
                            borderRadius: BorderRadius.circular(12.r)),
                        child: Icon(PhosphorIconsRegular.calendarBlank,
                            size: 19.sp, color: AppColors.navy),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.title.isEmpty ? '${f.kind} follow-up' : f.title,
                                style: AppText.custom(
                                    size: 14.5,
                                    weight: FontWeight.w700,
                                    color: AppColors.textPrimary)),
                            SizedBox(height: 3.h),
                            Text('${f.kind} · ${f.contact}',
                                style: AppText.custom(
                                    size: 12.5,
                                    weight: FontWeight.w500,
                                    color: AppColors.textMuted2)),
                            SizedBox(height: 3.h),
                            Text('${f.due} · ${f.time}',
                                style: AppText.caption(
                                    color: AppColors.textPlaceholder)),
                          ],
                        ),
                      ),
                      _miniPill(StatusMeta$.followup[f.status] ??
                          StatusMeta$.followup['due']!),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The Payments tab — the **invoice header** per customer
  /// (`/quotations/payments/?customer_id=`), which is the level the docs render
  /// first; tapping through opens the installment rows.
  Widget _paymentsTab(Customer cust) {
    return _tabAsync<Invoice>(
      ref.watch(customerInvoicesProvider(cust.id)),
      onRetry: () => ref.invalidate(customerInvoicesProvider(cust.id)),
      empty: const DetailTabEmpty(
          icon: PhosphorIconsRegular.receipt,
          title: 'No payments yet',
          body: 'Invoices raised against this customer will appear here.'),
      data: (invoices) => Column(
        children: [
          for (final inv in invoices)
            Container(
              padding: EdgeInsets.symmetric(vertical: 13.h, horizontal: 2.w),
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    context.push('${Routes.invoiceDetail}?id=${inv.id}'),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38.w,
                      height: 38.w,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: AppColors.bgChipGrey,
                          borderRadius: BorderRadius.circular(11.r)),
                      child: Icon(PhosphorIconsRegular.receipt,
                          size: 18.sp, color: AppColors.textSecondary),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(inv.id,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.custom(
                                  size: 14,
                                  weight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                          SizedBox(height: 3.h),
                          Text(inv.type, style: AppText.caption()),
                        ],
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _miniPill(StatusMeta$.invoice[inv.status] ??
                            StatusMeta$.invoice['partial']!),
                        SizedBox(height: 5.h),
                        Text(inv.total,
                            style: AppText.custom(
                                size: 13.5,
                                weight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The Leads tab — `?parent_customer=`, which is the customer's **upsell**
  /// leads. The original source lead is not a child of the customer, so it is
  /// absent here by design; it lives in the record's `linked_leads`.
  Widget _leadsTab(Customer cust) {
    return _tabAsync<Lead>(
      ref.watch(customerLeadsProvider(cust.id)),
      onRetry: () => ref.invalidate(customerLeadsProvider(cust.id)),
      empty: const DetailTabEmpty(
          icon: PhosphorIconsRegular.users,
          title: 'No upsell leads',
          body: 'Leads raised against this customer will appear here.'),
      data: (leads) => Column(
        children: [
          for (final l in leads)
            Container(
              padding: EdgeInsets.symmetric(vertical: 13.h, horizontal: 2.w),
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.push('${Routes.leadDetail}?id=${l.id}'),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38.w,
                      height: 38.w,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: AppColors.bgChipGrey,
                          borderRadius: BorderRadius.circular(11.r)),
                      child: Text(l.initials,
                          style: AppText.custom(
                              size: 12,
                              weight: FontWeight.w700,
                              color: AppColors.navy)),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.custom(
                                  size: 14,
                                  weight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                          SizedBox(height: 3.h),
                          Text(l.project, style: AppText.caption()),
                        ],
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Text(l.value,
                        style: AppText.custom(
                            size: 13.5,
                            weight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The Files tab — the shared polymorphic attachments table, `related_to=
  /// customer`.
  Widget _filesTab(Customer cust) {
    return _tabAsync<LeadFile>(
      ref.watch(customerFilesProvider(cust.id)),
      onRetry: () => ref.invalidate(customerFilesProvider(cust.id)),
      empty: const DetailTabEmpty(
          icon: PhosphorIconsRegular.paperclip,
          title: 'No files shared',
          body: 'Drawings, BOQs and documents will appear here.'),
      data: (files) => Column(
        children: [
          for (final f in files)
            InkWell(
              onTap: () async {
                final failure = await openAttachment(f.url);
                if (failure != null && mounted) {
                  ref.read(toastProvider.notifier).showError(failure);
                }
              },
              borderRadius: BorderRadius.circular(10.r),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 2.w),
                child: Row(
                  children: [
                    Container(
                      width: 38.w,
                      height: 38.w,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: AppColors.bgChipGrey,
                          borderRadius: BorderRadius.circular(11.r)),
                      child: Icon(PhosphorIconsRegular.paperclip,
                          size: 18.sp, color: AppColors.textSecondary),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.custom(
                                  size: 14,
                                  weight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                          SizedBox(height: 3.h),
                          Text(
                              [
                                f.ext,
                                if (f.uploadedAt.isNotEmpty) f.uploadedAt,
                              ].join(' · '),
                              style: AppText.caption()),
                        ],
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Icon(PhosphorIconsRegular.arrowSquareOut,
                        size: 16.sp, color: AppColors.textPlaceholder),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniPill(StatusMeta meta) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 3.h),
      decoration: BoxDecoration(color: meta.color.withOpacity(0.09), borderRadius: BorderRadius.circular(7.r)),
      child: Text(meta.label, style: AppText.custom(size: 11, weight: FontWeight.w700, color: meta.color)),
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
              () => context.push('${Routes.editCustomer}?id=${cust.id}'),
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
