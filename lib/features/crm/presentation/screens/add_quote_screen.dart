import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../accounting/application/providers/accounting_providers.dart';
import '../../../accounting/presentation/components/acc_pickers.dart'
    show pickGstState;
import '../../../auth/application/providers/auth_providers.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/crm_module_schema_providers.dart';
import '../../application/providers/products_providers.dart';
import '../../application/providers/quote_builder_providers.dart';
import '../../application/providers/quotes_providers.dart';
import '../../application/quote_builder/option_tabs.dart';
import '../../application/quote_builder/quote_builder_draft.dart';
import '../../application/quote_builder/quote_lines.dart';
import '../../application/quote_builder/quote_tax.dart';
import '../../application/quote_builder/quote_template_parts.dart';
import '../../domain/entities/product.dart';
import '../../infrastructure/data_sources/remote/quote_builder_remote_ds.dart';
import '../components/quote_builder/party_picker_sheet.dart';
import '../components/quote_builder/qb_kit.dart';
import '../components/quote_builder/quote_lines_editor.dart';
import '../components/quote_builder/quote_option_tabs_bar.dart';
import '../components/quote_builder/quote_template_sections.dart';
import '../components/quote_builder/quote_totals_block.dart';

/// The quote builder — New quote, Edit quote, or a sent quote read-only.
///
/// A port of the webapp's `QuoteBuilderModal`, kept in this screen's own look:
/// * `/quotes/add` → **New quote** (`?lead=` / `?customer=` preset the party);
/// * `/quotes/edit?id=<uuid>` → **Edit quote <number>**, saving only the keys
///   that changed (Save stays disabled until something did);
/// * a sent (locked) quote → **Quote <number>**, read-only, Close only. A 409
///   `QUOTE_LOCKED` on save flips the screen into that state.
///
/// Totals, untouched catalog prices and per-line GST all come from the server
/// (`preview-tax`); the client never computes tax. After a save that needs
/// discount approval the screen stays open on the saved-but-pending notice.
class AddQuoteScreen extends ConsumerStatefulWidget {
  const AddQuoteScreen({super.key});

  @override
  ConsumerState<AddQuoteScreen> createState() => _AddQuoteScreenState();
}

class _AddQuoteScreenState extends ConsumerState<AddQuoteScreen> {
  // ── Route ────────────────────────────────────────────────────────────────
  bool _routeRead = false;
  String _quoteId = '';
  String _presetLeadId = '';
  String _presetCustomerId = '';
  bool _focusPayment = false;

  /// Set by the detail screen (`&revise=1`) when the quote can be revised —
  /// the read-only notice then offers the webapp's "Revise quote", which pops
  /// back with `'revise'` so the detail runs its own confirm + revise.
  bool _canRevise = false;
  bool get _isEdit => _quoteId.isNotEmpty;

  // ── Form ─────────────────────────────────────────────────────────────────
  BuilderDraft _draft = BuilderDraft.empty();
  bool _seeded = false;
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _contractCtrl = TextEditingController();
  final _installmentsCtrl = TextEditingController();
  final _billingCtrl = TextEditingController();
  final _paymentKey = GlobalKey();
  PartyOption? _leadPick;
  PartyOption? _customerPick;

  // ── Save ─────────────────────────────────────────────────────────────────
  bool _saving = false;
  bool _attemptedSave = false;
  bool _spotConfirmed = false;

  // ── Alternative options (an `options` template, rulebook v1.7) ────────────
  // The active option's lines and title live in [_draft]; the other options wait
  // in their tab (see option_tabs.dart).
  List<OptionTab> _tabs = const [];
  int _activeTab = 0;
  int _primaryTab = 0;
  bool _groupSeeded = false;

  ActiveOption get _activeOption =>
      (title: _draft.title, items: _draft.items, linesDirty: _draft.linesDirty);

  /// Writes the active option back to its tab and shows tab [index].
  void _loadTab(List<OptionTab> next, int index) {
    final t = next[index];
    setState(() {
      _tabs = next;
      _activeTab = index;
      _draft = _draft.copyWith(
          title: t.title,
          items: t.items,
          linesDirty: t.linesDirty,
          serverFlip: null);
      _titleCtrl.text = t.title;
      _touched = true;
    });
  }

  void _selectTab(int index) {
    if (index != _activeTab)
      _loadTab(stashActive(_tabs, _activeTab, _activeOption), index);
  }

  void _addAlternative(int max) {
    final next = addAlternative(_tabs, _activeTab, _activeOption, max);
    if (next.length > _tabs.length) _loadTab(next, next.length - 1);
  }

  void _removeOption(int index) {
    final r = removeOption(_tabs, _activeTab, _activeOption, index);
    if (r.tabs.length == _tabs.length) return;
    setState(() => _primaryTab = primaryAfterRemove(_primaryTab, index));
    _loadTab(r.tabs, r.active);
  }

  /// On an edit the primary must be a saved option (a new one has no id yet).
  void _makePrimary(int index) {
    if (!_isEdit ||
        (index < _tabs.length && _tabs[index].quotationId.isNotEmpty)) {
      setState(() {
        _primaryTab = index;
        _touched = true;
      });
    }
  }

  /// The user changed something — closing with the system back then asks
  /// "Discard changes?" (Cancel and the header arrow close without asking).
  bool _touched = false;
  String get _userId => ref.read(sessionControllerProvider).user?.id ?? '';

  /// Saved, but needs the user's attention (approval / field warnings).
  SavedQuote? _savedQuote;

  /// A 409 QUOTE_LOCKED during this edit.
  AppError? _lockFailure;

  /// The last create / update refusal, and its per-field messages.
  String? _saveError;
  Map<String, List<String>> _fieldErrors = const {};

  // ── Live tax preview ─────────────────────────────────────────────────────
  Timer? _previewTimer;
  int _previewSeq = 0;
  String? _requestedKey;
  String? _answeredKey;
  TaxPreview? _preview;
  List<PreviewRowRef> _previewRows = const [];
  String? _previewError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeRead) return;
    _routeRead = true;
    final q = GoRouterState.of(context).uri.queryParameters;
    _quoteId = q['id'] ?? '';
    _presetLeadId = q['lead'] ?? q['leadId'] ?? '';
    _presetCustomerId = q['customer'] ?? '';
    _focusPayment = q['focus'] == 'payment';
    _canRevise = q['revise'] == '1';
    if (_isEdit) {
      // Seed the form once, from the first server answer.
      ref.listenManual<AsyncValue<SavedQuote>>(
          quoteBuilderQuoteProvider(_quoteId), (_, next) {
        final q = next.valueOrNull;
        if (q == null || _seeded) return;
        // Deferred: this can fire synchronously, mid-lifecycle.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_seeded) setState(() => _seedFromQuote(q));
        });
      }, fireImmediately: true);
    } else {
      _draft = BuilderDraft.empty(
          leadId: _presetLeadId,
          customerId: _presetLeadId.isEmpty ? _presetCustomerId : '');
      // A form closed with Cancel comes back as it was (not the lead / customer).
      final kept = ref.read(quoteNewDraftProvider);
      if (kept != null && kept.userId == _userId) {
        _draft = kept.draft.copyWith(
          leadId: _presetLeadId,
          customerId: _presetLeadId.isEmpty ? _presetCustomerId : '',
          quoteFor: _presetLeadId.isEmpty && _presetCustomerId.isNotEmpty
              ? QuoteFor.customer
              : QuoteFor.lead,
        );
        _titleCtrl.text = _draft.title;
        _notesCtrl.text = _draft.notes;
        _contractCtrl.text = _draft.contractRef;
        _installmentsCtrl.text = _draft.installments;
        _billingCtrl.text = _draft.billing;
        _touched = true;
        final keptTabs = kept.tabs;
        if (keptTabs != null && keptTabs.isNotEmpty) {
          _tabs = keptTabs;
          _activeTab = kept.activeTab.clamp(0, keptTabs.length - 1);
          _primaryTab = kept.primaryTab.clamp(0, keptTabs.length - 1);
          _groupSeeded = true;
        }
      }
      _seeded = true;
      final ds = ref.read(quoteBuilderDsProvider);
      if (_presetLeadId.isNotEmpty) {
        ds.partyById(QuoteFor.lead, _presetLeadId).then((o) {
          if (mounted && o != null) setState(() => _leadPick = o);
        });
      } else if (_presetCustomerId.isNotEmpty) {
        ds.partyById(QuoteFor.customer, _presetCustomerId).then((o) {
          if (mounted && o != null) setState(() => _customerPick = o);
        });
      }
    }
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    for (final c in [
      _titleCtrl,
      _notesCtrl,
      _contractCtrl,
      _installmentsCtrl,
      _billingCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _patch(BuilderDraft Function(BuilderDraft) f) => setState(() {
        _draft = f(_draft);
        _touched = true;
      });

  /// Cancel / header arrow: close at once. A new quote's form is kept for the
  /// next "New quote".
  void _closeKeepingDraft() {
    // UAT: Cancel and the header arrow ask "Discard changes?" the same way the
    // system back does, whenever something was changed.
    if (_touched && !_saving) {
      _onDismiss();
      return;
    }
    if (!_isEdit && _touched) {
      ref.read(quoteNewDraftProvider.notifier).state = (
        userId: _userId,
        draft: _draft.copyWith(
            leadId: '', customerId: '', quoteFor: QuoteFor.lead),
        // Every option, with the active one's draft written back into its tab.
        tabs: _groupSeeded && _tabs.isNotEmpty
            ? stashActive(_tabs, _activeTab, _activeOption)
            : null,
        activeTab: _activeTab,
        primaryTab: _primaryTab,
      );
    }
    context.pop();
  }

  /// More than one alternative exists: a single-quote template would orphan them.
  bool _alternativesBlockSwitch(_View v) =>
      v.groupMode && !_isEdit && v.allTabs.length > 1;

  /// Webapp `templateBlocked`: on an edit a saved option group keeps an
  /// option-group template, and a single quote cannot be turned into one —
  /// either switch would drop or orphan the saved options.
  bool _templateBlocked(_View v, bool buildsGroup, String id) => _isEdit
      ? (v.groupMode ? !buildsGroup : buildsGroup && id != v.templateId)
      : (_alternativesBlockSwitch(v) && !buildsGroup && id != v.templateId);

  /// System back / swipe: ask first when something was typed.
  Future<void> _onDismiss() async {
    if (_saving) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text('Discard changes?',
            style: AppText.custom(
                size: 17,
                weight: FontWeight.w800,
                color: AppColors.textPrimary)),
        content: Text(
            'You have unsaved changes. If you close now, they will be lost.',
            style: AppText.body(color: AppColors.textMuted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Keep editing',
                  style: AppText.bodyStrong(color: AppColors.textLabelAlt))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Discard',
                  style: AppText.bodyStrong(color: AppColors.error))),
        ],
      ),
    );
    if (discard == true && mounted) {
      if (!_isEdit) ref.read(quoteNewDraftProvider.notifier).state = null;
      context.pop();
    }
  }

  void _seedFromQuote(SavedQuote q) {
    _draft = BuilderDraft.fromQuote(q);
    _titleCtrl.text = _draft.title;
    _notesCtrl.text = _draft.notes;
    _contractCtrl.text = _draft.contractRef;
    _installmentsCtrl.text = _draft.installments;
    _billingCtrl.text = _draft.billing;
    _seeded = true;
    if (_focusPayment) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _paymentKey.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.3);
      });
    }
  }

  // ── Preview ──────────────────────────────────────────────────────────────

  /// Debounced (400 ms) so typing never fires a request per keystroke; a
  /// stale answer is dropped by sequence number, and the last figures stay on
  /// screen (dimmed) until the new ones land.
  void _schedulePreview(PreviewRequest? req) {
    if (req == null || req.key == _requestedKey) return;
    _requestedKey = req.key;
    _previewTimer?.cancel();
    _previewTimer =
        Timer(const Duration(milliseconds: 400), () => _runPreview(req));
  }

  Future<void> _runPreview(PreviewRequest req) async {
    final seq = ++_previewSeq;
    try {
      final res = await ref.read(quoteBuilderDsProvider).previewTax(req.body);
      if (!mounted || seq != _previewSeq) return;
      setState(() {
        _preview = res;
        _previewRows = req.rows;
        _answeredKey = req.key;
        _previewError = null;
      });
    } on AppError catch (e) {
      if (!mounted || seq != _previewSeq) return;
      setState(() {
        _answeredKey = req.key;
        _previewError =
            previewErrorCopy(e.type == AppErrorType.validation, e.bareMessage);
      });
    }
  }

  // ── Party ────────────────────────────────────────────────────────────────

  Future<void> _pickParty(QuoteFor mode) async {
    final ds = ref.read(quoteBuilderDsProvider);
    final picked = await showPartyPickerSheet(
      context: context,
      title: mode == QuoteFor.lead ? 'Select lead' : 'Select customer',
      hint: mode == QuoteFor.lead
          ? 'Search leads by name, company, email or phone…'
          : 'Search customers by name, company, email…',
      noun: mode == QuoteFor.lead ? 'leads' : 'customers',
      search: mode == QuoteFor.lead ? ds.searchLeads : ds.searchCustomers,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _saveError = null;
      if (mode == QuoteFor.lead) {
        _leadPick = picked;
        _draft = _draft.copyWith(leadId: picked.id);
      } else {
        _customerPick = picked;
        _draft = _draft.copyWith(customerId: picked.id);
      }
      _spotConfirmed = false;
      _touched = true;
    });
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  Future<void> _save(_View v, {Map<String, String>? spotOverride}) async {
    setState(() => _attemptedSave = true);
    if (!v.canSubmit || v.missingTemplateField) return;
    // A new quote on the Item Quote layout first asks for its dynamic fields;
    // the create continues from the popup's Continue.
    if (!_isEdit &&
        v.spotAsk.isNotEmpty &&
        !_spotConfirmed &&
        spotOverride == null) {
      final values = await _openSpot(v, confirmLabel: 'Continue');
      if (values == null || !mounted) return;
      return _save(v, spotOverride: values);
    }
    final toast = ref.read(toastProvider.notifier);
    final ds = ref.read(quoteBuilderDsProvider);
    setState(() {
      _saving = true;
      _saveError = null;
      _fieldErrors = const {};
    });
    try {
      final Map<String, dynamic> res;
      if (_isEdit && v.groupMode) {
        // An option edits through its group: shared fields once + every option.
        final body = toGroupPatchJson(v.sharedPatch ?? const {}, v.allTabs,
            optionsDiffer: v.groupOptionsDiffer,
            primaryQuotationId:
                v.groupPrimaryChanged ? v.primaryQuotationId : null);
        final g = await ds.updateGroup(v.groupId, body);
        res = _optionOf(g, _quoteId);
        ref.invalidate(quoteBuilderGroupProvider(v.groupId));
      } else if (_isEdit) {
        res = await ds.update(_quoteId, v.editPatch!);
      } else {
        final draft = spotOverride == null
            ? _draft
            : _draft.copyWith(spotValues: spotOverride);
        if (v.groupMode) {
          // The whole group in one write: the shared fields once + every option's own lines.
          final g = await ds.createGroup(toNewGroupJson(
              toNewQuoteJson(draft, v.writeCtx), v.allTabs, _primaryTab));
          res = _optionOf(g, v.allTabs[_primaryTab].quotationId);
        } else {
          res = await ds.create(toNewQuoteJson(draft, v.writeCtx));
        }
      }
      if (!mounted) return;
      final saved = SavedQuote.fromJson(res);
      ref.invalidate(quotesProvider);
      ref.invalidate(leadQuotesProvider);
      if (_isEdit) {
        ref.invalidate(quoteRowProvider(_quoteId));
      }
      if (saved.approvalIsPending || saved.fieldValuesWarnings.isNotEmpty) {
        setState(() {
          _saving = false;
          _savedQuote = saved;
        });
      } else {
        _finish(saved);
      }
    } on AppError catch (e) {
      if (!mounted) return;
      if (_isEdit && e.statusCode == 409 && e.code == 'QUOTE_LOCKED') {
        // Sent meanwhile: show it as saved (read-only), not the refused edit.
        final q = v.quote;
        setState(() {
          _saving = false;
          _lockFailure = e;
          if (q != null) _seedFromQuote(q);
        });
        ref.invalidate(quoteBuilderQuoteProvider(_quoteId));
        return;
      }
      setState(() {
        _saving = false;
        _saveError = e.bareMessage;
        _fieldErrors = e.fieldErrors ?? const {};
      });
      toast.showError(e.bareMessage);
    }
  }

  /// The option (full quote payload) of a group response: [id] when given and
  /// present, else the primary option, else the first.
  Map<String, dynamic> _optionOf(Map<String, dynamic> group, String id) {
    final options = [
      for (final o
          in (group['options'] is List ? group['options'] as List : const []))
        if (o is Map) Map<String, dynamic>.from(o),
    ];
    if (options.isEmpty) return group;
    for (final o in options) {
      if (id.isNotEmpty && o['quotation_id']?.toString() == id) return o;
    }
    final primary = group['primary_quotation_id']?.toString() ?? '';
    for (final o in options) {
      if (o['quotation_id']?.toString() == primary) return o;
    }
    return options.first;
  }

  void _finish(SavedQuote saved) {
    final toast = ref.read(toastProvider.notifier);
    if (_isEdit) {
      ref.invalidate(quoteBuilderQuoteProvider(_quoteId));
      toast.show('Changes saved');
    } else {
      ref.read(quoteNewDraftProvider.notifier).state = null;
      toast.show(saved.number.isEmpty
          ? 'Quote created'
          : 'Quote ${saved.number} created');
    }
    context.pop(saved.raw);
  }

  Future<Map<String, String>?> _openSpot(_View v,
      {required String confirmLabel}) async {
    final values = await showSpotInputsSheet(
      context,
      fields: ref.read(quoteSpotInputsProvider(v.spotKey).future),
      values: _draft.spotValues,
      confirmLabel: confirmLabel,
    );
    if (values != null && mounted) {
      setState(() {
        _spotConfirmed = true;
        _draft = _draft.copyWith(spotValues: values);
      });
    }
    return values;
  }

  // ── "Amounts are" flip ───────────────────────────────────────────────────

  Future<void> _changeAmountsAre(_View v, String to) async {
    final from = v.amountsAre;
    if (from.isEmpty || to == from) {
      _patch((d) => d.copyWith(amountsAreChoice: to));
      return;
    }
    final needsChoice = _isEdit && !_draft.linesDirty
        ? _draft.items.isNotEmpty
        : flipNeedsChoice(_draft.items);
    if (!needsChoice) {
      _patch((d) => d.copyWith(amountsAreChoice: to, serverFlip: null));
      return;
    }
    final ds = ref.read(quoteBuilderDsProvider);
    final flipPriced = <String, Map<String, List<PricedLine>>>{};
    final items = _draft.items;
    final choice = await showPriceConversionSheet(
      context,
      from: from,
      to: to,
      grandTotalBefore: _preview?.shownGrandTotal,
      preview: (choice) async {
        final req = flipPreviewRequest(v.previewCtx, items, from, to, choice);
        try {
          final res = await ds.previewTax(req.body);
          final priced = mapPreviewLines(req.rows, res.lines);
          flipPriced[choice] = priced;
          final changes = <PriceChangeRow>[];
          for (final it in items) {
            if (it.isPackage) continue;
            final after = priced[it.key]?.firstOrNull?.unitPrice ?? '';
            final before = it.priceTouched || it.kind == LineKind.free
                ? it.rate
                : (v.livePriced[it.key]?.firstOrNull?.unitPrice ?? '');
            if (after.isEmpty || before.isEmpty) continue;
            if (double.tryParse(cleanUnitPrice(before)) ==
                double.tryParse(after)) continue;
            final qty = toQty(it.qty);
            changes.add(PriceChangeRow(
              name: it.name.isEmpty ? 'Line' : it.name,
              before: groupedUnitPrice(displayUnitPrice(before, qty)),
              after: groupedUnitPrice(displayUnitPrice(after, qty)),
            ));
          }
          return (
            grandTotalAfter: res.shownGrandTotal,
            changes: changes,
            error: null
          );
        } on AppError catch (e) {
          return (
            grandTotalAfter: null,
            changes: const <PriceChangeRow>[],
            error: previewErrorCopy(
                e.type == AppErrorType.validation, e.bareMessage),
          );
        }
      },
    );
    if (choice == null || !mounted) return;
    final plan = planFlip(v.previewCtx, to, choice);
    setState(() {
      if (plan == FlipPlan.resetToSaved && v.quote != null) {
        _draft = _draft.copyWith(
            amountsAreChoice: to,
            items: itemsFromSavedLines(v.quote!.lines),
            serverFlip: null);
        return;
      }
      final next =
          applyPriceFlip(_draft.items, flipPriced[choice] ?? const {}, choice);
      if (plan == FlipPlan.serverFlip) {
        _draft = _draft.copyWith(
            amountsAreChoice: to, items: next, serverFlip: choice);
      } else {
        _draft = _draft.copyWith(
          amountsAreChoice: to,
          items: next,
          serverFlip: null,
          linesDirty: _draft.linesDirty || plan == FlipPlan.rewriteLinesDirty,
        );
      }
    });
  }

  // ── Derived view ─────────────────────────────────────────────────────────

  _View _buildView() {
    // The draft is seeded by the listener in didChangeDependencies; until then
    // the screen shows its loading state.
    final quote = _isEdit && _seeded
        ? ref.watch(quoteBuilderQuoteProvider(_quoteId)).valueOrNull
        : null;
    if (_isEdit) ref.watch(quoteBuilderQuoteProvider(_quoteId));
    final readOnly =
        _isEdit && ((quote?.isLocked ?? false) || _lockFailure != null);
    final leadLocked = !_isEdit && _presetLeadId.isNotEmpty;
    final customerLocked =
        !_isEdit && _presetLeadId.isEmpty && _presetCustomerId.isNotEmpty;
    final mode = leadLocked
        ? QuoteFor.lead
        : (customerLocked ? QuoteFor.customer : _draft.quoteFor);

    // Templates.
    final templatesAsync = ref.watch(quoteBuilderTemplatesProvider);
    final active = [
      for (final t
          in templatesAsync.valueOrNull ?? const <QuoteTemplateOption>[])
        if (t.isActive) t
    ];
    final defaultTemplateId = active
            .where((t) => t.isDefault && t.category.isEmpty)
            .firstOrNull
            ?.id ??
        '';
    final savedTemplateId = quote == null
        ? ''
        : (quote.templateId.isNotEmpty
            ? quote.templateId
            : active
                    .where((t) => t.name == quote.templateName)
                    .firstOrNull
                    ?.id ??
                '');
    final templateId = _draft.templateChoice ??
        (_isEdit ? savedTemplateId : defaultTemplateId);
    final templateFallback =
        templatesAsync.hasError || (templatesAsync.hasValue && active.isEmpty);
    final templateOptions = [
      ...active,
      if (quote != null &&
          quote.templateId.isNotEmpty &&
          !active.any((t) => t.id == quote.templateId))
        QuoteTemplateOption(
            id: quote.templateId,
            // "(inactive)" only when the list loaded and lacks it — a role that
            // cannot read templates (403) would otherwise see every quote's own
            // template labelled inactive.
            name:
                '${quote.templateName.isEmpty ? 'Current template' : quote.templateName}'
                '${templatesAsync.hasError ? '' : ' (inactive)'}'),
    ];

    final hidden = _isEdit ? hiddenFields(quote) : <String>{};
    final taxDefaults =
        readOnly ? null : ref.watch(quoteTaxDefaultsProvider).valueOrNull;
    final amountsAre = _draft.amountsAreChoice ?? taxDefaults?.amountsAre ?? '';
    final recurringEnabled = (taxDefaults?.recurringBillingEnabled ?? false) ||
        quote?.chargeSummary != null;

    final fieldsAsync = ref.watch(quoteTemplateFieldsProvider(templateId));
    final templateFields = fieldsAsync.valueOrNull ?? const <TemplateField>[];
    final configAsync = ref.watch(quoteTemplateConfigProvider(templateId));
    final layoutConfigured =
        configAsync.valueOrNull?.needsConfiguration ?? false;
    final headings = layoutConfigured
        ? configAsync.valueOrNull!.headings
        : const <SectionHeading>[];
    final sectionDefaults =
        configAsync.valueOrNull?.sectionDefaults ?? const <String, String>{};

    final libraryAsync =
        readOnly ? null : ref.watch(quoteClauseLibraryProvider);
    final library = libraryAsync?.valueOrNull ?? const <LibraryClause>[];
    final productsAsync = ref.watch(productsProvider);
    final catalog = productsAsync.valueOrNull ?? const <Product>[];

    // Clauses + sections.
    final today = localIsoDate();
    final productTypeIds = <String>{
      for (final it in _draft.items)
        for (final p in catalog)
          if (p.id == it.productId) _productTypeId(p),
    }..remove('');
    final familyDefaults = defaultClauseRows(library, const {}, today);
    final initialClauses = _isEdit
        ? savedClauseRows(quote?.clauses ?? const [])
        : defaultClauseRows(library, productTypeIds, today);
    final clauseRows = _draft.clauseRows ?? initialClauses;
    final sectionPicks = _draft.sectionPicks ??
        (_isEdit && quote != null
            ? quote.sections
            : defaultSectionPicks(headings, sectionDefaults, productTypeIds));
    final missingSections = missingMandatoryHeadings(headings, sectionPicks);
    final libraryLoaded = libraryAsync == null || !libraryAsync.isLoading;
    final legacyTerms = _isEdit
        ? (quote?.clauses.isEmpty ?? true)
        : (libraryLoaded && familyDefaults.isEmpty);

    // Spot inputs.
    final spotKey = (
      templateId: templateId,
      leadId: !_isEdit && mode == QuoteFor.lead ? _draft.leadId : '',
      customerId:
          !_isEdit && mode == QuoteFor.customer ? _draft.customerId : '',
      quotationId: _isEdit ? _quoteId : '',
    );
    final spotFields = layoutConfigured && !readOnly && templateId.isNotEmpty
        ? (ref.watch(quoteSpotInputsProvider(spotKey)).valueOrNull ??
            const <SpotInputField>[])
        : const <SpotInputField>[];
    final spotAsk = fieldsNeedingInput(spotFields);

    // Template fields.
    final stored = quote?.fieldValues ?? const <String, dynamic>{};
    Object valueOf(TemplateField f) =>
        fieldValueOf(f, _draft.fieldEdits, stored, !_isEdit);
    final missingTemplateField = !hidden.contains('field_values') &&
        templateFields.any((f) => isFieldMissing(f, valueOf(f)));

    // Live preview.
    final previewCtx = PreviewContext(
      isEdit: _isEdit,
      linesDirty: _draft.linesDirty,
      savedMode: quote?.amountsAre ?? '',
      quotationId: _isEdit ? _quoteId : null,
      leadId: !_isEdit && mode == QuoteFor.lead && _draft.leadId.isNotEmpty
          ? _draft.leadId
          : null,
      customerId:
          !_isEdit && mode == QuoteFor.customer && _draft.customerId.isNotEmpty
              ? _draft.customerId
              : null,
      placeOfSupply: _draft.placeOfSupply,
    );
    final canPreview =
        !readOnly && _savedQuote == null && (!_isEdit || quote != null);
    final liveReq = canPreview
        ? livePreviewRequest(
            previewCtx, _draft.items, amountsAre, _draft.serverFlip)
        : null;
    if (canPreview) _schedulePreview(liveReq);
    final hasPricedLines = _isEdit
        ? _draft.items.isNotEmpty || !_draft.linesDirty
        : includedLines(_draft.items).isNotEmpty;
    final livePriced = _preview == null
        ? <String, List<PricedLine>>{}
        : mapPreviewLines(_previewRows, _preview!.lines);
    final priced = readOnly && quote != null
        ? savedLinePricing(_draft.items, quote.lines)
        : livePriced;
    final updating = _requestedKey != null && _requestedKey != _answeredKey;

    // Alternative options: the template decides on a new quote; an edited option
    // always goes through its group.
    final pickedTemplate =
        templateOptions.where((t) => t.id == templateId).firstOrNull;
    final groupId = _isEdit ? (quote?.optionGroupId ?? '') : '';
    final groupMode =
        _isEdit ? groupId.isNotEmpty : (pickedTemplate?.buildsGroup ?? false);
    final groupAsync = groupMode && _isEdit
        ? ref.watch(quoteBuilderGroupProvider(groupId))
        : null;
    final group = groupAsync?.valueOrNull;
    final maxOptions = pickedTemplate?.maxOptions ?? 3;
    final canChangeSet = !_isEdit || group?.state == 'draft';
    if (groupMode && !_groupSeeded) {
      if (!_isEdit) {
        _groupSeeded = true;
        _tabs = [firstTab(_activeOption)];
      } else if (group != null && quote != null && group.options.isNotEmpty) {
        _groupSeeded = true;
        _tabs = tabsFromOptions(group.options);
        _activeTab = group.options
            .indexWhere((o) => o.id == quote.id)
            .clamp(0, group.options.length - 1);
        _primaryTab = group.options
            .indexWhere((o) => o.id == group.primaryQuotationId)
            .clamp(0, group.options.length - 1);
      }
    } else if (!groupMode &&
        pickedTemplate != null &&
        _groupSeeded &&
        !_isEdit) {
      // Switched back to a single-quote template (only possible with one option).
      // Guarded on a known template: while the templates are still loading
      // `groupMode` is false and this branch wiped the tabs restored from a
      // kept draft, after which tab A was re-seeded from the active option
      // (UAT: both options saved with the same lines).
      _groupSeeded = false;
      _tabs = const [];
      _activeTab = 0;
      _primaryTab = 0;
    }
    final allTabs = groupMode && _tabs.isNotEmpty
        ? stashActive(_tabs, _activeTab, _activeOption)
        : const <OptionTab>[];
    final otherOptionProblems = groupMode
        ? [
            for (final p in optionProblems(allTabs, _isEdit))
              if (p.label != optionLabel(_activeTab)) p
          ]
        : const <({String label, String problem})>[];
    final groupLoading = _isEdit && groupMode && group == null;

    // Validation.
    final problems = _draft.items.map(lineProblem).toSet();
    final hasNoLines =
        includedLines(_draft.items).isEmpty && (!_isEdit || _draft.linesDirty);
    final validityInPast = validUntilInPast(
        _draft.validUntil, _isEdit ? (quote?.validUntil ?? '') : '', today);
    final hasRecurringLine = _draft.items
        .any((it) => effectiveCharge(it, livePriced[it.key]).isRecurring);
    final partyChosen = _isEdit ||
        (mode == QuoteFor.lead
            ? _draft.leadId.isNotEmpty
            : _draft.customerId.isNotEmpty);
    final writeCtx = BuilderWriteContext(
      templateId: templateId,
      amountsAre: amountsAre,
      fields: templateFields,
      legacyTerms: legacyTerms,
      savedTemplateId: savedTemplateId,
      statusId:
          _isEdit ? null : ref.watch(quoteDefaultStatusProvider).valueOrNull,
    );
    final editPatch = _isEdit && quote != null
        ? toQuoteUpdateJson(_draft, quote, writeCtx)
        : null;
    final sharedPatch = editPatch == null
        ? null
        : (Map<String, dynamic>.from(editPatch)
          ..remove('line_items')
          ..remove('quotation_title'));
    final groupOptionsDiffer =
        groupMode && _isEdit && group != null && allTabs.isNotEmpty
            ? optionsChanged(allTabs, group.options)
            : false;
    final primaryId = allTabs.isNotEmpty && _primaryTab < allTabs.length
        ? allTabs[_primaryTab].quotationId
        : '';
    final groupPrimaryChanged = groupMode &&
        _isEdit &&
        group != null &&
        primaryId.isNotEmpty &&
        primaryId != group.primaryQuotationId;
    final hasChanges = !_isEdit ||
        (groupMode
            ? ((sharedPatch?.isNotEmpty ?? false) ||
                groupOptionsDiffer ||
                groupPrimaryChanged)
            : (editPatch != null && editPatch.isNotEmpty));
    final recurringWithSubscription =
        hasRecurringLine && _draft.payType == 'subscription';
    final hasTemplate = templateId.isNotEmpty || templateFallback;
    final optionBlock = optionBlockReason(otherOptionProblems);
    final block = optionBlock ??
        blockReason(
          items: _draft.items,
          validityInPast: validityInPast,
          recurringWithSubscription: recurringWithSubscription,
          hasAmountsAre: amountsAre.isNotEmpty,
          attemptedSave: _attemptedSave,
          missingTemplateField: missingTemplateField,
        );
    final canSubmit = !readOnly &&
        _savedQuote == null &&
        hasTemplate &&
        partyChosen &&
        !problems.contains(LineProblem.qty) &&
        !problems.contains(LineProblem.price) &&
        !problems.contains(LineProblem.charge) &&
        !problems.contains(LineProblem.description) &&
        !problems.contains(LineProblem.tax) &&
        !hasNoLines &&
        !validityInPast &&
        !recurringWithSubscription &&
        amountsAre.isNotEmpty &&
        hasChanges &&
        otherOptionProblems.isEmpty &&
        !groupLoading &&
        !_saving;

    return _View(
      quote: quote,
      quoteLoading: _isEdit && quote == null,
      quoteError:
          _isEdit ? ref.watch(quoteBuilderQuoteProvider(_quoteId)).error : null,
      readOnly: readOnly,
      leadLocked: leadLocked,
      customerLocked: customerLocked,
      mode: mode,
      templatesLoading: templatesAsync.isLoading,
      templateOptions: templateOptions,
      templateId: templateId,
      templateFallback: templateFallback,
      hidden: hidden,
      amountsAre: amountsAre,
      taxDefaults: taxDefaults,
      recurringEnabled: recurringEnabled,
      templateFields: templateFields,
      templateFieldsLoading: templateId.isNotEmpty && fieldsAsync.isLoading,
      templateFieldsError: fieldsAsync.hasError
          ? 'The template’s fields could not be loaded.'
          : null,
      layoutConfigured: layoutConfigured,
      headings: headings,
      sectionsLoading: configAsync.isLoading,
      sectionsError:
          configAsync.hasError ? 'Could not load the quote sections.' : null,
      sectionPicks: sectionPicks,
      missingSections: missingSections,
      library: library,
      libraryLoading: libraryAsync?.isLoading ?? false,
      libraryError: (libraryAsync?.hasError ?? false)
          ? 'The clause library could not be loaded. Saved and default clauses are kept.'
          : null,
      clauseRows: clauseRows,
      legacyTerms: legacyTerms,
      today: today,
      catalog: catalog,
      catalogLoading: productsAsync.isLoading,
      spotKey: spotKey,
      spotAsk: spotAsk,
      valueOf: valueOf,
      missingTemplateField: missingTemplateField,
      previewCtx: previewCtx,
      priced: priced,
      livePriced: livePriced,
      hasPricedLines: hasPricedLines,
      updating: updating,
      hasRecurringLine: hasRecurringLine,
      writeCtx: writeCtx,
      editPatch: editPatch,
      canSubmit: canSubmit,
      blockReason: block,
      groupMode: groupMode,
      groupLoading: groupLoading,
      groupError: groupAsync?.error,
      groupId: groupId,
      allTabs: allTabs,
      maxOptions: maxOptions,
      canChangeSet: canChangeSet,
      sharedPatch: sharedPatch,
      groupOptionsDiffer: groupOptionsDiffer,
      groupPrimaryChanged: groupPrimaryChanged,
      primaryQuotationId: primaryId,
      incompleteReason: incompleteReason(
          hasTemplate: hasTemplate,
          partyChosen: partyChosen,
          hasNoLines: hasNoLines),
      validityInPast: validityInPast,
    );
  }

  static String _productTypeId(Product p) {
    final v = p.raw['product_type'] ?? p.raw['product_type_id'];
    if (v is String) return v;
    if (v is Map) return (v['product_type_id'] ?? v['id'] ?? '').toString();
    return '';
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final v = _buildView();
    final title = !_isEdit
        ? 'New quote'
        : v.readOnly
            ? 'Quote ${v.quote?.number ?? ''}'.trim()
            : 'Edit quote ${v.quote?.number ?? ''}'.trim();
    final canLeave =
        _saving ? false : !(_touched && _savedQuote == null && !v.readOnly);
    return PopScope(
      canPop: canLeave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onDismiss();
      },
      child: Container(
        color: AppColors.bgDetail,
        child: Column(
          children: [
            _header(title),
            Expanded(
              child: v.quoteLoading
                  ? (v.quoteError != null
                      ? Padding(
                          padding: EdgeInsets.all(16.w),
                          child: QbNotice(
                            tone: QbTone.danger,
                            icon: PhosphorIconsRegular.warningCircle,
                            children: [
                              qbNoticeText(v.quoteError is AppError
                                  ? (v.quoteError as AppError).message
                                  : 'Could not load the quote.')
                            ],
                          ),
                        )
                      : const Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: AppColors.navy)))
                  : _savedQuote != null
                      ? ListView(
                          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 20.h),
                          children: [_savedNotice(_savedQuote!)],
                        )
                      : _form(v),
            ),
            if (!v.quoteLoading) _actionBar(v),
          ],
        ),
      ),
    );
  }

  Widget _form(_View v) {
    final ro = v.readOnly;
    final q = v.quote;
    final stateName = ref.watch(gstStateNameProvider);
    final flags = paymentFlags(_draft.payType);
    final payOptions = [
      for (final o in payTypeOptions)
        if (!(v.hasRecurringLine && o.$1 == 'subscription')) o,
    ];
    return ListView(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 20.h),
      children: [
        // ── Notices ──
        if (ro)
          Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: QbNotice(
              tone: _lockFailure != null ? QbTone.danger : QbTone.warning,
              icon: PhosphorIconsRegular.lockSimple,
              // As on web: offered while the quote is revisable, and after a
              // QUOTE_LOCKED refusal only when the server suggests REVISE.
              action: _canRevise &&
                      (_lockFailure == null ||
                          _lockFailure!.nextAction == 'REVISE')
                  ? TextButton(
                      onPressed: () => context.pop('revise'),
                      child: const Text('Revise quote'),
                    )
                  : null,
              children: [
                qbNoticeText(_lockFailure != null
                    ? '${_lockFailure!.bareMessage} Your changes were not saved.'
                    : (_focusPayment ? paymentLockedCopy : lockedCopy)),
              ],
            ),
          ),
        if (_isEdit && !ro && (q?.approvalIsPending ?? false))
          Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: QbNotice(
                tone: QbTone.warning,
                icon: PhosphorIconsRegular.shieldWarning,
                children: [qbNoticeText(approvalCopyNeutral)]),
          ),
        if (!ro && v.hidden.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: QbNotice(
                tone: QbTone.info,
                icon: PhosphorIconsRegular.eyeSlash,
                children: [qbNoticeText(hiddenFieldsNotice(v.hidden))]),
          ),
        // A customer-mode refusal is shown under the customer picker instead.
        if (_saveError != null && !(v.mode == QuoteFor.customer && !_isEdit))
          Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: QbNotice(
                tone: QbTone.danger,
                icon: PhosphorIconsRegular.warningCircle,
                children: [qbNoticeText(_saveError!)]),
          ),

        // ── Template + title ──
        const QbSectionLabel('Quote'),
        const QbFieldLabel('Template', required: true),
        SizedBox(height: 7.h),
        QbPickerBox(
          text: v.templateOptions
                  .where((t) => t.id == v.templateId)
                  .firstOrNull
                  ?.label ??
              '',
          placeholder: v.templatesLoading
              ? 'Loading templates…'
              : v.templateFallback
                  ? (_isEdit
                      ? (q?.templateName.isNotEmpty == true
                          ? q!.templateName
                          : 'Current template')
                      : 'Organisation’s default template')
                  : 'Select a template…',
          error: _fieldErrors.containsKey('template'),
          onTap: ro || v.templateFallback
              ? null
              : () async {
                  final id = await qbPickOne(context,
                      title: 'Template',
                      options: [
                        for (final t in v.templateOptions)
                          // Single-quote templates are not offered while
                          // alternatives exist (switching would drop them).
                          if (!_templateBlocked(v, t.buildsGroup, t.id))
                            (t.id, t.label)
                      ],
                      selected: v.templateId);
                  if (id != null) {
                    _patch((d) =>
                        d.copyWith(templateChoice: id, sectionPicks: null));
                    _spotConfirmed = false;
                  }
                },
        ),
        _fieldError('template'),
        if (_alternativesBlockSwitch(v))
          const QbHint(
              'Remove the alternatives to switch to a single-quote template.')
        else if (_isEdit && v.groupMode)
          const QbHint(
              'This quote has options, so its template stays an options template.'),
        SizedBox(height: 14.h),
        _textField(
          label: v.groupMode
              ? 'Option ${optionLabel(_activeTab)} title'
              : 'Quote title',
          ctrl: _titleCtrl,
          hint: v.groupMode
              ? 'e.g. Premium package'
              : 'e.g. CRM Annual Plan – ABC Corp',
          disabled: ro || v.hidden.contains('quotation_title'),
          errorKey: 'quotation_title',
          onChanged: (t) => _patch((d) => d.copyWith(title: t)),
        ),
        SizedBox(height: 14.h),

        // ── Party ──
        ..._partySection(v),

        // ── Alternative options: one tab per option; the lines below are the active option's ──
        if (v.groupMode && v.allTabs.isNotEmpty) ...[
          SizedBox(height: 8.h),
          if (_isEdit && v.groupError != null)
            QbNotice(
              tone: QbTone.danger,
              icon: PhosphorIconsRegular.warningCircle,
              children: [
                qbNoticeText(
                    'This quote is one option of a group and is changed through the group, which could not be loaded: ${v.groupError is AppError ? (v.groupError as AppError).bareMessage : v.groupError}')
              ],
            ),
          QuoteOptionTabsBar(
            tabs: v.allTabs,
            active: _activeTab,
            primary: _primaryTab,
            max: v.maxOptions,
            disabled: ro,
            canChangeSet: v.canChangeSet,
            onSelect: _selectTab,
            onAdd: () => _addAlternative(v.maxOptions),
            onRemove: _removeOption,
            onMakePrimary: _makePrimary,
          ),
        ],

        // ── Lines ──
        SizedBox(height: 8.h),
        QuoteLinesEditor(
          items: _draft.items,
          // Editing a line hands the lines to the client: a pending
          // server-side flip is dropped.
          onItemsChange: (items) => _patch((d) =>
              d.copyWith(items: items, linesDirty: true, serverFlip: null)),
          catalog: v.catalog,
          catalogLoading: v.catalogLoading,
          priced: v.priced,
          pricing: !ro && v.updating,
          amountsAre: v.amountsAre,
          disabled: ro || v.hidden.contains('line_items'),
          recurringEnabled: v.recurringEnabled,
          rateMaster: v.taxDefaults?.rateMaster ?? false,
        ),
        _fieldError('line_items'),
        SizedBox(height: 14.h),

        // ── Totals ──
        QuoteTotalsBlock(
          summary: ro
              ? q?.taxSummary
              : (v.hasPricedLines ? _preview?.summary : null),
          taxableTotal: v.hasPricedLines ? _preview?.taxableTotal : null,
          grandTotal: v.hasPricedLines ? _preview?.grandTotal : null,
          loading: !ro &&
              v.hasPricedLines &&
              _preview == null &&
              _previewError == null,
          updating: !ro && _preview != null && v.updating,
          error: !ro && v.hasPricedLines ? _previewError : null,
          discountPct: q?.discountPct ?? '',
          chargeSummary: ro
              ? q?.chargeSummary
              : (v.hasPricedLines ? _preview?.chargeSummary : null),
        ),

        // ── Payment ──
        QbSectionLabel('Payment & validity', key: _paymentKey),
        QbChipField(
          label: 'Payment type',
          required: true,
          disabled: ro,
          options: payOptions,
          selected: _draft.payType,
          onSelect: (p) => _patch((d) => d.copyWith(payType: p)),
        ),
        _fieldError('payment_type'),
        if (flags.installments || flags.billing) SizedBox(height: 14.h),
        if (flags.installments || flags.billing)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (flags.installments)
              Expanded(
                child: _textField(
                  label: '# Installments',
                  ctrl: _installmentsCtrl,
                  hint: 'min 2',
                  disabled: ro,
                  numeric: true,
                  errorKey: 'num_installments',
                  onChanged: (t) => _patch((d) => d.copyWith(installments: t)),
                ),
              ),
            if (flags.installments && flags.billing) SizedBox(width: 9.w),
            if (flags.billing)
              Expanded(
                child: _textField(
                  label: 'Billing period (days)',
                  ctrl: _billingCtrl,
                  hint: 'e.g. 30',
                  disabled: ro,
                  numeric: true,
                  errorKey: 'billing_period_days',
                  onChanged: (t) => _patch((d) => d.copyWith(billing: t)),
                ),
              ),
          ]),
        SizedBox(height: 14.h),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _validUntilField(v)),
          SizedBox(width: 9.w),
          Expanded(
            child: _dateField(
              label: 'Due date',
              value: _draft.dueDate,
              disabled: ro || v.hidden.contains('due_date'),
              errorKey: 'due_date',
              onPick: (d) => _patch((x) => x.copyWith(dueDate: d)),
              // A date can be changed on an edit, not cleared.
              onClear:
                  _isEdit ? null : () => _patch((x) => x.copyWith(dueDate: '')),
            ),
          ),
        ]),

        // ── Tax & contract ──
        const QbSectionLabel('Tax'),
        QbChipField(
          label: 'Amounts are',
          required: true,
          disabled: ro,
          options: [
            for (final e in quoteAmountsAreLabels.entries) (e.key, e.value)
          ],
          selected: v.amountsAre,
          onSelect: (to) => _changeAmountsAre(v, to),
        ),
        if (v.amountsAre.isEmpty && !ro)
          QbHint(v.taxDefaults == null ? 'Loading…' : 'Select…'),
        SizedBox(height: 14.h),
        const QbFieldLabel('Place of supply'),
        SizedBox(height: 7.h),
        QbPickerBox(
          text: _draft.placeOfSupply.isEmpty
              ? ''
              : stateName(_draft.placeOfSupply),
          placeholder: 'Select a state…',
          error: _fieldErrors.containsKey('place_of_supply_state_code'),
          onTap: ro
              ? null
              : () async {
                  final code = await pickGstState(context, ref,
                      selected: _draft.placeOfSupply.isEmpty
                          ? null
                          : _draft.placeOfSupply);
                  if (code != null && mounted)
                    _patch((d) => d.copyWith(placeOfSupply: code));
                },
          trailing: !ro && _draft.placeOfSupply.isNotEmpty
              ? GestureDetector(
                  onTap: () => _patch((d) => d.copyWith(placeOfSupply: '')),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6.w),
                    child: Icon(PhosphorIconsRegular.x,
                        size: 14.sp, color: AppColors.textPlaceholder),
                  ),
                )
              : null,
        ),
        _fieldError('place_of_supply_state_code'),
        SizedBox(height: 14.h),
        _textField(
          label: 'Contract reference',
          ctrl: _contractCtrl,
          hint: 'e.g. MSA-2026-014',
          disabled: ro || v.hidden.contains('contract_ref'),
          errorKey: 'contract_ref',
          maxLength: 140,
          onChanged: (t) => _patch((d) => d.copyWith(contractRef: t)),
        ),

        // ── Template fields / sections / quote details ──
        if (!v.hidden.contains('field_values'))
          TemplateFieldsSection(
            fields: v.templateFields,
            valueOf: v.valueOf,
            onChange: (key, value) => _patch(
                (d) => d.copyWith(fieldEdits: {...d.fieldEdits, key: value})),
            warnings: _isEdit ? (q?.fieldValuesWarnings ?? const []) : const [],
            loading: v.templateFieldsLoading,
            error: v.templateFieldsError,
            showMissing: _attemptedSave,
            disabled: ro,
          ),
        if (v.headings.isNotEmpty)
          QuoteSectionsEditor(
            headings: v.headings,
            picks: v.sectionPicks,
            onPicksChange: (p) => _patch((d) => d.copyWith(sectionPicks: p)),
            loading: v.sectionsLoading,
            error: v.sectionsError,
            showMissing: _attemptedSave,
            disabled: ro || (q?.isLocked ?? false),
          ),
        if (v.layoutConfigured && !ro && v.spotAsk.isNotEmpty) ...[
          const QbSectionLabel('Quote details'),
          Row(children: [
            Expanded(
              child: Text(
                  _isEdit
                      ? '${v.spotAsk.length} field${v.spotAsk.length == 1 ? '' : 's'} typed for this quote (bill-to / ship-to / reference …).'
                      : '${v.spotAsk.length} field${v.spotAsk.length == 1 ? '' : 's'} to fill in — asked when you create the quote.',
                  style: AppText.custom(
                      size: 12,
                      weight: FontWeight.w500,
                      color: AppColors.textMuted)),
            ),
            SizedBox(width: 8.w),
            GestureDetector(
              onTap: () => _openSpot(v, confirmLabel: 'Apply'),
              child: Container(
                height: 34.h,
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: const Color(0xFFE6E7EA)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(PhosphorIconsRegular.pencilSimple,
                      size: 13.sp, color: AppColors.textLabelAlt),
                  SizedBox(width: 5.w),
                  Text(_isEdit ? 'Edit details' : 'Fill in now',
                      style: AppText.custom(
                          size: 12.5,
                          weight: FontWeight.w700,
                          color: AppColors.textLabelAlt)),
                ]),
              ),
            ),
          ]),
        ],
        if (_attemptedSave && v.missingSections.isNotEmpty && !ro) ...[
          SizedBox(height: 10.h),
          QbNotice(
            tone: QbTone.warning,
            icon: PhosphorIconsRegular.lockSimple,
            children: [
              qbNoticeText(mandatoryHeadingsNotice(v.missingSections))
            ],
          ),
        ],

        // ── Notes ──
        const QbSectionLabel('Notes'),
        _textField(
          label: 'Notes',
          ctrl: _notesCtrl,
          hint: 'Notes shown on the quote..',
          multiline: true,
          disabled: ro || v.hidden.contains('notes'),
          errorKey: 'notes',
          onChanged: (t) => _patch((d) => d.copyWith(notes: t)),
        ),

        // ── Terms — the clause list; the Item Quote layout prints sections instead ──
        if (!v.layoutConfigured)
          QuoteClausesEditor(
            rows: v.clauseRows,
            onRowsChange: (rows) => _patch((d) => d.copyWith(clauseRows: rows)),
            library: v.library,
            libraryLoading: v.libraryLoading,
            libraryError: v.libraryError,
            today: v.today,
            legacy: v.legacyTerms,
            terms: _draft.terms,
            onTermsChange: (t) => _patch((d) => d.copyWith(terms: t)),
            termsDisabled: v.hidden.contains('terms_and_conditions'),
            disabled: ro,
          ),
      ],
    );
  }

  List<Widget> _partySection(_View v) {
    final q = v.quote;
    if (_isEdit) {
      final isLead = (q?.leadName ?? '').isNotEmpty;
      return [
        AppTextField(
          label: isLead ? 'Lead' : 'Customer',
          readOnly: true,
          value: isLead
              ? q!.leadName
              : (q?.customerName.isNotEmpty == true ? q!.customerName : '—'),
          suffixIcon: PhosphorIconsRegular.lockSimple,
        ),
      ];
    }
    if (v.leadLocked || v.customerLocked) {
      final pick = v.leadLocked ? _leadPick : _customerPick;
      return [
        AppTextField(
          label: v.leadLocked ? 'Lead' : 'Customer',
          required: true,
          readOnly: true,
          value: pick?.label ?? (v.leadLocked ? 'This lead' : 'This customer'),
          suffixIcon: PhosphorIconsRegular.lockSimple,
        ),
        if ((pick?.sub ?? '').isNotEmpty) QbHint(pick!.sub),
        if (v.customerLocked && _saveError != null)
          QbHint(_customerModeError(_saveError!), error: true),
      ];
    }
    final mode = v.mode;
    final pick = mode == QuoteFor.lead ? _leadPick : _customerPick;
    final id = mode == QuoteFor.lead ? _draft.leadId : _draft.customerId;
    return [
      const QbFieldLabel('Quote for', required: true),
      SizedBox(height: 8.h),
      Row(children: [
        QbChip(
          label: 'Lead',
          icon: PhosphorIconsRegular.user,
          selected: mode == QuoteFor.lead,
          onTap: () => setState(() {
            _draft = _draft.copyWith(quoteFor: QuoteFor.lead);
            _saveError = null;
          }),
        ),
        SizedBox(width: 8.w),
        QbChip(
          label: 'Customer',
          icon: PhosphorIconsRegular.buildings,
          selected: mode == QuoteFor.customer,
          onTap: () => setState(() {
            _draft = _draft.copyWith(quoteFor: QuoteFor.customer);
            _saveError = null;
          }),
        ),
      ]),
      QbHint(mode == QuoteFor.lead ? leadModeHint : customerModeHint),
      SizedBox(height: 12.h),
      AppTextField(
        label: mode == QuoteFor.lead ? 'Lead' : 'Customer',
        required: true,
        readOnly: true,
        value: id.isEmpty ? null : (pick?.label ?? id),
        hint: mode == QuoteFor.lead
            ? 'Search leads by name, company, email or phone…'
            : 'Search customers by name, company, email…',
        suffixIcon: PhosphorIconsRegular.magnifyingGlass,
        errorText: _fieldErrors[mode == QuoteFor.lead ? 'lead' : 'customer']
            ?.firstOrNull,
        onTap: () => _pickParty(mode),
      ),
      if (id.isNotEmpty && (pick?.sub ?? '').isNotEmpty) QbHint(pick!.sub),
      if (mode == QuoteFor.customer && _saveError != null)
        QbHint(_customerModeError(_saveError!), error: true),
    ];
  }

  /// Copy shown inline when the server refuses a customer-mode create.
  static String _customerModeError(String message) =>
      message.isNotEmpty ? message : customerNoLeadCopy;

  Widget _validUntilField(_View v) {
    final today = DateTime.now();
    final error =
        v.validityInPast ? 'The validity date can’t be in the past.' : null;
    return _dateField(
      label: 'Quote valid until',
      value: _draft.validUntil,
      disabled: v.readOnly || v.hidden.contains('valid_until'),
      errorKey: 'valid_until',
      errorText: error,
      // Every quote expires: no validity date in the past.
      firstDate: DateTime(today.year, today.month, today.day),
      onPick: (d) => _patch((x) => x.copyWith(validUntil: d)),
      // Changed on an edit, never cleared (the API takes a date, not a blank).
      onClear: _isEdit ? null : () => _patch((x) => x.copyWith(validUntil: '')),
    );
  }

  Widget _dateField({
    required String label,
    required String value,
    required bool disabled,
    required String errorKey,
    required ValueChanged<String> onPick,
    VoidCallback? onClear,
    String? errorText,
    DateTime? firstDate,
  }) {
    final err = errorText ?? _fieldErrors[errorKey]?.firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      QbFieldLabel(label),
      SizedBox(height: 7.h),
      QbPickerBox(
        text: value.isEmpty ? '' : formatApiDay(value),
        placeholder: 'Pick a date',
        icon: PhosphorIconsRegular.calendarBlank,
        error: err != null,
        onTap: disabled
            ? null
            : () async {
                final now = DateTime.now();
                final first = firstDate ?? DateTime(now.year - 2);
                var initial = DateTime.tryParse(value) ?? now;
                if (initial.isBefore(first)) initial = first;
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: first,
                  lastDate: DateTime(now.year + 5),
                );
                if (picked != null) onPick(isoDay(picked));
              },
        trailing: !disabled && onClear != null && value.isNotEmpty
            ? GestureDetector(
                onTap: onClear,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6.w),
                  child: Icon(PhosphorIconsRegular.x,
                      size: 14.sp, color: AppColors.textPlaceholder),
                ),
              )
            : null,
      ),
      if (err != null) QbHint(err, error: true),
    ]);
  }

  Widget _textField({
    required String label,
    required TextEditingController ctrl,
    required String hint,
    required bool disabled,
    required String errorKey,
    required ValueChanged<String> onChanged,
    bool multiline = false,
    bool numeric = false,
    int? maxLength,
  }) {
    return AppTextField(
      label: label,
      controller: ctrl,
      hint: hint,
      readOnly: disabled,
      value: disabled ? ctrl.text : null,
      multiline: multiline,
      keyboardType: numeric ? TextInputType.number : null,
      inputFormatters: [
        if (numeric) FilteringTextInputFormatter.digitsOnly,
        if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
      ],
      errorText: _fieldErrors[errorKey]?.firstOrNull,
      onChanged: onChanged,
    );
  }

  Widget _fieldError(String key) {
    final msg = _fieldErrors[key]?.firstOrNull;
    return msg == null ? const SizedBox.shrink() : QbHint(msg, error: true);
  }

  /// "<number> is saved." + the discount-approval notice + the saved totals.
  Widget _savedNotice(SavedQuote s) {
    final pending = s.approvalIsPending;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text.rich(TextSpan(
        style: AppText.custom(
            size: 14, weight: FontWeight.w500, color: AppColors.textBody),
        children: [
          TextSpan(
              text: s.number.isEmpty ? 'The quote' : s.number,
              style: AppText.custom(
                  size: 14,
                  weight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const TextSpan(text: ' is saved.'),
        ],
      )),
      SizedBox(height: 14.h),
      if (pending)
        QbNotice(
          tone: QbTone.warning,
          icon: PhosphorIconsRegular.shieldWarning,
          children: [
            qbNoticeText(_isEdit ? approvalCopyNeutral : approvalCopy,
                strong: true),
            if (s.discountPct.isNotEmpty)
              qbNoticeText('Discount on this quote: ${pct2(s.discountPct)}.'),
            qbNoticeText(
                '${_isEdit ? '' : 'Your approver has been notified. '}You can keep working on the quote meanwhile.',
                muted: true),
          ],
        ),
      if (s.fieldValuesWarnings.isNotEmpty)
        QbNotice(
          tone: QbTone.warning,
          icon: PhosphorIconsRegular.warning,
          children: [for (final w in s.fieldValuesWarnings) qbNoticeText(w)],
        ),
      if (s.taxSummary != null)
        QuoteTotalsBlock(
          summary: s.taxSummary,
          // The approval notice already states the discount.
          discountPct: pending ? '' : s.discountPct,
        )
      else
        Text('Quote total: ${formatMoneyStr(s.raw['total_amount'])}',
            style: AppText.custom(
                size: 13.5,
                weight: FontWeight.w600,
                color: AppColors.textBody)),
    ]);
  }

  Widget _header(String title) {
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
            onTap: () => _savedQuote != null
                ? _finish(_savedQuote!)
                : _closeKeepingDraft(),
            child: Container(
              width: 38.w,
              height: 38.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(11.r),
                border: Border.all(color: const Color(0xFFE6E7EA)),
              ),
              child: Icon(PhosphorIconsBold.caretLeft,
                  size: 17.sp, color: AppColors.textBody),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(
                        size: 19,
                        weight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3)),
                Text('Line items from the catalog or typed',
                    style: AppText.custom(
                        size: 12,
                        weight: FontWeight.w500,
                        color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBar(_View v) {
    Widget bar(List<Widget> children, {Widget? above}) => Container(
          padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 22.h),
          decoration: const BoxDecoration(
            color: AppColors.white,
            border: Border(top: BorderSide(color: AppColors.borderCardSoft)),
          ),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (above != null) ...[above, SizedBox(height: 8.h)],
                Row(children: children),
              ]),
        );

    if (_savedQuote != null) {
      return bar([
        Expanded(
            child: qbSheetButton('Done',
                primary: true, onTap: () => _finish(_savedQuote!)))
      ]);
    }
    if (v.readOnly) {
      return bar([
        Expanded(
            child: qbSheetButton('Close',
                primary: false, onTap: () => context.pop()))
      ]);
    }
    // Say why the button is disabled — otherwise a cleared quantity reads as a
    // dead button.
    final reason =
        v.blockReason.isNotEmpty ? v.blockReason : v.incompleteReason;
    final label = _isEdit
        ? (_saving ? 'Saving…' : 'Save changes')
        : (_saving ? 'Creating…' : 'Create quote');
    return bar(
      above: reason.isEmpty
          ? null
          : Text(reason,
              style: AppText.custom(
                  size: 12.5,
                  weight: FontWeight.w600,
                  color: v.blockReason.isNotEmpty
                      ? AppColors.error
                      : AppColors.textMuted)),
      [
        GestureDetector(
          onTap: _saving ? null : _closeKeepingDraft,
          child: Container(
            width: 100.w,
            height: 48.h,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: const Color(0xFFE6E7EA)),
            ),
            child: Text('Cancel',
                style: AppText.custom(
                    size: 14,
                    weight: FontWeight.w600,
                    color: AppColors.textLabelAlt)),
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: GestureDetector(
            onTap: v.canSubmit ? () => _save(v) : null,
            child: Container(
              height: 48.h,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color:
                      v.canSubmit ? AppColors.navy : AppColors.textPlaceholder,
                  borderRadius: BorderRadius.circular(12.r)),
              child: _saving
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        width: 16.w,
                        height: 16.w,
                        child: const CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.white),
                      ),
                      SizedBox(width: 8.w),
                      Text(label,
                          style: AppText.custom(
                              size: 15,
                              weight: FontWeight.w700,
                              color: AppColors.white)),
                    ])
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(PhosphorIconsBold.check,
                          size: 16.sp, color: AppColors.white),
                      SizedBox(width: 8.w),
                      Text(label,
                          style: AppText.custom(
                              size: 15,
                              weight: FontWeight.w700,
                              color: AppColors.white)),
                    ]),
            ),
          ),
        ),
      ],
    );
  }
}

/// Everything the build derives from the draft + server data, computed once
/// per build.
class _View {
  const _View({
    required this.quote,
    required this.quoteLoading,
    required this.quoteError,
    required this.readOnly,
    required this.leadLocked,
    required this.customerLocked,
    required this.mode,
    required this.templatesLoading,
    required this.templateOptions,
    required this.templateId,
    required this.templateFallback,
    required this.hidden,
    required this.amountsAre,
    required this.taxDefaults,
    required this.recurringEnabled,
    required this.templateFields,
    required this.templateFieldsLoading,
    required this.templateFieldsError,
    required this.layoutConfigured,
    required this.headings,
    required this.sectionsLoading,
    required this.sectionsError,
    required this.sectionPicks,
    required this.missingSections,
    required this.library,
    required this.libraryLoading,
    required this.libraryError,
    required this.clauseRows,
    required this.legacyTerms,
    required this.today,
    required this.catalog,
    required this.catalogLoading,
    required this.spotKey,
    required this.spotAsk,
    required this.valueOf,
    required this.missingTemplateField,
    required this.previewCtx,
    required this.priced,
    required this.livePriced,
    required this.hasPricedLines,
    required this.updating,
    required this.hasRecurringLine,
    required this.writeCtx,
    required this.editPatch,
    required this.canSubmit,
    required this.blockReason,
    required this.incompleteReason,
    this.groupMode = false,
    this.groupLoading = false,
    this.groupError,
    this.groupId = '',
    this.allTabs = const [],
    this.maxOptions = 3,
    this.canChangeSet = true,
    this.sharedPatch,
    this.groupOptionsDiffer = false,
    this.groupPrimaryChanged = false,
    this.primaryQuotationId = '',
    required this.validityInPast,
  });

  final SavedQuote? quote;
  final bool quoteLoading;
  final Object? quoteError;
  final bool readOnly;
  final bool leadLocked;
  final bool customerLocked;
  final QuoteFor mode;
  final bool templatesLoading;
  final List<QuoteTemplateOption> templateOptions;
  final String templateId;
  final bool templateFallback;
  final Set<String> hidden;
  final String amountsAre;
  final QuoteTaxDefaults? taxDefaults;
  final bool recurringEnabled;
  final List<TemplateField> templateFields;
  final bool templateFieldsLoading;
  final String? templateFieldsError;
  final bool layoutConfigured;
  final List<SectionHeading> headings;
  final bool sectionsLoading;
  final String? sectionsError;
  final List<SectionPick> sectionPicks;
  final List<SectionHeading> missingSections;
  final List<LibraryClause> library;
  final bool libraryLoading;
  final String? libraryError;
  final List<ClauseRow> clauseRows;
  final bool legacyTerms;
  final String today;
  final List<Product> catalog;
  final bool catalogLoading;
  final ({
    String templateId,
    String leadId,
    String customerId,
    String quotationId
  }) spotKey;
  final List<SpotInputField> spotAsk;
  final Object Function(TemplateField) valueOf;
  final bool missingTemplateField;
  final PreviewContext previewCtx;
  final Map<String, List<PricedLine>> priced;
  final Map<String, List<PricedLine>> livePriced;
  final bool hasPricedLines;
  final bool updating;
  final bool hasRecurringLine;
  final BuilderWriteContext writeCtx;
  final Map<String, dynamic>? editPatch;
  final bool canSubmit;
  final String blockReason;
  final String incompleteReason;

  // Alternative options (an `options` template / an option of a group).
  final bool groupMode;
  final bool groupLoading;
  final Object? groupError;
  final String groupId;
  final List<OptionTab> allTabs;
  final int maxOptions;
  final bool canChangeSet;
  final Map<String, dynamic>? sharedPatch;
  final bool groupOptionsDiffer;
  final bool groupPrimaryChanged;
  final String primaryQuotationId;
  final bool validityInPast;
}
