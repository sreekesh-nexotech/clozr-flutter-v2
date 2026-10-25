import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../../app/theme/app_colors.dart';
import '../../../../../app/theme/app_text_styles.dart';
import '../../../../../core/network/app_error.dart';
import '../../../application/providers/quote_detail_providers.dart';
import '../../../application/quote_lifecycle.dart';

/// The quote detail's dialogs (webapp `AcceptQuoteDialog`,
/// `DeclineQuoteDialog`, `RenewQuoteDialog`, the revise confirm and
/// `GenerateDocumentDialog`). Each submit callback returns the error to show
/// inside the dialog, or null to close it.

typedef DialogSubmit<T> = Future<String?> Function(T value);

TextStyle get _strong => const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary);

Widget _errorText(String? e) => e == null
    ? const SizedBox.shrink()
    : Padding(padding: EdgeInsets.only(top: 8.h), child: Text(e, style: AppText.caption(color: AppColors.error)));

/// A tappable `YYYY-MM-DD` box opening the platform date picker.
class QuoteDateBox extends StatelessWidget {
  const QuoteDateBox({super.key, required this.label, required this.value, required this.onPicked, this.hint, this.error, this.enabled = true, this.placeholder = 'Pick a date', this.clearable = false});

  final String label;
  final String value;
  final ValueChanged<String> onPicked;
  final String? hint;
  final String? error;
  final bool enabled;
  final String placeholder;
  final bool clearable;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(value) ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 5),
    );
    if (d != null) onPicked(isoDayOf(d));
  }

  @override
  Widget build(BuildContext context) {
    final shown = value.isEmpty ? placeholder : (fmtQuoteDate(value).isEmpty ? value : fmtQuoteDate(value));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textMuted)),
      SizedBox(height: 5.h),
      GestureDetector(
        onTap: enabled ? () => _pick(context) : null,
        child: Container(
          height: 44.h,
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: error != null ? AppColors.error : AppColors.borderInput),
          ),
          child: Row(children: [
            Icon(PhosphorIconsRegular.calendarBlank, size: 16.sp, color: AppColors.textMuted),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(shown,
                  style: AppText.custom(
                      size: 13.5, weight: FontWeight.w600, color: value.isEmpty ? AppColors.textPlaceholder : AppColors.textPrimary)),
            ),
            if (clearable && value.isNotEmpty && enabled)
              GestureDetector(
                onTap: () => onPicked(''),
                child: Icon(PhosphorIconsRegular.x, size: 14.sp, color: AppColors.textMuted),
              ),
          ]),
        ),
      ),
      if (error != null)
        Padding(padding: EdgeInsets.only(top: 4.h), child: Text(error!, style: AppText.caption(color: AppColors.error)))
      else if (hint != null)
        Padding(padding: EdgeInsets.only(top: 4.h), child: Text(hint!, style: AppText.caption())),
    ]);
  }
}

// ── Accept ────────────────────────────────────────────────────────────────

/// What the Accept dialog hands back.
class AcceptChoice {
  const AcceptChoice(this.acceptedOn, this.schedule);
  final String acceptedOn;

  /// Only when it differs from what acceptance would create anyway.
  final AcceptSchedule? schedule;
}

/// "Accept this quote?" Returns `'accepted'`, `'change'` (the "Change" link:
/// the caller opens the builder and comes back) or null (cancelled).
Future<String?> showAcceptQuoteDialog(
  BuildContext context, {
  required QuoteFacts quote,
  required String amountLabel,
  required DialogSubmit<AcceptChoice> onSubmit,
}) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AcceptDialog(quote: quote, amountLabel: amountLabel, onSubmit: onSubmit),
    );

class _AcceptDialog extends StatefulWidget {
  const _AcceptDialog({required this.quote, required this.amountLabel, required this.onSubmit});
  final QuoteFacts quote;
  final String amountLabel;
  final DialogSubmit<AcceptChoice> onSubmit;

  @override
  State<_AcceptDialog> createState() => _AcceptDialogState();
}

class _AcceptDialogState extends State<_AcceptDialog> {
  late final AcceptDateWindow _window = acceptDateWindow(widget.quote);
  late String _acceptedOn = _window.initial;
  late final _count = TextEditingController();
  late final _period = TextEditingController();
  String _firstDue = '';
  String? _dateError;
  String? _scheduleError;
  String? _error;
  bool _busy = false;

  bool get _editable => scheduleEditable(widget.quote.paymentType);

  @override
  void initState() {
    super.initState();
    final base = defaultSchedule(widget.quote, _window.initial);
    _count.text = '${base.numInstallments}';
    _period.text = '${base.billingPeriodDays}';
  }

  @override
  void dispose() {
    _count.dispose();
    _period.dispose();
    super.dispose();
  }

  String get _effectiveOn => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(_acceptedOn) ? _acceptedOn : _window.initial;

  Future<void> _submit() async {
    final problem = validateAcceptedOn(_acceptedOn, _window);
    if (problem != null) {
      setState(() => _dateError = problem);
      return;
    }
    AcceptSchedule? schedule;
    if (_editable) {
      final (chosen, err) = resolveSchedule(
          count: _count.text, periodDays: _period.text, firstDue: _firstDue, quote: widget.quote, acceptedOn: _acceptedOn);
      if (err != null) {
        setState(() => _scheduleError = err);
        return;
      }
      if (scheduleChanged(chosen!, widget.quote, _acceptedOn)) schedule = chosen;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.onSubmit(AcceptChoice(_acceptedOn, schedule));
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop('accepted');
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  Widget _numField(String label, TextEditingController c) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textMuted)),
          SizedBox(height: 5.h),
          SizedBox(
            height: 44.h,
            child: TextField(
              controller: c,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() => _scheduleError = null),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
              ),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final q = widget.quote;
    final on = _effectiveOn;
    final summary = acceptPlanSummary(q, on);
    final (resolved, _) = _editable
        ? resolveSchedule(count: _count.text, periodDays: _period.text, firstDue: _firstDue, quote: q, acceptedOn: on)
        : (null, null);
    final scheduleLine = resolved != null ? scheduleSummary(resolved) : summary.schedule;
    final typeLabel = resolved != null
        ? (resolved.numInstallments > 1 ? 'Instalments – even split' : 'Lump sum')
        : summary.typeLabel;
    final count = int.tryParse(_count.text.trim()) ?? 1;
    final shownFirstDue = _firstDue.isNotEmpty ? _firstDue : defaultSchedule(q, on).firstDueDate;

    return AlertDialog(
      title: const Text('Accept this quote?'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(style: AppText.body(), children: [
            const TextSpan(text: 'Accepting '),
            TextSpan(text: q.label, style: _strong),
            const TextSpan(
                text: ' marks it as won and generates its payment plan and installment schedule. You can move it back out of '
                    'Accepted until a payment is recorded or accounting issues a tax invoice.'),
          ])),
          SizedBox(height: 14.h),
          QuoteDateBox(
            label: 'Accepted on',
            value: _acceptedOn,
            enabled: !_busy,
            error: _dateError,
            hint: acceptDateHint(_window),
            onPicked: (v) => setState(() {
              _acceptedOn = v;
              _dateError = null;
            }),
          ),
          SizedBox(height: 14.h),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12.r),
            decoration: BoxDecoration(
              color: AppColors.bgSubtle,
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(color: AppColors.borderCardSoft),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('PAYMENT PLAN · ${typeLabel.toUpperCase()}',
                      style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.3)),
                  SizedBox(height: 3.h),
                  Text(scheduleLine, style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textPrimary)),
                  if (widget.amountLabel.isNotEmpty) ...[
                    SizedBox(height: 2.h),
                    Text('Total ${widget.amountLabel}', style: AppText.caption()),
                  ],
                ]),
              ),
              GestureDetector(
                onTap: _busy ? null : () => Navigator.of(context).pop('change'),
                child: Text(_editable ? 'Other terms' : 'Change',
                    style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.navy)
                        .copyWith(decoration: TextDecoration.underline)),
              ),
            ]),
          ),
          if (_editable) ...[
            SizedBox(height: 12.h),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _numField('Instalments', _count),
              if (count > 1) ...[SizedBox(width: 10.w), _numField('Every (days)', _period)],
            ]),
            SizedBox(height: 10.h),
            QuoteDateBox(
              label: count > 1 ? 'First due' : 'Due on',
              value: shownFirstDue,
              enabled: !_busy,
              onPicked: (v) => setState(() {
                _firstDue = v;
                _scheduleError = null;
              }),
            ),
            SizedBox(height: 6.h),
            Text(_scheduleError ?? kScheduleHelp,
                style: AppText.caption(color: _scheduleError != null ? AppColors.error : AppColors.textMuted)),
          ],
          _errorText(_error),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Accepting…' : 'Accept quote')),
      ],
    );
  }
}

// ── Decline ───────────────────────────────────────────────────────────────

/// "Why was this quote declined?" — true when the quote was declined.
Future<bool> showDeclineQuoteDialog(
  BuildContext context, {
  required String quoteLabel,
  required String statusLabel,
  required DialogSubmit<({String reasonId, String note})> onSubmit,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeclineDialog(quoteLabel: quoteLabel, statusLabel: statusLabel, onSubmit: onSubmit),
    ) ==
    true;

class _DeclineDialog extends ConsumerStatefulWidget {
  const _DeclineDialog({required this.quoteLabel, required this.statusLabel, required this.onSubmit});
  final String quoteLabel;
  final String statusLabel;
  final DialogSubmit<({String reasonId, String note})> onSubmit;

  @override
  ConsumerState<_DeclineDialog> createState() => _DeclineDialogState();
}

class _DeclineDialogState extends ConsumerState<_DeclineDialog> {
  final _note = TextEditingController();
  String _reasonId = '';
  String? _fieldError;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit(List<({String id, String name})> reasons) async {
    final r = validateDeclineDraft(_reasonId, _note.text, reasons.map((e) => e.id));
    if (r.error != null) {
      setState(() => _fieldError = r.error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.onSubmit((reasonId: r.reasonId, note: r.note));
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(quoteDeclineReasonsProvider);
    final reasons = async.valueOrNull ?? const <({String id, String name})>[];
    final noReasons = async.hasValue && reasons.isEmpty;
    return AlertDialog(
      title: const Text('Why was this quote declined?'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(style: AppText.body(), children: [
            TextSpan(text: widget.quoteLabel, style: _strong),
            TextSpan(text: ' will be marked ${widget.statusLabel}. The reason feeds the win/loss report.'),
          ])),
          SizedBox(height: 14.h),
          if (async.hasError)
            Text(async.error is AppError ? (async.error as AppError).bareMessage : '${async.error}', style: AppText.caption(color: AppColors.error))
          else if (noReasons)
            Text(kNoDeclineReasons, style: AppText.caption(color: AppColors.error))
          else
            DropdownButtonFormField<String>(
              value: _reasonId.isEmpty ? null : _reasonId,
              isExpanded: true,
              hint: Text(async.isLoading ? 'Loading reasons…' : 'Choose a reason'),
              decoration: InputDecoration(
                labelText: 'Decline reason *',
                errorText: _fieldError,
                border: const OutlineInputBorder(),
              ),
              items: [for (final r in reasons) DropdownMenuItem(value: r.id, child: Text(r.name))],
              onChanged: _busy || async.isLoading
                  ? null
                  : (v) => setState(() {
                        _reasonId = v ?? '';
                        _fieldError = null;
                      }),
            ),
          SizedBox(height: 12.h),
          TextField(
            controller: _note,
            enabled: !_busy,
            minLines: 2,
            maxLines: 4,
            onChanged: (_) {
              if (_fieldError != null) setState(() => _fieldError = null);
            },
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'e.g. Went with a cheaper vendor; revisit next quarter',
              border: OutlineInputBorder(),
            ),
          ),
          if (noReasons && _fieldError != null) _errorText(_fieldError),
          _errorText(_error),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        TextButton(
          onPressed: _busy || noReasons || async.isLoading || async.hasError ? null : () => _submit(reasons),
          child: Text(_busy ? 'Saving…' : 'Mark as ${widget.statusLabel}',
              style: TextStyle(color: _busy || noReasons ? null : AppColors.error)),
        ),
      ],
    );
  }
}

// ── Renew ─────────────────────────────────────────────────────────────────

/// "Renew this quote?" — true once renewed.
Future<bool> showRenewQuoteDialog(BuildContext context, {required String quoteLabel, required DialogSubmit<String?> onSubmit}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RenewDialog(quoteLabel: quoteLabel, onSubmit: onSubmit),
    ) ==
    true;

class _RenewDialog extends StatefulWidget {
  const _RenewDialog({required this.quoteLabel, required this.onSubmit});
  final String quoteLabel;
  final DialogSubmit<String?> onSubmit;

  @override
  State<_RenewDialog> createState() => _RenewDialogState();
}

class _RenewDialogState extends State<_RenewDialog> {
  String _validUntil = '';
  String? _fieldError;
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    final problem = validateRenewDate(_validUntil);
    if (problem != null) {
      setState(() => _fieldError = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.onSubmit(_validUntil.isEmpty ? null : _validUntil);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Renew this quote?'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(style: AppText.body(), children: [
            const TextSpan(text: 'A new revision of '),
            TextSpan(text: widget.quoteLabel, style: _strong),
            const TextSpan(text: ' is created as a draft at today’s catalog prices. This quote becomes '),
            TextSpan(text: 'Superseded', style: _strong),
            const TextSpan(text: ' and read-only.'),
          ])),
          SizedBox(height: 14.h),
          QuoteDateBox(
            label: 'New valid-until date (optional)',
            value: _validUntil,
            enabled: !_busy,
            clearable: true,
            placeholder: 'Default validity',
            error: _fieldError,
            hint: 'Leave blank to use your default validity period',
            onPicked: (v) => setState(() {
              _validUntil = v;
              _fieldError = null;
            }),
          ),
          _errorText(_error),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        TextButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Renewing…' : 'Renew quote')),
      ],
    );
  }
}

// ── Revise ────────────────────────────────────────────────────────────────

/// "Create a revision?" — true to go ahead.
Future<bool> confirmReviseQuote(BuildContext context, String number) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create a revision?'),
        content: Text('A new draft revision of ${number.isEmpty ? 'this quote' : number} is created with the same lines and '
            'prices for you to change. This quote becomes Superseded and read-only.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Create revision')),
        ],
      ),
    ) ==
    true;

// ── Generate document ────────────────────────────────────────────────────

/// "Generate document": pick a template, fill its fields, Generate. True
/// once generated.
Future<bool> showGenerateDocumentDialog(
  BuildContext context, {
  required DialogSubmit<({DocTemplate template, Map<String, String> values})> onSubmit,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GenerateDialog(onSubmit: onSubmit),
    ) ==
    true;

class _GenerateDialog extends ConsumerStatefulWidget {
  const _GenerateDialog({required this.onSubmit});
  final DialogSubmit<({DocTemplate template, Map<String, String> values})> onSubmit;

  @override
  ConsumerState<_GenerateDialog> createState() => _GenerateDialogState();
}

class _GenerateDialogState extends ConsumerState<_GenerateDialog> {
  DocTemplate? _template;
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, String> _values = {};
  bool _attempted = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _choose(DocTemplate t) {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _ctrls.clear();
    _values.clear();
    for (final f in t.fields) {
      _values[f.key] = f.defaultValue;
      if (f.type != 'date' && f.type != 'choice') _ctrls[f.key] = TextEditingController(text: f.defaultValue);
    }
    setState(() {
      _template = t;
      _attempted = false;
      _error = null;
    });
  }

  Map<String, String> get _current => {
        for (final f in _template?.fields ?? const <DocTemplateField>[]) f.key: _ctrls[f.key]?.text ?? _values[f.key] ?? '',
      };

  Future<void> _generate() async {
    final t = _template!;
    final values = _current;
    setState(() => _attempted = true);
    if (t.fields.any((f) => documentFieldProblem(f, values[f.key] ?? '').isNotEmpty)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.onSubmit((template: t, values: values));
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  Widget _field(DocTemplateField f) {
    final err = _attempted ? documentFieldProblem(f, _current[f.key] ?? '') : '';
    final label = '${f.label}${f.required ? ' *' : ''}';
    final help = f.helpText.isEmpty ? null : f.helpText;
    if (f.type == 'date') {
      return QuoteDateBox(
        label: label,
        value: _values[f.key] ?? '',
        clearable: true,
        enabled: !_busy,
        error: err.isEmpty ? null : err,
        hint: help,
        onPicked: (v) => setState(() => _values[f.key] = v),
      );
    }
    if (f.type == 'choice') {
      final v = _values[f.key] ?? '';
      return DropdownButtonFormField<String>(
        value: f.choices.contains(v) ? v : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, helperText: help, helperMaxLines: 3, errorText: err.isEmpty ? null : err, border: const OutlineInputBorder()),
        items: [for (final c in f.choices) DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))],
        onChanged: _busy ? null : (x) => setState(() => _values[f.key] = x ?? ''),
      );
    }
    final multi = f.type == 'textarea';
    return TextField(
      controller: _ctrls[f.key],
      enabled: !_busy,
      minLines: multi ? 2 : 1,
      maxLines: multi ? 4 : 1,
      keyboardType: f.type == 'number' || f.type == 'decimal' ? const TextInputType.numberWithOptions(decimal: true) : null,
      onChanged: (_) {
        if (_attempted) setState(() {});
      },
      decoration: InputDecoration(labelText: label, helperText: help, helperMaxLines: 3, errorText: err.isEmpty ? null : err, border: const OutlineInputBorder()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _template;
    final async = ref.watch(quoteDocTemplatesProvider);
    final templates = async.valueOrNull ?? const <DocTemplate>[];
    Widget body;
    if (t == null) {
      body = async.isLoading
          ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          : async.hasError
              ? Text(async.error is AppError ? (async.error as AppError).bareMessage : '${async.error}', style: AppText.caption(color: AppColors.error))
              : templates.isEmpty
                  ? Text('No document templates are active in this workspace.', style: AppText.caption())
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final tp in templates)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(PhosphorIconsRegular.filePlus, size: 20.sp, color: AppColors.navy),
                          title: Text(tp.name, style: AppText.bodyStrong()),
                          subtitle: tp.description.isEmpty
                              ? null
                              : Text(tp.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.caption()),
                          onTap: () => _choose(tp),
                        ),
                    ]);
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (t.fields.isEmpty)
          Text('This template has no fields to fill — it uses the quote as it is.', style: AppText.caption())
        else ...[
          for (final f in t.fields) Padding(padding: EdgeInsets.only(bottom: 12.h), child: _field(f)),
          Text('Blank fields use the template’s default (for example the lead’s PO reference or the quote’s payment terms).',
              style: AppText.caption()),
        ],
        if (_attempted && t.fields.any((f) => documentFieldProblem(f, _current[f.key] ?? '').isNotEmpty))
          _errorText('Fix the highlighted fields.'),
        _errorText(_error),
      ]);
    }
    return AlertDialog(
      title: Text(t?.name ?? 'Generate document'),
      content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: body)),
      actions: [
        if (t != null)
          TextButton(onPressed: _busy ? null : () => setState(() => _template = null), child: const Text('Back')),
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        if (t != null) TextButton(onPressed: _busy ? null : _generate, child: Text(_busy ? 'Generating…' : 'Generate')),
      ],
    );
  }
}
