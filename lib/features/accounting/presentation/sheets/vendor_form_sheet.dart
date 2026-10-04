import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/accounting_invalidation.dart';
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/settlement_providers.dart';
import '../../domain/entities/acc_masters.dart';
import '../components/acc_pickers.dart';
import '../components/acc_widgets.dart';
import 'acc_sheet_scaffold.dart';

/// Whether another **active** vendor already has [name] (case-insensitive).
///
/// A duplicate active name is a 500 on the backend (handover §12.3), so the
/// app looks first and refuses with a sentence instead.
Future<bool> vendorNameTaken(WidgetRef ref, String name, {String? exceptId}) async {
  final n = name.trim().toLowerCase();
  if (n.isEmpty) return false;
  final hits = await ref.read(accountingRepositoryProvider).vendors(search: name.trim());
  return hits.any((v) => v.isActive && v.id != exceptId && v.name.trim().toLowerCase() == n);
}

const vendorDuplicateMessage = 'A vendor with this name already exists';

/// Add or edit a vendor (plan §4.10).
Future<Vendor?> showVendorFormSheet(BuildContext context, {Vendor? vendor}) =>
    showClozrSheet<Vendor>(context: context, builder: (_) => _VendorFormSheet(vendor: vendor));

class _VendorFormSheet extends ConsumerStatefulWidget {
  const _VendorFormSheet({this.vendor});
  final Vendor? vendor;

  @override
  ConsumerState<_VendorFormSheet> createState() => _VendorFormSheetState();
}

class _VendorFormSheetState extends ConsumerState<_VendorFormSheet> {
  late final _name = TextEditingController(text: widget.vendor?.name ?? '');
  late final _legal = TextEditingController(text: widget.vendor?.legalName ?? '');
  late final _email = TextEditingController(text: widget.vendor?.email ?? '');
  late final _phone = TextEditingController(text: widget.vendor?.phone ?? '');
  late final _address = TextEditingController(text: widget.vendor?.address ?? '');
  late final _account = TextEditingController(text: widget.vendor?.bankAccountNoMasked ?? '');
  late final _ifsc = TextEditingController(text: widget.vendor?.ifsc ?? '');
  late final _notes = TextEditingController(text: widget.vendor?.notes ?? '');
  late String? _state = widget.vendor?.stateCode;
  late bool _bodyCorporate = widget.vendor?.isBodyCorporate ?? false;
  late bool _gta = widget.vendor?.isGtaFcmOpted ?? false;
  late bool _smallTransporter = widget.vendor?.isSmallTransporterDeclared ?? false;
  bool _busy = false;
  AppError? _error;

  bool get _editing => widget.vendor != null;

  @override
  void dispose() {
    for (final c in [_name, _legal, _email, _phone, _address, _account, _ifsc, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ref.read(toastProvider.notifier).showError('Enter the vendor name');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final renamed = !_editing || widget.vendor!.name.trim().toLowerCase() != name.toLowerCase();
      if (renamed && await vendorNameTaken(ref, name, exceptId: widget.vendor?.id)) {
        if (!mounted) return;
        setState(() => _busy = false);
        ref.read(toastProvider.notifier).showError(vendorDuplicateMessage);
        return;
      }
      final fields = <String, Object?>{
        'name': name,
        'legal_name': _legal.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'address': _address.text.trim(),
        'state_code': _state,
        'bank_account_no_masked': _account.text.trim(),
        'ifsc': _ifsc.text.trim().toUpperCase(),
        'is_body_corporate': _bodyCorporate,
        'is_gta_fcm_opted': _gta,
        'is_small_transporter_declared': _smallTransporter,
        'notes': _notes.text.trim(),
      };
      final repo = ref.read(accountingRepositoryProvider);
      final saved = _editing ? await repo.updateVendor(widget.vendor!.id, fields) : await repo.createVendor(fields);
      invalidateAccountingReads(ref.invalidate);
      ref.invalidate(vendorsProvider);
      ref.invalidate(vendorDetailProvider);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show(_editing ? 'Vendor updated' : 'Vendor added');
      Navigator.of(context).pop(saved);
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // The duplicate-name race still ends in a 500 (§12.3).
        _error = e.type == AppErrorType.server
            ? AppError(type: e.type, message: vendorDuplicateMessage, statusCode: e.statusCode)
            : e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateName = ref.watch(gstStateNameProvider);
    return AccSheetScaffold(
      title: _editing ? 'Edit vendor' : 'Add vendor',
      submitLabel: _editing ? 'Save vendor' : 'Add vendor',
      busyLabel: 'Saving…',
      posts: false,
      busy: _busy,
      error: _error,
      onSubmit: _save,
      children: [
        AccInput(label: 'Name', required: true, controller: _name, hint: 'As you call them',
            textCapitalization: TextCapitalization.words),
        AccInput(label: 'Legal name', controller: _legal, hint: 'As on their invoices',
            textCapitalization: TextCapitalization.words),
        AccPickerBox(
          label: 'State',
          value: _state == null ? null : stateName(_state),
          hint: 'Select state…',
          icon: PhosphorIconsRegular.mapPin,
          onTap: () async {
            final code = await pickGstState(context, ref, selected: _state, title: 'Vendor state');
            if (code != null) setState(() => _state = code);
          },
        ),
        AccInput(label: 'Email', controller: _email, keyboardType: TextInputType.emailAddress),
        AccInput(label: 'Phone', controller: _phone, keyboardType: TextInputType.phone),
        AccInput(label: 'Address', controller: _address, maxLines: 3),
        AccDisclosure(
          title: 'Bank and tax details',
          initiallyOpen: _editing,
          children: [
            AccInput(label: 'Account no (masked)', controller: _account, hint: 'e.g. XXXX1234'),
            AccInput(label: 'IFSC', controller: _ifsc, textCapitalization: TextCapitalization.characters),
            AccCheckRow(label: 'Body corporate', value: _bodyCorporate, onChanged: (v) => setState(() => _bodyCorporate = v)),
            AccCheckRow(
                label: 'GTA opted for forward charge',
                value: _gta,
                onChanged: (v) => setState(() => _gta = v)),
            AccCheckRow(
                label: 'Small transporter declaration received',
                value: _smallTransporter,
                onChanged: (v) => setState(() => _smallTransporter = v)),
          ],
        ),
        AccInput(label: 'Notes', controller: _notes, maxLines: 3),
      ],
    );
  }
}
