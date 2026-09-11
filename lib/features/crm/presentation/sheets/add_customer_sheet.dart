import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/phone_controller.dart';
import '../../../../core/widgets/phone_input_field.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/customers_providers.dart';
import '../../domain/entities/customer.dart';
import '../../application/providers/crm_module_schema_providers.dart';
import '../../application/providers/customer_activity_providers.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/view_schema.dart';
import '../components/lead_schema_form.dart';
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
  /// Reads the schema-driven form's values at submit time.
  final _schemaFormKey = GlobalKey<LeadSchemaFormState>();

  final _name = TextEditingController();
  final _company = TextEditingController();
  final _phone = PhoneController();
  final _email = TextEditingController();
  final _source = TextEditingController(text: 'Referral');
  final _value = TextEditingController();
  bool _showErrors = false;

  /// True while the create is in flight, so a second tap cannot post again.
  /// Without it two taps during the round trip make two customers — the same
  /// duplicate-create seen on tasks and upsells.
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _company, _email, _source, _value]) {
      c.dispose();
    }
    _phone.dispose();
    super.dispose();
  }

  bool get _nameOk => _name.text.trim().isNotEmpty;

  /// The org's own Customer layout — `GET /crm/customers/schema/?view_type=detail`.
  ///
  /// `detail`, not `form`, matching the follow-up and quote sheets: `form`
  /// introspects model fields only and returns none of the relational ones the
  /// form actually needs. Empty in mock mode, on a failed fetch, or for an org
  /// with no config — which is the signal to use the built-in six-field form.
  ViewSchema get _schema => widget.ref.read(customerDetailSchemaProvider);

  bool get _schemaDriven => _schema.editableColumns.isNotEmpty;

  /// Submits the org-configured form.
  ///
  /// The payload is whatever the schema said the form owns, under the names the
  /// API stores them as — so a field an admin adds tomorrow is saved with no code
  /// change. Required fields are the server's call: `name` missing comes back as
  /// a per-field message, which is more use than a guess made here.
  Future<void> _submitSchemaForm() async {
    final state = _schemaFormKey.currentState;
    if (state == null) return;
    setState(() => _saving = true);
    try {
      await widget.ref
          .read(customersRepositoryProvider)
          .createCustomer(state.payload);
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      widget.ref.read(toastProvider.notifier).showError(e.message);
      return;
    }
    if (!mounted) return;
    // `customersProvider` is a thin wrapper around one `customersScopedProvider`
    // family member — invalidating it alone just re-reads that same (still
    // cached, not refetched) member. The list screen watches a *different*
    // member of the same family (`customersListProvider`, keyed by the
    // drawer's filters), which this never touched at all — invalidating the
    // family itself is what actually forces every cached query, list screen
    // included, to refetch and pick up the new row.
    widget.ref.invalidate(customersScopedProvider);
    widget.ref.read(toastProvider.notifier).show('Customer added');
    Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (_schemaDriven) return _submitSchemaForm();
    setState(() => _showErrors = true);
    if (!_nameOk) {
      widget.ref.read(toastProvider.notifier).show('Enter a customer name');
      return;
    }
    final name = _name.text.trim();
    if (ApiConfig.apiEnabled) {
      setState(() => _saving = true);
      try {
        await widget.ref.read(customersRepositoryProvider).createCustomer({
          'name': name,
          'organization_name': _company.text.trim(),
          'email': _email.text.trim(),
          'phone': _phone.toE164() ?? '',
          // The deal value. Collected on the form but never sent before, so
          // whatever the user typed here was silently discarded. `revenue` is
          // the writable field behind the "Deal value" row on the detail page.
          'revenue': _value.text.trim(),
        });
        if (!mounted) return;
        // See the matching comment in `_submitSchemaForm` — the family itself
        // has to be invalidated for the list screen to actually refetch.
        widget.ref.invalidate(customersScopedProvider);
        widget.ref.read(toastProvider.notifier).show('Customer added');
        Navigator.of(context).pop();
      } on AppError catch (e) {
        if (!mounted) return;
        setState(() => _saving = false);
        widget.ref.read(toastProvider.notifier).showError(e.message);
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
      phone: _phone.toE164() ?? '—',
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
    // Wrapped in its own [Consumer]: `widget.ref` — handed down from the
    // screen that opened this sheet — reads the *current* provider value on
    // every rebuild, but is not the ref Riverpod ties this element's
    // subscriptions to, so watching through it never actually triggers a
    // rebuild on its own. The schema swap below used to happen only by
    // accident, whenever some unrelated `setState()` elsewhere in this
    // sheet (a text field's `onChanged`) happened to also re-run `build()`
    // after the fetch had already resolved in the background — which is
    // why the built-in fields sometimes stuck around long after the org's
    // own layout was ready. A `Consumer`'s own ref is the one that actually
    // rebuilds this subtree the moment the schema (or the status catalog)
    // resolves.
    return Consumer(builder: (context, ref, _) {
      final schema = ref.watch(customerDetailSchemaProvider);
      ref.watch(customerStatusCatalogProvider);
      if (schema.editableColumns.isNotEmpty) return _schemaSheet(context, ref, schema);
      return _builtInSheet(context);
    });
  }

  Widget _builtInSheet(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'New customer', onClose: () => Navigator.of(context).pop()),
        Flexible(
          child: SingleChildScrollView(
            // Typing in the last row hides the fields above it; dragging the
            // sheet is how you get them back.
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                      child: PhoneInputField(
                          label: 'Mobile', controller: _phone, hint: '98470 11001'),
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
                    // Source is **read-only** on the customer API — it is derived
                    // from the originating lead, so a manually created customer
                    // has none and there is no field to write. Offering a box
                    // that cannot be saved is worse than not offering one, so in
                    // API mode Deal value takes the row on its own. Mock mode
                    // keeps it: there it feeds the local draft.
                    if (!ApiConfig.apiEnabled) ...[
                      Expanded(child: AppTextField(label: 'Source', controller: _source, hint: 'Referral')),
                      SizedBox(width: 10.w),
                    ],
                    Expanded(
                      child: AppTextField(
                        label: 'Deal value (₹)',
                        controller: _value,
                        // A plain amount, not "₹12L". The API stores a decimal
                        // and there is no lakh/crore parser on the way in — the
                        // mock branch's digit-strip would have turned "₹12L"
                        // into 12, so the hint now asks for what is actually
                        // sent. The list and detail still *display* it as ₹12L.
                        hint: 'e.g. 1800000',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SheetSubmitBar(
            label: 'Create customer',
            icon: PhosphorIconsBold.plus,
            busy: _saving,
            busyLabel: 'Creating…',
            onTap: _submit),
      ],
    );
  }

  /// The org-configured sheet: one input per editable column the schema lists,
  /// in the org's order and under the org's labels.
  ///
  /// Two overrides are needed on top of the shared form:
  ///
  /// * **`writeKey`** — a customer writes its status as plain `status`, where the
  ///   Lead default renames it to `status_id`. Posting the wrong one is accepted
  ///   and ignored, so the status would silently never be set.
  /// * **`status` options** — the shared form resolves a foreign key by its
  ///   `relatedModel`, and it knows `LeadStatus` but not `CustomerStatus`. Without
  ///   this the picker would open empty on the one field most likely to be set.
  Widget _schemaSheet(BuildContext context, WidgetRef ref, ViewSchema schema) {
    final statuses = ref.watch(customerStatusesProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
            title: 'New customer', onClose: () => Navigator.of(context).pop()),
        Flexible(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 12.h),
            child: LeadSchemaForm(
              key: _schemaFormKey,
              schema: schema,
              row: null,
              writeKey: (c) => c.name,
              // `products` is a list of **objects**, not ids: the serializer
              // wants `{product_id, quantity}` and answers *"Expected a
              // dictionary, but got str"* for a bare id. Quantity defaults to 1
              // — this sheet has no per-line quantity control, and a quote is
              // where line quantities are actually set.
              writeMulti: (c, ids) => c.name == 'products'
                  ? [for (final id in ids) {'product_id': id, 'quantity': 1}]
                  : ids,
              optionsByColumn: {
                if (statuses.isNotEmpty)
                  'status': [
                    for (final s in statuses) CatalogOption(id: s.id, name: s.name),
                  ],
              },
            ),
          ),
        ),
        SheetSubmitBar(
            label: 'Create customer',
            icon: PhosphorIconsBold.plus,
            busy: _saving,
            busyLabel: 'Creating…',
            onTap: _submit),
      ],
    );
  }
}
