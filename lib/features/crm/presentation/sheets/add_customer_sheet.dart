import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/phone_controller.dart';
import '../../../../core/widgets/phone_input_field.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/customer_form_rules.dart';
import '../../application/providers/customers_providers.dart';
import '../../domain/entities/customer.dart';
import '../../application/providers/crm_module_schema_providers.dart';
import '../../application/providers/customer_activity_providers.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/view_schema.dart';
import '../components/customer_address_fields.dart';
import '../components/duplicate_notice.dart';
import '../components/lead_schema_form.dart';
import 'add_sheet_kit.dart';

/// Add customer — the webapp's `AddCustomerModal` in the mobile sheet's style:
/// the org's schema fields, then the billing / delivery address and GSTIN
/// block, with the org's duplicate policy reported as the webapp does.
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

/// A create the `warn` policy let through: the new customer and its match.
class _Settled {
  const _Settled(this.duplicate, this.customerId);
  final LeadDuplicate duplicate;
  final String? customerId;
}

class _AddCustomerSheetState extends State<_AddCustomerSheet> {
  /// Reads the schema-driven form's values at submit time.
  final _schemaFormKey = GlobalKey<LeadSchemaFormState>();
  final _scroll = ScrollController();
  final _address = CustomerAddressController();

  final _name = TextEditingController();
  final _company = TextEditingController();
  final _phone = PhoneController();
  final _email = TextEditingController();
  final _source = TextEditingController(text: 'Referral');
  final _value = TextEditingController();
  bool _showErrors = false;

  /// The server's per-field messages on the built-in form (`name`, `email`…).
  Map<String, String> _serverErrors = const {};

  /// True while the create is in flight, so a second tap cannot post again.
  /// Without it two taps during the round trip make two customers — the same
  /// duplicate-create seen on tasks and upsells.
  bool _saving = false;

  /// The org's duplicate rule refused the create (`block`).
  LeadDuplicate? _dup;

  /// The create succeeded but matched an existing record (`warn`). The form is
  /// then done — resubmitting would make another duplicate — so the footer
  /// becomes a single "Done".
  _Settled? _settled;

  @override
  void dispose() {
    for (final c in [_name, _company, _email, _source, _value]) {
      c.dispose();
    }
    _phone.dispose();
    _scroll.dispose();
    _address.dispose();
    super.dispose();
  }

  bool get _nameOk => _name.text.trim().isNotEmpty;

  /// The org's own Customer layout — `GET /crm/customers/schema/?view_type=detail`.
  ///
  /// `detail`, not `form`, matching the follow-up and quote sheets: `form`
  /// introspects model fields only and returns none of the relational ones the
  /// form actually needs. Empty in mock mode, on a failed fetch, or for an org
  /// with no config — which is the signal to use the built-in form.
  ViewSchema get _schema => widget.ref.read(customerDetailSchemaProvider);

  bool get _schemaDriven => _schema.editableColumns.isNotEmpty;

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  /// Posts [payload] and reports the outcome as the webapp does. [onFieldErrors]
  /// places the server's per-field messages that are not the address block's
  /// and returns the keys it could not show under an input.
  Future<void> _create(
    Map<String, dynamic> payload,
    Set<String> Function(Map<String, String> errors) onFieldErrors,
  ) async {
    setState(() {
      _saving = true;
      _dup = null;
    });
    final toast = widget.ref.read(toastProvider.notifier);
    try {
      final created = await widget.ref.read(customersRepositoryProvider).createCustomer(payload);
      if (!mounted) return;
      // `customersProvider` is a thin wrapper around one `customersScopedProvider`
      // family member; the list screen watches a different member, so the family
      // itself is invalidated to make every cached list refetch the new row.
      widget.ref.invalidate(customersScopedProvider);
      // `warn` policy: the 201 carries the match under `warnings` — and only
      // here, a later GET never reports it — so the sheet stays open to show it.
      final warned = LeadDuplicate.fromWarnings(created?.raw['warnings']);
      if (warned != null) {
        setState(() {
          _saving = false;
          _settled = _Settled(warned, created?.id);
        });
        _scrollToTop();
        toast.show('Customer created — possible duplicate');
        return;
      }
      toast.show('Customer created');
      Navigator.of(context).pop();
    } on AppError catch (e) {
      // This form explains every refusal itself (under the field, the
      // duplicate panel or its own toast) — keep the shell's raw
      // "field: msg" toast from repeating it.
      widget.ref.read(apiServiceProvider).handled(e);
      if (!mounted) return;
      setState(() => _saving = false);
      // `block` policy: 400 with `errors.duplicate`; nothing was created.
      final dup = LeadDuplicate.parse(e.extra?['duplicate']);
      if (dup != null) {
        setState(() => _dup = dup);
        _scrollToTop();
        toast.showError('This customer already exists');
        return;
      }
      // Field messages go under their inputs; a toast only for what has none.
      final errors = firstFieldErrors(e.fieldErrors);
      final inAddress = _address.showServerErrors(errors);
      final rest = {
        for (final x in errors.entries)
          if (!inAddress.contains(x.key)) x.key: x.value,
      };
      final unplaced = onFieldErrors(rest);
      if (rest.length == unplaced.length && _address.hasErrors) _address.scrollToFirstError();
      if (errors.isEmpty) {
        toast.showError(e.message);
      } else if (unplaced.isNotEmpty) {
        toast.showError(errors[unplaced.first]!);
      }
    }
  }

  /// Submits the org-configured form.
  ///
  /// The payload is whatever the schema said the form owns, under the names the
  /// API stores them as — so a field an admin adds tomorrow is saved with no code
  /// change — plus the address block.
  Future<void> _submitSchemaForm() async {
    final state = _schemaFormKey.currentState;
    if (state == null) return;
    // Only the name is required (webapp); its message sits under the field.
    if (_schema.column('name') != null && state.valueOf('name').trim().isEmpty) {
      state.showErrors({'name': customerNameRequiredMessage});
      _address.clearErrors();
      setState(() => _dup = null);
      return;
    }
    _address.clearErrors();
    if (state.validate().isNotEmpty) return;
    await _create(
      {...state.payload, ..._address.createPayload},
      (errors) {
        state.showErrors(errors);
        return {for (final k in errors.keys) if (!state.hasInlineError(k)) k};
      },
    );
  }

  static const _builtInKeys = {'name', 'organization_name', 'email', 'phone', 'revenue'};

  Future<void> _submit() async {
    if (_saving || _settled != null) return;
    if (_schemaDriven) return _submitSchemaForm();
    setState(() {
      _showErrors = true;
      _serverErrors = const {};
    });
    if (!_nameOk) return;
    final name = _name.text.trim();
    if (ApiConfig.apiEnabled) {
      await _create(
        {
          'name': name,
          'organization_name': _company.text.trim(),
          'email': _email.text.trim(),
          'phone': _phone.toE164() ?? '',
          // `revenue` is the writable field behind the "Deal value" row.
          'revenue': _value.text.trim(),
          ..._address.createPayload,
        },
        (errors) {
          setState(() => _serverErrors = {
                for (final e in errors.entries)
                  if (_builtInKeys.contains(e.key)) e.key: e.value,
              });
          return {for (final k in errors.keys) if (!_builtInKeys.contains(k)) k};
        },
      );
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
    widget.ref.read(toastProvider.notifier).show('Customer created');
    Navigator.of(context).pop();
  }

  /// Leaves the sheet for a matched (or the just-created) record.
  void _open(String route) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(route);
  }

  @override
  Widget build(BuildContext context) {
    // Wrapped in its own [Consumer]: `widget.ref` — handed down from the
    // screen that opened this sheet — is not the ref Riverpod ties this
    // element's subscriptions to, so watching through it never triggers a
    // rebuild. A `Consumer`'s own ref rebuilds this subtree the moment the
    // schema (or the status catalog) resolves.
    return Consumer(builder: (context, ref, _) {
      final schema = ref.watch(customerDetailSchemaProvider);
      ref.watch(customerStatusCatalogProvider);
      final body = schema.editableColumns.isNotEmpty
          ? _schemaForm(ref, schema)
          : _builtInFields();
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: 'Add customer', onClose: () => Navigator.of(context).pop()),
          Flexible(
            child: SingleChildScrollView(
              controller: _scroll,
              // Typing in the last row hides the fields above it; dragging the
              // sheet is how you get them back.
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(18.w, 4.h, 18.w, 12.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_dup != null)
                    DuplicateNotice(
                      duplicate: _dup!,
                      blocked: true,
                      subject: 'customer',
                      onOpenLead: (id) => _open('${Routes.leadDetail}?id=$id'),
                      onOpenCustomer: (id) => _open('${Routes.customerDetail}?id=$id'),
                    ),
                  if (_settled != null)
                    DuplicateNotice(
                      duplicate: _settled!.duplicate,
                      blocked: false,
                      subject: 'customer',
                      newLeadId: _settled!.customerId,
                      onOpenLead: (id) => _open('${Routes.leadDetail}?id=$id'),
                      onOpenCustomer: (id) => _open('${Routes.customerDetail}?id=$id'),
                    ),
                  body,
                  if (ApiConfig.apiEnabled) ...[
                    SizedBox(height: 18.h),
                    CustomerAddressFields(controller: _address),
                  ],
                ],
              ),
            ),
          ),
          if (_settled != null)
            SheetSubmitBar(
                label: 'Done',
                icon: PhosphorIconsBold.check,
                onTap: () => Navigator.of(context).pop())
          else
            SheetSubmitBar(
                label: 'Save customer',
                icon: PhosphorIconsBold.check,
                busy: _saving,
                busyLabel: 'Saving…',
                onTap: _submit),
        ],
      );
    });
  }

  Widget _builtInFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          label: 'Customer name',
          required: true,
          controller: _name,
          hint: 'e.g. Acme Retail Pvt Ltd',
          errorText: _showErrors && !_nameOk ? customerNameRequiredMessage : _serverErrors['name'],
          onChanged: (_) => setState(() => _serverErrors = {..._serverErrors}..remove('name')),
        ),
        SizedBox(height: 14.h),
        AppTextField(
          label: 'Company',
          controller: _company,
          hint: 'e.g. Meera Boutique',
          errorText: _serverErrors['organization_name'],
        ),
        SizedBox(height: 14.h),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: PhoneInputField(
                  label: 'Phone',
                  controller: _phone,
                  hint: '98470 11001',
                  errorText: _serverErrors['phone']),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: AppTextField(
                  label: 'Email',
                  controller: _email,
                  hint: 'name@company.in',
                  errorText: _serverErrors['email'],
                  keyboardType: TextInputType.emailAddress),
            ),
          ],
        ),
        SizedBox(height: 14.h),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Source is read-only on the customer API (derived from the
            // originating lead), so in API mode Deal value takes the row alone.
            // Mock mode keeps it: there it feeds the local draft.
            if (!ApiConfig.apiEnabled) ...[
              Expanded(child: AppTextField(label: 'Source', controller: _source, hint: 'Referral')),
              SizedBox(width: 10.w),
            ],
            Expanded(
              child: AppTextField(
                label: 'Deal value (₹)',
                controller: _value,
                // A plain amount: the API stores a decimal and there is no
                // lakh/crore parser on the way in.
                hint: 'e.g. 1800000',
                errorText: _serverErrors['revenue'],
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The org-configured form: one input per editable column the schema lists,
  /// in the org's order and under the org's labels — less the address / GSTIN
  /// columns, which the block below owns (webapp `isAddressFormField`).
  ///
  /// Overrides on top of the shared form:
  ///
  /// * **`writeKey`** — a customer writes its status as plain `status`, where the
  ///   Lead default renames it to `status_id`.
  /// * **`status` options** — the shared form knows `LeadStatus` but not
  ///   `CustomerStatus`; the org's starting (Active-type) status is pre-selected.
  /// * **`mobileRequired: false`** — only the name is required for a customer.
  Widget _schemaForm(WidgetRef ref, ViewSchema schema) {
    final statuses = ref.watch(customerStatusesProvider);
    final startStatus = defaultCustomerStatusId(statuses);
    return LeadSchemaForm(
      key: _schemaFormKey,
      schema: schema,
      row: null,
      mobileRequired: false,
                        requiredOnly: const {'name'},
      hints: const {'name': 'e.g. Acme Retail Pvt Ltd'},
      hiddenColumns: addressOwnedColumns,
      writeKey: (c) => c.name,
      // `products` is a list of **objects**, not ids: the serializer wants
      // `{product_id, quantity}`.
      writeMulti: (c, ids) => c.name == 'products'
          ? [for (final id in ids) {'product_id': id, 'quantity': 1}]
          : ids,
      initialChoices: {if (startStatus != null) 'status': startStatus},
      optionsByColumn: {
        if (statuses.isNotEmpty)
          'status': [
            for (final s in statuses) CatalogOption(id: s.id, name: s.name),
          ],
      },
    );
  }
}
