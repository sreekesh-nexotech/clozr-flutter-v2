import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/accounting_invalidation.dart';
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/settlement_providers.dart';
import '../../domain/entities/acc_masters.dart';
import '../components/acc_pickers.dart';
import '../components/acc_widgets.dart';
import '../config/accounting_copy.dart';
import 'acc_sheet_scaffold.dart';

/// A customer's or vendor's tax profile (plan §5.3 / §4.10). [kind] is
/// `customer` or `vendor`. A party with no profile yet (404) opens blank —
/// "unregistered, no GSTIN" — and saving creates it.
Future<PartyTaxProfile?> showPartyTaxProfileSheet(
  BuildContext context, {
  required String kind,
  required String partyId,
  String? title,
}) =>
    showClozrSheet<PartyTaxProfile>(
      context: context,
      builder: (_) => _PartyTaxProfileSheet(kind: kind, partyId: partyId, title: title),
    );

const _gstinChars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

/// Whether [gstin] is well-formed and its 15th character is the correct
/// mod-36 check digit. The server validates too; this just catches a typo
/// before the round trip.
bool gstinValid(String gstin) {
  final g = gstin.toUpperCase();
  if (!RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$').hasMatch(g)) return false;
  var sum = 0;
  for (var i = 0; i < 14; i++) {
    final product = _gstinChars.indexOf(g[i]) * (i.isOdd ? 2 : 1);
    sum += product ~/ 36 + product % 36;
  }
  final check = (36 - sum % 36) % 36;
  return g[14] == _gstinChars[check];
}

class _PartyTaxProfileSheet extends ConsumerWidget {
  const _PartyTaxProfileSheet({required this.kind, required this.partyId, this.title});
  final String kind;
  final String partyId;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(partyTaxProfileProvider((kind: kind, id: partyId)));
    return async.when(
      loading: () => SizedBox(
        height: 180.h,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.navy)),
      ),
      error: (e, _) => Padding(
        padding: EdgeInsets.fromLTRB(18.w, 8.h, 18.w, 28.h),
        child: ConflictBanner(
          error: e is AppError ? e : const AppError(type: AppErrorType.unknown, message: 'Could not load the tax profile.'),
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(partyTaxProfileProvider((kind: kind, id: partyId))),
        ),
      ),
      data: (p) => _Form(kind: kind, partyId: partyId, title: title, profile: p),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.kind, required this.partyId, required this.profile, this.title});
  final String kind;
  final String partyId;
  final String? title;
  final PartyTaxProfile profile;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late String _reg = widget.profile.registrationType ?? 'UNREGISTERED';
  late final _gstin = TextEditingController(text: widget.profile.gstin ?? '');
  late final _pan = TextEditingController(text: widget.profile.pan ?? '');
  late String? _state = widget.profile.stateCode;
  late String? _entityKind = widget.profile.entityKind;
  late bool _tds = widget.profile.tdsApplicable;
  late bool _bodyCorporate = widget.profile.isBodyCorporate;
  late String? _tdsNature = widget.profile.tdsNatureDefault;
  DateTime _from = DateTime.now();
  String? _gstinError;
  bool _busy = false;
  AppError? _error;

  bool get _needsGstin => const {'REGISTERED', 'COMPOSITION', 'SEZ', 'GOVERNMENT'}.contains(_reg);

  @override
  void dispose() {
    _gstin.dispose();
    _pan.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final gstin = _gstin.text.trim().toUpperCase();
    if (_needsGstin && gstin.isEmpty) {
      setState(() => _gstinError = 'Enter the GSTIN');
      return;
    }
    if (gstin.isNotEmpty && !gstinValid(gstin)) {
      setState(() => _gstinError = 'This GSTIN is not valid — check for a typo');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _gstinError = null;
    });
    try {
      final saved = await ref.read(accountingRepositoryProvider).savePartyTaxProfile(widget.kind, widget.partyId, {
        'registration_type': _reg,
        'gstin': gstin,
        'state_code': _state,
        'pan': _pan.text.trim().toUpperCase(),
        'entity_kind': _entityKind,
        'tds_applicable': _tds,
        'is_body_corporate': _bodyCorporate,
        'tds_nature_default': _tdsNature,
        'effective_from': isoDay(_from),
      });
      ref.invalidate(partyTaxProfileProvider((kind: widget.kind, id: widget.partyId)));
      invalidateAccountingReads(ref.invalidate);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Tax profile saved');
      Navigator.of(context).pop(saved);
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (e.code == 'GSTIN_INVALID') {
          _gstinError = 'The GSTIN failed the server check';
        } else {
          _error = e;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = ref.watch(accPermProvider('acc_setup')).update;
    final stateName = ref.watch(gstStateNameProvider);
    final fields = <Widget>[
      AccChoiceChips(
        label: 'GST registration',
        options: registrationTypeLabels,
        selected: _reg,
        onSelected: (v) => setState(() => _reg = v),
      ),
      if (_reg != 'UNREGISTERED' && _reg != 'OVERSEAS')
        AccInput(
          label: 'GSTIN',
          required: _needsGstin,
          controller: _gstin,
          hint: '15 characters',
          errorText: _gstinError,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[0-9A-Za-z]')),
            LengthLimitingTextInputFormatter(15),
          ],
          onChanged: (_) => setState(() => _gstinError = null),
        ),
      AccPickerBox(
        label: 'State',
        value: _state == null ? null : stateName(_state),
        hint: 'Select state…',
        icon: PhosphorIconsRegular.mapPin,
        onTap: () async {
          final code = await pickGstState(context, ref, selected: _state, title: 'State');
          if (code != null) setState(() => _state = code);
        },
      ),
      AccInput(
        label: 'PAN',
        controller: _pan,
        hint: '10 characters',
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[0-9A-Za-z]')),
          LengthLimitingTextInputFormatter(10),
        ],
      ),
      AccChoiceChips(
        label: 'Entity',
        options: entityKindLabels,
        selected: _entityKind,
        onSelected: (v) => setState(() => _entityKind = v),
      ),
      AccCheckRow(
        label: widget.kind == 'vendor' ? 'TDS applies to payments' : 'Deducts TDS from our invoices',
        value: _tds,
        onChanged: (v) => setState(() => _tds = v),
      ),
      if (_tds)
        AccPickerBox(
          label: 'Default TDS nature',
          value: _tdsNature == null ? null : tdsNatures[_tdsNature],
          hint: 'Select nature…',
          onTap: () async {
            final n = await pickTdsNature(context, selected: _tdsNature);
            if (n != null) setState(() => _tdsNature = n);
          },
        ),
      AccCheckRow(label: 'Body corporate', value: _bodyCorporate, onChanged: (v) => setState(() => _bodyCorporate = v)),
      AccDateBox(label: 'Effective from', value: _from, onChanged: (d) => setState(() => _from = d ?? _from)),
    ];
    return AccSheetScaffold(
      title: widget.title ?? 'Tax profile',
      submitLabel: 'Save tax profile',
      busyLabel: 'Saving…',
      posts: false,
      busy: _busy,
      error: _error,
      submitEnabled: canEdit,
      onSubmit: _save,
      children: [
        if (!canEdit)
          const AccInfoBanner('Only people with accounting setup rights can change tax profiles.',
              icon: PhosphorIconsRegular.lock),
        if (!widget.profile.exists && canEdit)
          const AccInfoBanner('No tax profile yet — treated as unregistered with no GSTIN until one is saved.'),
        if (canEdit) ...fields else IgnorePointer(child: Opacity(opacity: 0.7, child: Column(children: [
          for (int i = 0; i < fields.length; i++) ...[if (i > 0) SizedBox(height: 13.h), fields[i]],
        ]))),
      ],
    );
  }
}
