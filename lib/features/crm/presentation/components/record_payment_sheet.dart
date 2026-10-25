import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../accounting/application/providers/accounting_invalidation.dart';
import '../../../accounting/application/providers/accounting_providers.dart';
import '../../../accounting/domain/entities/acc_masters.dart';
import '../../../accounting/presentation/components/acc_pickers.dart';
import '../../../accounting/presentation/components/acc_widgets.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../sheets/add_sheet_kit.dart' show sheetDateLabel;
import '../../application/providers/customers_providers.dart';
import '../../application/providers/invoices_providers.dart';
import '../../application/providers/lead_lifecycle_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../../application/record_payment/record_payment_logic.dart';
import '../../application/record_payment/record_payment_plan.dart';
import '../../application/record_payment/record_payment_providers.dart';

/// The prototype's `#35507C` info-banner text — no design token exists for it.
const Color _bannerText = Color(0xFF35507C);

final RegExp _uuidRe = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// Opens "Record payment" (webapp `RecordPaymentModal`), as a bottom sheet.
///
/// * [planId] — the plan's `payment_id` (uuid). [invoiceId] is the older
///   display-id key (`Invoice.id`: the quote number, or the uuid when the quote
///   has none) and is resolved to the uuid; pass either.
/// * [recordId] — preselect that instalment (the plan row's "Settle").
/// * [lockPlan] — hide the plan picker; defaults to true whenever a plan is
///   given (webapp: `locked = !!invoiceId`).
///
/// Resolves to true once a payment was recorded. Every payments list, plan
/// list and the plan itself are invalidated by then
/// ([invalidateAfterRecordPayment]), so headers like "1 of 3 settled" refetch.
Future<bool> showRecordPaymentSheet(
  BuildContext context, {
  String? planId,
  String? invoiceId,
  String? recordId,
  bool? lockPlan,
}) async {
  final ok = await showClozrSheet<bool>(
    context: context,
    builder: (_) => _RecordPaymentSheet(
      planId: planId,
      invoiceId: invoiceId,
      recordId: recordId,
      locked: lockPlan ?? ((planId ?? '').isNotEmpty || (invoiceId ?? '').isNotEmpty),
    ),
  );
  return ok ?? false;
}

class _RecordPaymentSheet extends ConsumerStatefulWidget {
  const _RecordPaymentSheet({this.planId, this.invoiceId, this.recordId, required this.locked});
  final String? planId;
  final String? invoiceId;
  final String? recordId;
  final bool locked;

  @override
  ConsumerState<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends ConsumerState<_RecordPaymentSheet> {
  final _amount = TextEditingController();
  final _adhocAmount = TextEditingController();
  final _label = TextEditingController();
  final _note = TextEditingController();
  final _tds = TextEditingController();
  final _bankCharge = TextEditingController();
  final _gatewayRef = TextEditingController();

  /// The plan's uuid; empty until picked / resolved.
  String _planId = '';
  String _pickedLabel = '';
  bool _resolving = false;
  RecordMode _modeChoice = RecordMode.settle;
  String _recordId = '';
  String? _preselected;
  DateTime _date = DateTime.now();
  String _method = defaultPayMethodCode;
  bool _adjOpen = false;

  // Accounting only.
  BankAccount? _bank;
  String? _treatAs;

  String? _errPlan;
  String? _errInstall;
  String? _errAmount;
  String? _errDate;
  String? _errBank;

  bool _busy = false;
  AppError? _error;

  // "Convert lead and continue" (webapp round 4 Q4).
  bool _offerConvert = false;
  bool _converting = false;
  String? _convertNote;
  ({String id, String name})? _markWon;
  String? _leadId;

  /// The write to run once the lead is a customer.
  Future<void> Function()? _pending;

  /// The form's scroll, so a prompt or error raised at the top is brought
  /// into view after the user tapped Record at the bottom.
  final _scroll = ScrollController();

  void _revealTop() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  @override
  void initState() {
    super.initState();
    _resolvePlan();
  }

  /// [widget.planId] as is; a display id via the loaded plans, else a search.
  Future<void> _resolvePlan() async {
    final direct = widget.planId ?? '';
    if (direct.isNotEmpty) {
      _planId = direct;
      return;
    }
    final display = widget.invoiceId ?? '';
    if (display.isEmpty) return;
    if (_uuidRe.hasMatch(display)) {
      _planId = display;
      return;
    }
    for (final iv in ref.read(invoicesProvider).valueOrNull ?? const []) {
      if (iv.id == display && iv.uuid.isNotEmpty) {
        _planId = iv.uuid;
        return;
      }
    }
    _resolving = true;
    try {
      final hits = await ref.read(recordPaymentRemoteProvider).searchPlans(display);
      final hit = hits.where((p) => p.quoteNo == display).firstOrNull ?? (hits.length == 1 ? hits.first : null);
      if (mounted) setState(() => _planId = hit?.id ?? '');
    } on AppError {
      // Leaves the picker empty; "Select a payment plan" explains it.
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_amount, _adhocAmount, _label, _note, _tds, _bankCharge, _gatewayRef]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  RecordPaymentPlan? get _plan =>
      _planId.isEmpty ? null : ref.read(recordPaymentPlanProvider(_planId)).valueOrNull;

  SettlementDetails _details(RecordMode mode, PlanRecord? record) {
    final accounting = ref.read(accountingActiveProvider);
    final canTreatAs = mode == RecordMode.adhoc || (accounting && record != null && record.linkedDocumentId == null);
    return SettlementDetails(
      tds: deductionInput(_tds.text),
      bankCharge: deductionInput(_bankCharge.text),
      gatewayRef: _gatewayRef.text,
      // An explicit bank account wins over the method server-side, so never with cash.
      bankAccountId: accounting && _method != 'cash' ? _bank?.id : null,
      treatAs: canTreatAs ? _treatAs : null,
    );
  }

  void _pickPlan(PlanOption o) {
    setState(() {
      _planId = o.id;
      _pickedLabel = o.label;
      _errPlan = null;
      _modeChoice = RecordMode.settle;
      _recordId = '';
      _amount.clear();
      _offerConvert = false;
      _convertNote = null;
      _markWon = null;
      _error = null;
    });
  }

  /// Pick an instalment and prefill the amount with its open balance.
  void _pickInstallment(PlanRecord r) {
    setState(() {
      _recordId = r.id;
      _errInstall = null;
      _errAmount = null;
      _amount.text = amountSeed(r.open);
    });
  }

  bool _bankRequired() {
    if (!ref.read(accountingActiveProvider) || _method == 'cash') return false;
    final banks = ref.read(bankAccountsProvider);
    if (banks.hasError) return false; // cannot read banks: the server resolves the alias / default
    final rows = banks.valueOrNull ?? const <BankAccount>[];
    return !rows.any((b) => b.isDefault && b.isActive && b.kind == 'BANK');
  }

  Future<void> _save() async {
    if (_busy || _converting) return;
    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show('Recording payments needs a server connection');
      return;
    }
    final plan = _plan;
    final mode = effectiveMode(_modeChoice, plan?.paymentType);
    var bad = false;
    setState(() {
      _errPlan = plan == null ? 'Select a payment plan' : null;
      _errInstall = plan != null && mode == RecordMode.settle && _recordId.isEmpty ? 'Select an installment' : null;
      _errAmount = null;
      _errDate = paymentDateError(_date, DateTime.now());
      _errBank = _bankRequired() && _bank == null ? 'Choose the bank account this payment landed in' : null;
    });
    bad = _errPlan != null || _errInstall != null || _errDate != null || _errBank != null;
    if (plan != null && mode == RecordMode.adhoc) {
      final err = validateAdhocAmount(_adhocAmount.text,
          tds: deductionInput(_tds.text), bankCharge: deductionInput(_bankCharge.text));
      if (err != null) {
        setState(() => _errAmount = err);
        bad = true;
      }
    }
    if (bad || plan == null) return;

    final Future<Map<String, dynamic>> Function() write;
    if (mode == RecordMode.settle) {
      final record = plan.openRecords.where((r) => r.id == _recordId).firstOrNull;
      if (record == null) {
        setState(() => _errInstall = 'Select an installment');
        return;
      }
      final details = _details(mode, record);
      final check = validateSettleAmount(
          raw: _amount.text, balance: record.open, tds: details.tds, bankCharge: details.bankCharge);
      if (!check.ok) {
        setState(() => _errAmount = check.error);
        return;
      }
      final body = buildSettleBody(amountPaid: check.amountPaid, paidDate: _date, method: _method, details: details);
      write = () => ref.read(recordPaymentRemoteProvider).settleRecord(record.id, body);
    } else {
      final details = _details(mode, null);
      final body = buildAdhocBody(
        planId: plan.id,
        amount: apiMoney(_adhocAmount.text),
        paidDate: _date,
        method: _method,
        // Webapp: `label || note`.
        label: _label.text.trim().isNotEmpty ? _label.text : _note.text,
        details: details,
      );
      write = () => ref.read(recordPaymentRemoteProvider).addRecord(body);
    }

    _pending = () => _runRecord(write);
    // A lead-only plan: the lead becomes a customer first (the same Convert
    // as the lead screen), then this exact write runs.
    if (plan.needsCustomer) {
      setState(() {
        _offerConvert = true;
        _convertNote = null;
        _markWon = null;
      });
      _revealTop();
      return;
    }
    await _runRecord(write);
  }

  Future<void> _runRecord(Future<Map<String, dynamic>> Function() write) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await write();
      if (!mounted) return;
      final accounting = ref.read(accountingActiveProvider);
      await invalidateAfterRecordPayment(ref.invalidate, planId: _planId);
      if (accounting) invalidateAccountingReads(ref.invalidate);
      if (!mounted) return;
      final toast = ref.read(toastProvider.notifier);
      Navigator.of(context).pop(true);
      // Webapp closes silently with accounting off (a quirk); the app confirms.
      toast.show(accounting && saved['posted_receipt_id'] != null
          ? 'Payment recorded · receipt posted to the books'
          : 'Payment recorded');
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (isCustomerRequiredFailure(code: e.code, message: e.message) && (_plan?.quotationUuid ?? '').isNotEmpty) {
          _offerConvert = true;
          _convertNote = null;
        } else {
          _error = e;
        }
      });
      _revealTop();
    }
  }

  // ── Convert lead and continue ──

  Future<String?> _quoteLead() async {
    if (_leadId != null) return _leadId;
    final q = _plan?.quotationUuid ?? '';
    if (q.isEmpty) return null;
    return _leadId = await ref.read(recordPaymentRemoteProvider).quotationLeadId(q);
  }

  Future<void> _convertAndContinue() async {
    if (_converting) return;
    setState(() {
      _converting = true;
      _convertNote = null;
      _markWon = null;
    });
    try {
      final leadId = await _quoteLead();
      if (leadId == null) {
        _stopConverting('This quote has no lead to convert.');
        return;
      }
      final state = await ref.read(recordPaymentRemoteProvider).quoteLeadState(leadId);
      if (!mounted) return;
      switch (convertStepFor(state)) {
        case ConvertStep.recordNow:
          _afterConverted(leadId, null, toast: false);
        case ConvertStep.alreadyPending:
          _stopConverting(conversionAlreadyPendingCopy);
        case ConvertStep.noWonStatus:
          _stopConverting(noWonStatusCopy);
        case ConvertStep.confirmMarkWon:
          setState(() {
            _converting = false;
            _markWon = (id: state.wonStatusId!, name: state.wonStatusName ?? 'Won');
          });
        case ConvertStep.convert:
          await _runConvert(leadId);
      }
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      _stopConverting(e.message);
    }
  }

  /// Webapp `runConvert`: optionally move the lead to Won (auto-convert /
  /// approval rules apply), then the normal convert.
  Future<void> _runConvert(String leadId, {String? markWonStatusId}) async {
    setState(() {
      _converting = true;
      _markWon = null;
    });
    try {
      if (markWonStatusId != null) {
        final remote = ref.read(recordPaymentRemoteProvider);
        await remote.moveLeadToStatus(leadId, markWonStatusId);
        final after = LeadConversion.fromRow(await remote.leadRow(leadId), isWon: true);
        if (!mounted) return;
        if (after.isConverted) {
          _afterConverted(leadId, after.customerName);
          return;
        }
        if (after.pendingApproval) {
          _invalidateLead(leadId);
          _stopConverting(conversionSentForApprovalCopy);
          return;
        }
      }
      final result = await convertLead(ref, leadId);
      if (!mounted) return;
      switch (result) {
        case Converted(:final customerName):
          _afterConverted(leadId, customerName);
        case ConversionRequested():
          _invalidateLead(leadId);
          _stopConverting(conversionSentForApprovalCopy);
        case NeedsCustomerChoice(:final match):
          _stopConverting(match.message);
      }
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      _stopConverting(e.message);
    }
  }

  void _stopConverting(String note) {
    if (!mounted) return;
    setState(() {
      _converting = false;
      _convertNote = note;
    });
  }

  void _invalidateLead(String leadId) {
    ref.invalidate(leadRowProvider(leadId));
    ref.invalidate(leadDetailProvider(leadId));
    ref.invalidate(leadsScopedProvider);
    ref.invalidate(customersScopedProvider);
  }

  void _afterConverted(String leadId, String? customerName, {bool toast = true}) {
    _invalidateLead(leadId);
    if (toast) ref.read(toastProvider.notifier).show(leadConvertedToast(customerName));
    setState(() {
      _converting = false;
      _offerConvert = false;
    });
    final pending = _pending;
    if (pending != null) pending();
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final planAsync = _planId.isEmpty ? null : ref.watch(recordPaymentPlanProvider(_planId));
    final plan = planAsync?.valueOrNull;
    final accounting = ref.watch(accountingActiveProvider);
    if (accounting) ref.watch(bankAccountsProvider);
    final mode = effectiveMode(_modeChoice, plan?.paymentType);
    final open = plan?.openRecords ?? const <PlanRecord>[];
    final selected = mode == RecordMode.settle ? open.where((r) => r.id == _recordId).firstOrNull : null;

    // "Settle" on a row: preselect that instalment once the plan has loaded.
    final want = widget.recordId;
    if (want != null && _preselected != want && plan != null) {
      final hit = open.where((r) => r.id == want).firstOrNull;
      _preselected = want;
      if (hit != null) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _pickInstallment(hit) : null);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'Record payment', onClose: () => Navigator.of(context).maybePop()),
        Flexible(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 12.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null) ...[
                  ConflictBanner(error: _error!),
                  SizedBox(height: 13.h),
                ],
                if (_offerConvert) ...[
                  _convertBox(),
                  SizedBox(height: 13.h),
                ],
                if (!widget.locked) ...[
                  _label$('Payment plan', required: true),
                  _box(
                    onTap: _openPlanPicker,
                    text: _pickedLabel.isNotEmpty
                        ? _pickedLabel
                        : (plan != null ? '${plan.quoteNo} · ${plan.who}' : 'Search by quote number or customer…'),
                    placeholder: _pickedLabel.isEmpty && plan == null,
                    icon: PhosphorIconsRegular.magnifyingGlass,
                  ),
                  _errorText(_errPlan),
                  SizedBox(height: 13.h),
                ] else
                  _errorText(_errPlan),
                if (_resolving || (planAsync?.isLoading ?? false) && plan == null)
                  Padding(
                    padding: EdgeInsets.only(bottom: 13.h),
                    child: Text('Loading payment plan…', style: AppText.caption()),
                  ),
                if (planAsync != null && planAsync.hasError && plan == null)
                  Padding(
                    padding: EdgeInsets.only(bottom: 13.h),
                    child: Text("Couldn't load this payment plan", style: AppText.caption(color: AppColors.error)),
                  ),
                if (plan != null) ..._planBody(plan, mode, open, selected, accounting),
                SizedBox(height: 6.h),
              ],
            ),
          ),
        ),
        _footer(),
      ],
    );
  }

  List<Widget> _planBody(
      RecordPaymentPlan plan, RecordMode mode, List<PlanRecord> open, PlanRecord? selected, bool accounting) {
    final adhocAllowed = adhocAllowedFor(plan.paymentType);
    final tds = deductionInput(_tds.text);
    final charge = deductionInput(_bankCharge.text);
    final note = deductionsNote(tds, charge);
    final canTreatAs = mode == RecordMode.adhoc || (accounting && selected != null && selected.linkedDocumentId == null);
    return [
      _infoStrip(PhosphorIconsRegular.receipt, plan.summary),
      SizedBox(height: 13.h),
      _segToggle(mode, adhocAllowed),
      if (!adhocAllowed) ...[
        SizedBox(height: 6.h),
        Text(adhocUnavailableCopy, style: AppText.caption()),
      ],
      SizedBox(height: 13.h),
      if (mode == RecordMode.settle) ...[
        if (open.isEmpty)
          _successBanner(allSettledCopy(plan.paymentType))
        else ...[
          _label$('Installment', required: true),
          _box(
            onTap: () => _openInstallmentPicker(open),
            text: selected?.optionLabel ?? 'Select an installment…',
            placeholder: selected == null,
            icon: PhosphorIconsRegular.caretDown,
          ),
          _errorText(_errInstall),
          SizedBox(height: 13.h),
          _field('Amount received (₹)', _amount,
              selected != null ? (amountSeed(selected.open).isEmpty ? '0' : amountSeed(selected.open)) : 'Pick an installment',
              number: true,
              onChanged: (_) => setState(() => _errAmount = null)),
          if (_errAmount != null && !_adjOpen)
            _errorText(_errAmount)
          else if (selected != null)
            _hint('Open balance ${rupees(selected.open)}'),
          SizedBox(height: 13.h),
          _dateField(),
          SizedBox(height: 13.h),
          _methods(),
        ],
      ] else ...[
        _field('Amount (₹)', _adhocAmount, 'e.g. 250000',
            number: true, onChanged: (_) => setState(() => _errAmount = null)),
        _errorText(_errAmount),
        SizedBox(height: 13.h),
        _dateField(),
        SizedBox(height: 13.h),
        _methods(),
        SizedBox(height: 13.h),
        _field('Label', _label, 'e.g. Part payment'),
      ],
      if (mode == RecordMode.adhoc || open.isNotEmpty) ...[
        SizedBox(height: 15.h),
        _adjustmentsToggle(),
        if (_adjOpen) ...[
          SizedBox(height: 10.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _field('TDS deducted (₹)', _tds, '0',
                    number: true, onChanged: (_) => setState(() => _errAmount = null)),
              ),
              SizedBox(width: 9.w),
              Expanded(
                child: _field('Bank charge (₹)', _bankCharge, '0',
                    number: true, onChanged: (_) => setState(() => _errAmount = null)),
              ),
            ],
          ),
          _hint('TDS the customer withheld and the fee the bank / gateway deducted both count toward settlement.'),
          SizedBox(height: 13.h),
          _field('Bank / gateway reference', _gatewayRef, 'UTR or transaction id'),
          if (accounting && canTreatAs) ...[
            SizedBox(height: 13.h),
            AccChoiceChips(
              label: 'Treat as',
              options: const {'': 'Not specified', 'ADVANCE': 'Advance', 'CUSTOMER_CREDIT': 'Customer credit'},
              selected: _treatAs ?? '',
              onSelected: (v) => setState(() => _treatAs = v.isEmpty ? null : v),
            ),
          ],
          if (note != null) _hint(note),
          if (mode == RecordMode.settle) _errorText(_errAmount),
        ],
      ],
      if (accounting) ..._bankFields(),
      if (mode == RecordMode.adhoc) ...[
        SizedBox(height: 13.h),
        _field('Notes', _note, 'Internal note, e.g. Installment 1 of 3'),
      ],
    ];
  }

  // ── Pickers ──

  Future<void> _openPlanPicker() async {
    final picked = await showClozrSheet<PlanOption>(
      context: context,
      builder: (_) => _PlanPickerSheet(selectedId: _planId),
    );
    if (picked != null && mounted) _pickPlan(picked);
  }

  Future<void> _openInstallmentPicker(List<PlanRecord> open) async {
    final picked = await showClozrSheet<PlanRecord>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: 'Installment', onClose: () => Navigator.of(ctx).pop()),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(14.w, 4.h, 14.w, 28.h),
              children: [
                for (final r in open)
                  _optionRow(
                    title: r.optionLabel,
                    selected: r.id == _recordId,
                    onTap: () => Navigator.of(ctx).pop(r),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null && mounted) _pickInstallment(picked);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    // Future dates stay pickable so the rule can say why they are refused
    // (webapp: a typed future date shows the same message).
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (d != null && mounted) {
      setState(() {
        _date = d;
        _errDate = null;
      });
    }
  }

  // ── Pieces ──

  Widget _convertBox() {
    final markWon = _markWon;
    final text = markWon != null ? markWonPromptCopy(markWon.name) : (_convertNote ?? convertLeadPromptCopy);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(11.r),
        border: Border.all(color: AppColors.borderInput, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(text, style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textLabel, height: 1.45)),
          SizedBox(height: 10.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (markWon != null) ...[
                _smallButton('Cancel', primary: false, onTap: _converting ? null : () => setState(() => _markWon = null)),
                SizedBox(width: 8.w),
                Flexible(
                  child: _smallButton(
                    _converting ? 'Converting…' : 'Mark Won, convert and continue',
                    onTap: _converting || _busy
                        ? null
                        : () async {
                            final leadId = await _quoteLead();
                            if (leadId != null) await _runConvert(leadId, markWonStatusId: markWon.id);
                          },
                  ),
                ),
              ] else
                Flexible(
                  child: _smallButton(
                    _converting ? 'Converting…' : 'Convert lead and continue',
                    onTap: _converting || _busy ? null : _convertAndContinue,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _smallButton(String label, {bool primary = true, VoidCallback? onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 36.h,
        padding: EdgeInsets.symmetric(horizontal: 13.w),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? (onTap == null ? AppColors.navy.withOpacity(0.6) : AppColors.navy) : AppColors.white,
          borderRadius: BorderRadius.circular(9.r),
          border: primary ? null : Border.all(color: AppColors.borderInput),
        ),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.custom(
                size: 12.5, weight: FontWeight.w700, color: primary ? AppColors.white : AppColors.textLabel)),
      ),
    );
  }

  List<Widget> _bankFields() {
    final cash = _method == 'cash';
    final banks = ref.watch(bankAccountsProvider);
    if (banks.hasError) {
      // No access to the bank list (webapp: users without acc_setup).
      return [
        if (!cash) ...[
          SizedBox(height: 13.h),
          _hint('Non-cash payments post to the bank account that lists this method as an alias, or to the default '
              'bank. If neither exists the payment is refused — ask an accountant to set one up.'),
        ],
      ];
    }
    final hasDefault = (banks.valueOrNull ?? const <BankAccount>[]).any((b) => b.isDefault && b.isActive && b.kind == 'BANK');
    return [
      SizedBox(height: 13.h),
      Opacity(
        opacity: cash ? 0.55 : 1,
        child: AccPickerBox(
          label: 'Bank account',
          required: _bankRequired(),
          value: cash ? null : _bank?.label,
          hint: hasDefault ? 'Default bank account' : 'Select an account',
          onTap: () async {
            if (cash) return;
            final b = await pickBankAccount(context, ref, selectedId: _bank?.id);
            if (b != null && mounted) {
              setState(() {
                _bank = b;
                _errBank = null;
              });
            }
          },
        ),
      ),
      if (_errBank != null)
        _errorText(_errBank)
      else
        _hint(cash ? 'Cash payments post to cash in hand.' : 'Where the money landed. Posted to the books as a receipt.'),
    ];
  }

  Widget _dateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label$('Date received'),
        _box(onTap: _pickDate, text: sheetDateLabel(_date), icon: PhosphorIconsRegular.calendarBlank),
        _errorText(_errDate),
      ],
    );
  }

  Widget _methods() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label$('Method'),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [for (final m in recordPayMethods) _methodChip(m)],
        ),
      ],
    );
  }

  Widget _adjustmentsToggle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _adjOpen = !_adjOpen),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_adjOpen ? PhosphorIconsBold.caretDown : PhosphorIconsBold.caretRight, size: 13.sp, color: AppColors.navy),
          SizedBox(width: 6.w),
          Text('Adjustments (TDS, bank charge, reference)',
              style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.navy)),
        ],
      ),
    );
  }

  Widget _footer() {
    final busy = _busy || _converting;
    return Container(
      padding: EdgeInsets.fromLTRB(18.w, 12.h, 18.w, 24.h),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderCardSoft))),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: busy ? null : _save,
        child: Container(
          height: 48.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: busy ? AppColors.navy.withOpacity(0.6) : AppColors.navy,
              borderRadius: BorderRadius.circular(12.r)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(PhosphorIconsBold.check, size: 15.sp, color: AppColors.white),
              SizedBox(width: 8.w),
              Text(_busy ? 'Recording…' : 'Record payment',
                  style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segToggle(RecordMode mode, bool adhocAllowed) {
    return Container(
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(12.r)),
      child: Row(
        children: [
          Expanded(child: _seg(mode, RecordMode.settle, PhosphorIconsRegular.checkCircle, 'Settle an installment')),
          // The Ad-hoc tab exists only for milestone-based plans.
          if (adhocAllowed) ...[
            SizedBox(width: 6.w),
            Expanded(child: _seg(mode, RecordMode.adhoc, PhosphorIconsRegular.currencyInr, 'Ad-hoc amount')),
          ],
        ],
      ),
    );
  }

  Widget _seg(RecordMode current, RecordMode key, IconData icon, String label) {
    final on = current == key;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _modeChoice = key;
        _errAmount = null;
      }),
      child: Container(
        height: 38.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15.sp, color: on ? AppColors.navy : AppColors.textMuted),
            SizedBox(width: 6.w),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.custom(
                      size: 12.5, weight: FontWeight.w700, color: on ? AppColors.navy : AppColors.textMuted)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _methodChip(PayMethod m) {
    final on = _method == m.code;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _method = m.code;
        _errBank = null;
      }),
      child: Container(
        height: 34.h,
        padding: EdgeInsets.symmetric(horizontal: 13.w),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.navy : AppColors.white,
          borderRadius: BorderRadius.circular(9.r),
          border: on ? null : Border.all(color: AppColors.borderInput),
        ),
        child: Text(m.label,
            style: AppText.custom(
                size: 12.5,
                weight: on ? FontWeight.w700 : FontWeight.w600,
                color: on ? AppColors.white : AppColors.textLabel)),
      ),
    );
  }

  Widget _box({required VoidCallback onTap, required String text, bool placeholder = false, required IconData icon}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 46.h,
        padding: EdgeInsets.symmetric(horizontal: 14.w),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(11.r),
          border: Border.all(color: AppColors.borderInput, width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: placeholder ? AppText.body(color: AppColors.textPlaceholder) : AppText.body()),
            ),
            Icon(icon, size: 15.sp, color: AppColors.textPlaceholder),
          ],
        ),
      ),
    );
  }

  Widget _infoStrip(IconData icon, String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(10.r)),
      child: Row(
        children: [
          Icon(icon, size: 15.sp, color: AppColors.navy),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(text, style: AppText.custom(size: 12, weight: FontWeight.w600, color: _bannerText)),
          ),
        ],
      ),
    );
  }

  Widget _successBanner(String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 11.h),
      decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(10.r)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsRegular.checkCircle, size: 15.sp, color: AppColors.success),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(text,
                style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textLabel, height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c, String hint,
      {bool number = false, ValueChanged<String>? onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label$(label),
        Container(
          height: 44.h,
          padding: EdgeInsets.symmetric(horizontal: 13.w),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(11.r),
            border: Border.all(color: AppColors.borderInput, width: 1.5),
          ),
          child: Center(
            child: TextField(
              controller: c,
              onChanged: onChanged,
              keyboardType: number
                  ? const TextInputType.numberWithOptions(decimal: true, signed: true)
                  : TextInputType.text,
              // Paise allowed. A leading minus is let through so the amount
              // rule can say "Enter a valid amount" rather than eat the key.
              inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d{0,2}'))] : null,
              style: AppText.body(),
              cursorColor: AppColors.blueBright,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: AppText.body(color: AppColors.textPlaceholder),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _hint(String text) => Padding(
        padding: EdgeInsets.only(top: 6.h),
        child: Text(text, style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
      );

  Widget _errorText(String? text) => text == null
      ? const SizedBox.shrink()
      : Padding(
          padding: EdgeInsets.only(top: 6.h),
          child: Text(text, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.error)),
        );

  Widget _label$(String text, {bool required = false}) => Padding(
        padding: EdgeInsets.only(bottom: 7.h),
        child: Row(
          children: [
            Text(text, style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
            if (required) Text(' *', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.error)),
          ],
        ),
      );
}

Widget _optionRow({required String title, String? sub, required bool selected, required VoidCallback onTap}) {
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: 9.h, horizontal: 6.w),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.bodyStrong()),
                if (sub != null) ...[
                  SizedBox(height: 2.h),
                  Text(sub, style: AppText.caption()),
                ],
              ],
            ),
          ),
          if (selected) Icon(PhosphorIconsBold.check, size: 19.sp, color: AppColors.success),
        ],
      ),
    ),
  );
}

/// The plan picker: a debounced server search (webapp `SearchSelect` over
/// `GET /quotations/payments/?search=`).
class _PlanPickerSheet extends ConsumerStatefulWidget {
  const _PlanPickerSheet({required this.selectedId});
  final String selectedId;

  @override
  ConsumerState<_PlanPickerSheet> createState() => _PlanPickerSheetState();
}

class _PlanPickerSheetState extends ConsumerState<_PlanPickerSheet> {
  final _query = TextEditingController();
  Timer? _debounce;
  String _term = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _term = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(recordPaymentPlanSearchProvider(_term));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'Payment plan', onClose: () => Navigator.of(context).pop()),
        Padding(
          padding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 8.h),
          child: Container(
            height: 44.h,
            padding: EdgeInsets.symmetric(horizontal: 13.w),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(11.r),
              border: Border.all(color: AppColors.borderInput, width: 1.5),
            ),
            child: Row(
              children: [
                Icon(PhosphorIconsRegular.magnifyingGlass, size: 15.sp, color: AppColors.textPlaceholder),
                SizedBox(width: 8.w),
                Expanded(
                  child: TextField(
                    controller: _query,
                    autofocus: true,
                    onChanged: _onChanged,
                    style: AppText.body(),
                    cursorColor: AppColors.blueBright,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Search by quote number or customer…',
                      hintStyle: AppText.body(color: AppColors.textPlaceholder),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Flexible(
          child: results.when(
            loading: () => Padding(
              padding: EdgeInsets.all(24.h),
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => Padding(
              padding: EdgeInsets.all(24.h),
              child: Text("Couldn't load payment plans", style: AppText.caption(color: AppColors.error)),
            ),
            data: (plans) => plans.isEmpty
                ? Padding(
                    padding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 32.h),
                    child: Text(_term.isNotEmpty ? 'No payment plans match “$_term”' : 'No payment plans yet',
                        style: AppText.caption()),
                  )
                : ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.fromLTRB(14.w, 4.h, 14.w, 28.h),
                    children: [
                      for (final p in plans)
                        _optionRow(
                          title: p.label,
                          sub: p.dueLine,
                          selected: p.id == widget.selectedId,
                          onTap: () => Navigator.of(context).pop(p),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
