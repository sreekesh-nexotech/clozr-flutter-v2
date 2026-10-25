import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/utils/inr_format.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/notes_thread.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/api/roster.dart';
import '../../../../data/api/user_directory.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../accounting/application/providers/accounting_providers.dart';
import '../../../auth/presentation/components/permission_guard.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/audit_log_providers.dart';
import '../../application/providers/crm_module_schema_providers.dart';
import '../../application/providers/crm_notes_providers.dart';
import '../../application/providers/invoices_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../../application/providers/payments_providers.dart';
import '../../application/providers/quote_detail_providers.dart';
import '../../application/providers/quotes_providers.dart';
import '../../application/quote_lifecycle.dart';
import '../../domain/entities/audit_entry.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/quote.dart';
import '../../infrastructure/data_sources/remote/crm_catalog_remote_ds.dart' show hexColor;
import '../../infrastructure/data_sources/remote/quotes_remote_ds.dart';
import '../components/crm_async.dart';
import '../components/finance_widgets.dart';
import '../components/option_picker_sheet.dart';
import '../components/quote_detail/quote_detail_sections.dart';
import '../components/quote_detail/quote_dialogs.dart';
// Discount approval (another agent's component): the banner + gating helpers.
import '../components/quote_discount_approval.dart';
// `confirmDeleteQuote` — the webapp's "Delete this quote?" dialog, shared with the list.
import 'quotes_screen.dart' show confirmDeleteQuote;

final _uuidRe = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

String _str(Object? v) {
  if (v == null) return '';
  final t = '$v'.trim();
  return t == 'null' ? '' : t;
}

/// Quote detail — a port of the webapp's `QuoteDetailScreen`: header with
/// status / lifecycle actions, lock / superseded / 409 conflict banners, the
/// discount-approval banner, related records, quote information with inline
/// edits, line items + GST totals, terms, payment instructions, notes thread
/// and activity.
///
/// `?id=` is the display number (`QTN-00028`, resolved through the list) or
/// the record uuid (revisions, related links).
class QuoteDetailScreen extends ConsumerStatefulWidget {
  const QuoteDetailScreen({super.key});

  @override
  ConsumerState<QuoteDetailScreen> createState() => _QuoteDetailScreenState();
}

class _QuoteDetailScreenState extends ConsumerState<QuoteDetailScreen> {
  /// A 409 lifecycle refusal — the server's detail plus the next step.
  LifecycleConflict? _conflict;

  /// An accounting lock reported by the server on a write.
  QuoteLockKind? _lockKind;
  bool _busy = false;
  bool _pdfBusy = false;

  // ── Load ────────────────────────────────────────────────────────────────

  Widget _scaffold(Widget child, {String? name, Widget? trailing}) => Container(
        color: AppColors.bgDetail,
        child: Column(children: [
          DetailAppBar(section: 'Quote', name: name, onBack: () => context.pop(), trailing: trailing),
          Expanded(child: child),
        ]),
      );

  Widget _notFound() => EmptyState(
        icon: PhosphorIconsRegular.fileText,
        title: 'Quote not found',
        body: 'This quote may have been deleted.',
        ctaLabel: 'Back to Quotes',
        onCta: () {
          ref.invalidate(quotesProvider);
          context.pop();
        },
      );

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    String uuid = '';
    Quote? listQuote;
    if (_uuidRe.hasMatch(id)) {
      uuid = id;
    } else {
      final list = ref.watch(quotesProvider);
      if (list.isLoading && !list.hasValue) return _scaffold(const DetailSkeleton());
      if (list.hasError && !list.hasValue) {
        return _scaffold(ErrorState.forError(crmAppError(list.error!), onRetry: () => ref.invalidate(quotesProvider)));
      }
      listQuote = ref.watch(quoteByIdProvider(id));
      if (listQuote == null) return _scaffold(_notFound());
      uuid = listQuote.uuid;
    }

    Map<String, dynamic>? row;
    if (!ApiConfig.apiEnabled || uuid.isEmpty) {
      // Mock mode: a minimal record from the list entity.
      if (listQuote == null) return _scaffold(_notFound());
      row = {
        'quotation_id': listQuote.uuid,
        'quotation_number': listQuote.id,
        'quotation_title': listQuote.title,
        'status': {'name': listQuote.statusName},
        'valid_until': '',
        'line_items': const [],
      };
    } else {
      final rowAsync = ref.watch(quoteRowProvider(uuid));
      if (rowAsync.isLoading && !rowAsync.hasValue) return _scaffold(const DetailSkeleton());
      row = rowAsync.valueOrNull;
      if (row == null) {
        final err = ref.watch(quoteLoadErrorProvider(uuid));
        if (err.isLoading) return _scaffold(const DetailSkeleton());
        final e = err.valueOrNull;
        if (e == null || e.type == AppErrorType.notFound) return _scaffold(_notFound());
        return _scaffold(EmptyState(
          icon: PhosphorIconsRegular.warning,
          title: 'Couldn’t load this quote',
          body: e.bareMessage,
          ctaLabel: 'Back to Quotes',
          onCta: () => context.pop(),
        ));
      }
    }
    return _buildQuote(uuid, row);
  }

  Future<void> _refresh(String uuid) async {
    ref.invalidate(quotesProvider);
    ref.invalidate(quoteLifecycleStatusesProvider);
    ref.invalidate(crmNotesProvider);
    if (uuid.isNotEmpty) {
      ref.invalidate(quoteRowProvider(uuid));
      ref.invalidate(quoteActivityLogProvider(uuid));
      ref.invalidate(quotePaymentInstructionsProvider(uuid));
      // The approval banner reads the newest request separately; a re-priced
      // quote raises a new one, and without this the banner kept the old
      // (already decided) request — no Approve / Reject for the approver.
      ref.invalidate(quoteLatestDiscountApprovalProvider(uuid));
    }
    ref.invalidate(quoteLatestRevisionProvider);
    await settle([
      ref.read(quoteLifecycleStatusesProvider.future),
      if (uuid.isNotEmpty) ref.read(quoteRowProvider(uuid).future),
    ]);
  }

  /// After any write: the record, the list it was found through, and the plan
  /// side (accepting creates the plan; leaving Accepted deletes it).
  void _afterWrite(String uuid) {
    ref.invalidate(quoteRowProvider(uuid));
    ref.invalidate(quotesProvider);
    ref.invalidate(invoicesProvider);
    ref.invalidate(paymentsProvider);
    ref.invalidate(quoteLatestRevisionProvider);
    ref.invalidate(quotePaymentInstructionsProvider(uuid));
  }

  // ── Errors ──────────────────────────────────────────────────────────────

  /// Webapp `onWriteError`: a lifecycle 409 becomes the warning banner, an
  /// accounting lock the lock banner, anything else a toast without the
  /// `field:` prefix. The shell's generic toast is withdrawn either way.
  void _onWriteError(AppError e, QuoteFacts facts, {bool statusChange = false}) {
    ref.read(apiServiceProvider).handled(e);
    if (!mounted) return;
    final c = lifecycleConflict(e);
    if (c != null) {
      final approvalShown = facts.approvalStatus == 'PENDING' || facts.approvalStatus == 'REJECTED';
      if (!(c.code == 'APPROVAL_PENDING' && approvalShown)) setState(() => _conflict = c);
      return;
    }
    final kind = quoteLockKind(e, wasStatusChange: statusChange, wasAccepted: facts.statusType == 'ACCEPTED' || facts.isConverted);
    if (kind != null) {
      setState(() => _lockKind = kind);
    } else {
      ref.read(toastProvider.notifier).showError(e.bareMessage);
    }
  }

  // ── Writes ──────────────────────────────────────────────────────────────

  Future<bool> _patch(QuoteFacts facts, Map<String, dynamic> body, String success, {bool statusChange = false}) async {
    if (!ensurePermission(ref, 'quotation', PermVerb.update)) return false;
    setState(() => _busy = true);
    try {
      await ref.read(quoteActionsDsProvider).patch(facts.id, body);
    } on AppError catch (e) {
      _onWriteError(e, facts, statusChange: statusChange);
      if (mounted) setState(() => _busy = false);
      return false;
    }
    if (!mounted) return true;
    setState(() {
      _busy = false;
      if (statusChange) _conflict = null;
    });
    _afterWrite(facts.id);
    if (success.isNotEmpty) ref.read(toastProvider.notifier).show(success);
    return true;
  }

  /// Webapp `moveToStatus`: Rejected-type opens the decline dialog,
  /// Accepted-type the accept dialog, anything else moves straight away.
  Future<void> _moveToStatus(QuoteFacts facts, List<QuoteStatusRow> statuses, QuoteStatusRow? target, String success) async {
    if (target == null) {
      ref.read(toastProvider.notifier).showError(kStatusNotConfigured);
      return;
    }
    final legacy = isLegacyStatusList(statuses);
    final type = resolveStatusType(target, legacy);
    if (!legacy && needsDeclineReason(type, facts.statusType)) {
      await _decline(facts, target);
      return;
    }
    if (type == 'ACCEPTED' && facts.statusType != 'ACCEPTED') {
      await _accept(facts, statuses);
      return;
    }
    setState(() => _conflict = null);
    await _patch(facts, {'status_id': target.id}, success, statusChange: true);
  }

  Future<void> _decline(QuoteFacts facts, QuoteStatusRow target) async {
    if (!ensurePermission(ref, 'quotation', PermVerb.update)) return;
    final api = ref.read(apiServiceProvider);
    var conflicted = false;
    final ok = await showDeclineQuoteDialog(
      context,
      quoteLabel: facts.label,
      statusLabel: target.name,
      onSubmit: (d) async {
        try {
          await ref.read(quoteActionsDsProvider).patch(facts.id, {
            'status_id': target.id,
            'decline_reason': d.reasonId,
            if (d.note.isNotEmpty) 'decline_note': d.note,
          });
          return null;
        } on AppError catch (e) {
          api.handled(e);
          final c = lifecycleConflict(e);
          if (c != null) {
            conflicted = true;
            if (mounted) setState(() => _conflict = c);
            return null;
          }
          return e.bareMessage;
        }
      },
    );
    if (!mounted || !ok) return;
    _afterWrite(facts.id);
    if (!conflicted) {
      setState(() => _conflict = null);
      ref.read(toastProvider.notifier).show('Quote marked ${target.name}');
    }
  }

  Future<void> _accept(QuoteFacts facts, List<QuoteStatusRow> statuses) async {
    if (!ensurePermission(ref, 'quotation', PermVerb.update)) return;
    final accepted = findStatusOfType(statuses, 'ACCEPTED');
    if (accepted == null) {
      ref.read(toastProvider.notifier).showError(kStatusNotConfigured);
      return;
    }
    final api = ref.read(apiServiceProvider);
    var current = facts;
    while (mounted) {
      var conflicted = false;
      final result = await showAcceptQuoteDialog(
        context,
        quote: current,
        amountLabel: current.grandTotal == null ? '' : '${quoteMoney(current.grandTotal)} incl. GST',
        onSubmit: (choice) async {
          try {
            await ref.read(quoteActionsDsProvider).patch(current.id, {
              'status_id': accepted.id,
              'accepted_on': choice.acceptedOn,
              if (choice.schedule != null) 'schedule': choice.schedule!.toJson(),
            });
            return null;
          } on AppError catch (e) {
            api.handled(e);
            final c = lifecycleConflict(e);
            if (c != null) {
              conflicted = true;
              if (mounted) setState(() => _conflict = c);
              return null;
            }
            return e.bareMessage;
          }
        },
      );
      if (!mounted) return;
      if (result == 'change') {
        // R5: the builder's payment section (read-only on a sent quote);
        // closing it comes back to the Accept dialog.
        await context.push('${Routes.editQuote}?id=${current.id}&focus=payment');
        if (!mounted) return;
        ref.invalidate(quoteRowProvider(current.id));
        final fresh = await ref.read(quoteRowProvider(current.id).future);
        if (fresh != null) current = QuoteFacts.fromRow(fresh, statuses: statuses);
        continue;
      }
      if (result == 'accepted') {
        _afterWrite(current.id);
        if (!conflicted) {
          setState(() => _conflict = null);
          ref.read(toastProvider.notifier).show('Quote accepted — payment plan created');
        }
      }
      return;
    }
  }

  void _markSent(QuoteFacts facts, QuoteLifecycleActions a, List<QuoteStatusRow> statuses) {
    if (a.sendBlocked) {
      ref.read(toastProvider.notifier).show(a.sendBlockedReason);
      return;
    }
    _moveToStatus(facts, statuses, findStatusOfType(statuses, 'SENT'), 'Quote marked as sent');
  }

  void _tapAccept(QuoteFacts facts, QuoteLifecycleActions a, List<QuoteStatusRow> statuses) {
    if (a.acceptBlocked) {
      ref.read(toastProvider.notifier).show(a.acceptBlockedReason);
      return;
    }
    _accept(facts, statuses);
  }

  void _tapReject(QuoteFacts facts, List<QuoteStatusRow> statuses) {
    if (!ensurePermission(ref, 'quotation', PermVerb.update)) return;
    _moveToStatus(facts, statuses, findStatusOfType(statuses, 'REJECTED'), 'Quote rejected');
  }

  /// Opens a freshly created quote (revision / duplicate / renewal).
  void _open(Map<String, dynamic> created) {
    final id = _str(created['quotation_id']);
    if (id.isEmpty) return;
    context.push('${Routes.quoteDetail}?id=$id');
  }

  Future<void> _revise(QuoteFacts facts) async {
    if (!ensurePermission(ref, 'quotation', PermVerb.update) || !ensurePermission(ref, 'quotation', PermVerb.create)) return;
    if (!await confirmReviseQuote(context, facts.number) || !mounted) return;
    setState(() => _busy = true);
    try {
      final created = await ref.read(quoteActionsDsProvider).revise(facts.id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _conflict = null;
      });
      _afterWrite(facts.id);
      ref.read(toastProvider.notifier).show('Revision ${_str(created['quotation_number'])} created as a draft');
      _open(created);
    } on AppError catch (e) {
      _onWriteError(e, facts);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _duplicate(QuoteFacts facts) async {
    if (!ensurePermission(ref, 'quotation', PermVerb.create)) return;
    setState(() => _busy = true);
    try {
      final created = await ref.read(quoteActionsDsProvider).duplicate(facts.id);
      if (!mounted) return;
      setState(() => _busy = false);
      ref.invalidate(quotesProvider);
      final n = _str(created['quotation_number']);
      ref.read(toastProvider.notifier).show('Duplicated as ${n.isEmpty ? 'a new draft' : n}');
      _open(created);
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      if (mounted) setState(() => _busy = false);
      ref.read(toastProvider.notifier).showError(e.bareMessage);
    }
  }

  Future<void> _renew(QuoteFacts facts) async {
    if (!ensurePermission(ref, 'quotation', PermVerb.update) || !ensurePermission(ref, 'quotation', PermVerb.create)) return;
    final api = ref.read(apiServiceProvider);
    Map<String, dynamic>? created;
    final ok = await showRenewQuoteDialog(context, quoteLabel: facts.label, onSubmit: (validUntil) async {
      try {
        created = await ref.read(quoteActionsDsProvider).renew(facts.id, validUntil);
        return null;
      } on AppError catch (e) {
        api.handled(e);
        final c = lifecycleConflict(e);
        if (c != null) {
          if (mounted) setState(() => _conflict = c);
          return null;
        }
        return e.bareMessage;
      }
    });
    if (!mounted || !ok || created == null) return;
    setState(() => _conflict = null);
    _afterWrite(facts.id);
    final n = _str(created!['quotation_number']);
    ref.read(toastProvider.notifier).show('Renewed as ${n.isEmpty ? 'a new revision' : n} at today’s prices');
    _open(created!);
  }

  Future<void> _delete(QuoteFacts facts) async {
    if (!ensurePermission(ref, 'quotation', PermVerb.delete)) return;
    final reason = deleteBlockedReason(facts);
    if (reason.isNotEmpty) {
      ref.read(toastProvider.notifier).show(reason);
      return;
    }
    if (!await confirmDeleteQuote(context, facts.number) || !mounted) return;
    try {
      await ref.read(quoteActionsDsProvider).delete(facts.id);
    } on AppError catch (e) {
      _onWriteError(e, facts);
      return;
    }
    if (!mounted) return;
    ref.invalidate(quotesProvider);
    ref.invalidate(invoicesProvider);
    ref.read(toastProvider.notifier).show('${facts.number.isEmpty ? 'Quote' : facts.number} deleted');
    context.pop();
  }

  Future<void> _downloadPdf(QuoteFacts facts) async {
    if (!ref.read(quoteCanExportProvider)) {
      ref.read(toastProvider.notifier).showError(kExportDenied);
      return;
    }
    setState(() => _pdfBusy = true);
    final toast = ref.read(toastProvider.notifier);
    try {
      final bytes = await ref.read(quoteActionsDsProvider).pdf(facts.id);
      final dir = await getTemporaryDirectory();
      final name = (facts.number.isEmpty ? facts.id : facts.number).replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final file = File('${dir.path}/$name.pdf');
      await file.writeAsBytes(bytes);
      final result = await OpenFile.open(file.path, type: 'application/pdf');
      if (result.type != ResultType.done) {
        toast.show(result.message.isNotEmpty ? result.message : 'No app on this device can open this file.');
      }
    } on AppError catch (e) {
      ref.read(apiServiceProvider).handled(e);
      toast.showError(e.bareMessage);
    } on Object catch (e) {
      toast.showError('Could not open the PDF: $e');
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  Future<void> _generateDocument(QuoteFacts facts) async {
    if (!ensurePermission(ref, 'quotation', PermVerb.update)) return;
    final api = ref.read(apiServiceProvider);
    final ok = await showGenerateDocumentDialog(context, onSubmit: (v) async {
      try {
        await ref.read(quoteActionsDsProvider).generateDocument(generateDocumentBody(v.template, facts.id, v.values));
        return null;
      } on AppError catch (e) {
        api.handled(e);
        return e.bareMessage;
      }
    });
    if (ok && mounted) ref.read(toastProvider.notifier).show('Document generated');
  }

  Future<void> _reassignOwner(QuoteFacts facts, String ownerId) async {
    if (!ensurePermission(ref, 'quotation', PermVerb.update)) return;
    // The webapp's Reassign owner reads the task picker roster
    // (`assignable-users?module=task`); `module=quotation` is refused (400).
    final users = await ref.read(assignableUsersForModuleProvider('task').future);
    if (!mounted) return;
    final picked = await showOptionPicker(
      context: context,
      title: 'Reassign owner',
      options: users,
      selected: {if (ownerId.isNotEmpty) ownerId},
      emptyNote: 'No users can own quotes here.',
    );
    if (picked == null || picked.isEmpty || picked.first == ownerId || !mounted) return;
    final name = users.where((u) => u.id == picked.first).firstOrNull?.name ?? 'new owner';
    // `owner_id`, not `owner`: the quote serializer treats `owner` as read-only
    // and silently ignores it (200, owner unchanged — verified on dev), which
    // is what the webapp sends. `owner_id` is the writable key.
    await _patch(facts, {'owner_id': picked.first}, 'Owner reassigned to $name');
  }

  // ── Inline edits ────────────────────────────────────────────────────────

  Future<String?> _promptText(String title, String initial, String hint) =>
      showDialog<String>(
        context: context,
        builder: (_) => _TextPromptDialog(title: title, initial: initial, hint: hint),
      );

  Future<void> _editText(QuoteFacts facts, String label, String key, String initial, String hint, String success) async {
    if (!ensurePermission(ref, 'quotation', PermVerb.update)) return;
    final v = await _promptText(label, initial, hint);
    if (v == null || v.trim() == initial.trim() || !mounted) return;
    await _patch(facts, {key: v.trim()}, success);
  }

  Future<void> _editDate(QuoteFacts facts, String key, String current, String success) async {
    if (!ensurePermission(ref, 'quotation', PermVerb.update)) return;
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(current) ?? now,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 5),
    );
    if (d == null || !mounted || isoDayOf(d) == localDayOf(current)) return;
    await _patch(facts, {key: isoDayOf(d)}, success);
  }

  Future<void> _editChoice(QuoteFacts facts, String title, String key, List<CatalogOption> options, String current, String success) async {
    if (!ensurePermission(ref, 'quotation', PermVerb.update)) return;
    final picked = await showOptionPicker(context: context, title: title, options: options, selected: {if (current.isNotEmpty) current});
    if (picked == null || picked.isEmpty || picked.first == current || !mounted) return;
    await _patch(facts, {key: picked.first}, success);
  }

  // ── Build ───────────────────────────────────────────────────────────────

  Widget _buildQuote(String uuid, Map<String, dynamic> row) {
    final statuses = ref.watch(quoteLifecycleStatusesProvider).valueOrNull ?? const <QuoteStatusRow>[];
    final facts = QuoteFacts.fromRow(row, statuses: statuses);
    final a = quoteLifecycleActions(facts);
    final legacy = isLegacyStatusList(statuses);
    final canUpdate = hasPermission(ref, 'quotation', PermVerb.update);
    final canCreate = hasPermission(ref, 'quotation', PermVerb.create);
    final canDelete = hasPermission(ref, 'quotation', PermVerb.delete);
    final canExport = ref.watch(quoteCanExportProvider);
    final readOnly = a.isReadOnly;
    final latest = a.isSuperseded
        ? ref.watch(quoteLatestRevisionProvider('${facts.id}|${facts.number}|${facts.revisionNo}')).valueOrNull
        : null;
    final latestId = latest?.id ?? _conflict?.latestRevisionId ?? '';
    final latestNumber = (latest?.number ?? '').isNotEmpty ? latest!.number : (_conflict?.latestQuotationNumber ?? '');
    final paidLocked = _isPaidLocked(uuid);

    void showReason(String r) => ref.read(toastProvider.notifier).show(r);

    final menu = DetailIconAction(
      icon: PhosphorIconsBold.dotsThreeVertical,
      onTap: () => _openMenu(facts, a, statuses, row, canUpdate: canUpdate, canCreate: canCreate, canDelete: canDelete, canExport: canExport),
    );

    return _scaffold(
      AppRefresh(
        onRefresh: () => _refresh(uuid),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
          children: [
            if (_lockKind != null || paidLocked) ...[
              QuoteNotice(
                icon: PhosphorIconsRegular.lockSimple,
                title: quoteLockCopy[_lockKind ?? QuoteLockKind.paid]!.title,
                text: quoteLockCopy[_lockKind ?? QuoteLockKind.paid]!.body,
                onDismiss: _lockKind == null ? null : () => setState(() => _lockKind = null),
              ),
              SizedBox(height: 14.h),
            ],
            if (a.isSuperseded) ...[
              QuoteNotice(
                icon: PhosphorIconsRegular.clockCounterClockwise,
                tone: AppColors.textMuted,
                bg: AppColors.tintGrey,
                title: 'Superseded.',
                text: 'A newer revision replaced this quote, so it is read-only and can no longer be accepted.',
                actions: [
                  if (latestId.isNotEmpty)
                    ('Open ${latestNumber.isEmpty ? 'latest revision' : latestNumber}',
                        () => context.push('${Routes.quoteDetail}?id=$latestId')),
                ],
              ),
              SizedBox(height: 14.h),
            ],
            if (_conflict != null) ...[
              _conflictBanner(_conflict!, facts, a, statuses, latestId, latestNumber, canUpdate, canCreate),
              SizedBox(height: 14.h),
            ],
            _headerCard(facts, a, statuses, legacy, row, canUpdate),
            // ── Discount approval banner (plan 5.5; component from
            // quote_discount_approval.dart). Renders only for a PENDING /
            // REJECTED approval and carries its own top margin.
            DiscountApprovalBanner(row: row, onChanged: () => _afterWrite(uuid)),
            SizedBox(height: 14.h),
            _relatedCard(facts, row),
            _infoCard(facts, a, row, canUpdate: canUpdate, readOnly: readOnly, onLocked: showReason),
            SizedBox(height: 14.h),
            _lineItemsCard(row),
            QuoteTermsCard(row: row),
            if (_str(row['notes']).isNotEmpty) ...[
              SizedBox(height: 14.h),
              FinanceCard(
                title: 'Notes on the quote',
                child: Text(_str(row['notes']),
                    style: AppText.custom(size: 14, weight: FontWeight.w500, color: AppColors.textLabelAlt, height: 1.6)),
              ),
            ],
            SizedBox(height: 14.h),
            QuotePaymentInstructionsCard(quotationId: uuid, canConfigure: hasPermission(ref, 'settings', PermVerb.update)),
            SizedBox(height: 14.h),
            _notesThread(uuid, readOnly),
            SizedBox(height: 14.h),
            _activityCard(uuid, row),
          ],
        ),
      ),
      name: facts.number.isEmpty ? facts.title : facts.number,
      trailing: menu,
    );
  }

  /// A payment is recorded, or a tax invoice is linked, against this
  /// quote's plan (handover §9.3) — the webapp's "This quote is locked."
  bool _isPaidLocked(String uuid) {
    if (uuid.isEmpty) return false;
    final invoices = ref.watch(invoicesProvider).valueOrNull ?? const [];
    final plan = invoices.where((i) => i.quoteUuid == uuid).firstOrNull;
    if (plan == null) return false;
    return ref.watch(paymentsForInvoiceProvider(plan.id)).any((p) => p.status == 'paid' || p.linkedDocumentId != null);
  }

  Widget _conflictBanner(LifecycleConflict c, QuoteFacts facts, QuoteLifecycleActions a, List<QuoteStatusRow> statuses,
      String latestId, String latestNumber, bool canUpdate, bool canCreate) {
    final actions = <(String, VoidCallback)>[
      if (c.next == 'REVISE' && a.canRevise && canUpdate && canCreate) ('Revise', () => _revise(facts)),
      if (c.next == 'RENEW' && canUpdate && canCreate) ('Renew', () => _renew(facts)),
      if (c.next == 'MARK_SENT' && a.canMarkSent && !a.sendBlocked && canUpdate)
        ('Mark as sent', () => _markSent(facts, a, statuses)),
      if (c.next == 'OPEN_ACCEPTED_QUOTE' && c.acceptedQuotationId.isNotEmpty)
        ('Open ${c.acceptedQuotationNumber.isEmpty ? 'accepted quote' : c.acceptedQuotationNumber}',
            () => context.push('${Routes.quoteDetail}?id=${c.acceptedQuotationId}')),
      if (c.next == 'OPEN_LATEST_REVISION' && latestId.isNotEmpty)
        ('Open ${latestNumber.isEmpty ? 'latest revision' : latestNumber}', () => context.push('${Routes.quoteDetail}?id=$latestId')),
    ];
    return QuoteNotice(
      icon: c.code == 'APPROVAL_PENDING' ? PhosphorIconsRegular.hourglassMedium : PhosphorIconsRegular.lockSimple,
      text: c.message,
      actions: actions,
      onDismiss: () => setState(() => _conflict = null),
    );
  }

  Future<void> _openStatusPicker(QuoteFacts facts, QuoteLifecycleActions a, List<QuoteStatusRow> statuses, bool legacy) async {
    if (a.isReadOnly) return;
    if (!ensurePermission(ref, 'quotation', PermVerb.update)) return;
    if (statuses.isEmpty) {
      ref.read(toastProvider.notifier).showError(kStatusNotConfigured);
      return;
    }
    final pickable = pickableStatuses(statuses, facts.statusId, wasSent: a.wasSent);
    final acceptBlocked = a.acceptBlocked || facts.acceptanceBlock != null && !canBackdateAcceptance(facts.acceptanceBlock);
    final chosen = await showQuoteStatusPicker(
      context,
      currentId: facts.statusId,
      options: [
        for (final s in pickable)
          QuoteStatusChoice(
            id: s.id,
            name: s.name,
            color: hexColor(s.color) ?? AppColors.textMuted,
            disabledReason: s.id != facts.statusId && resolveStatusType(s, legacy) == 'ACCEPTED' && acceptBlocked
                ? (a.acceptBlockedReason.isNotEmpty ? a.acceptBlockedReason : facts.acceptanceBlock?.message)
                : null,
          ),
      ],
    );
    if (chosen == null || chosen == facts.statusId || !mounted) return;
    final target = statuses.where((s) => s.id == chosen).firstOrNull;
    await _moveToStatus(facts, statuses, target, target == null ? '' : 'Status set to ${target.name}');
  }

  Widget _headerCard(QuoteFacts facts, QuoteLifecycleActions a, List<QuoteStatusRow> statuses, bool legacy,
      Map<String, dynamic> row, bool canUpdate) {
    final current = statuses.where((s) => s.id == facts.statusId).firstOrNull;
    final statusName = facts.statusName.isNotEmpty ? facts.statusName : (current?.name ?? 'Status');
    final statusColor = hexColor((row['status'] is Map ? (row['status'] as Map)['color'] : null) ?? current?.color) ?? AppColors.textMuted;
    final meta = StatusMeta(statusName, statusColor);
    final title = facts.title.isNotEmpty
        ? facts.title
        : (_str(row['customer_name']).isNotEmpty ? _str(row['customer_name']) : _str(row['lead_name']));
    final issued = fmtQuoteDate(_str(row['created_at']));
    final valid = fmtQuoteDate(facts.validUntil);
    final chip = approvalChipLabel(row);
    final grand = _str(row['grand_total']);
    final estimate = row['tax_summary'] is Map && (row['tax_summary'] as Map)['is_estimate'] == true && parseMoneyNonZero(row['tax_total']);

    // The primary action: Mark as sent on a draft, Accept on a sent quote.
    final primary = a.canMarkSent
        ? (label: 'Mark as sent', icon: PhosphorIconsBold.paperPlaneTilt, blocked: a.sendBlocked || !canUpdate,
            reason: a.sendBlocked ? a.sendBlockedReason : '', onTap: () => _markSent(facts, a, statuses))
        : a.canAccept
            ? (label: 'Accept quote', icon: PhosphorIconsBold.check, blocked: a.acceptBlocked || !canUpdate,
                reason: a.acceptBlockedReason, onTap: () => _tapAccept(facts, a, statuses))
            : null;

    return FinanceCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const IconChip(icon: PhosphorIconsRegular.fileText, size: 46, radius: 13, iconSize: 22),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8.w, runSpacing: 5.h, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(facts.number.isEmpty ? (facts.title.isEmpty ? 'Quote' : facts.title) : facts.number,
                    style: AppText.custom(size: 19, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                StatusPill.meta(meta),
                if (facts.revisionNo > 0) QuoteHeadChip('REVISION ${facts.revisionNo}'),
                if (facts.isLocked && !a.isSuperseded)
                  const QuoteHeadChip('LOCKED', icon: PhosphorIconsBold.lock, color: AppColors.textSecondary, bg: AppColors.tintGrey),
                if (chip != null)
                  QuoteHeadChip(chip,
                      color: chip == 'APPROVED' ? AppColors.success : (chip == 'PENDING APPROVAL' ? AppColors.warningDeep : AppColors.error),
                      bg: chip == 'APPROVED' ? AppColors.tintGreen : (chip == 'PENDING APPROVAL' ? AppColors.tintAmber : AppColors.tintRed)),
              ]),
              if (title.isNotEmpty) ...[
                SizedBox(height: 4.h),
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textMuted)),
              ],
              SizedBox(height: 4.h),
              Text('Issued ${issued.isEmpty ? '—' : issued} · Quote valid until ${valid.isEmpty ? '—' : valid}',
                  style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
              if (facts.revisionOf.isNotEmpty) ...[
                SizedBox(height: 6.h),
                GestureDetector(
                  onTap: () => context.push('${Routes.quoteDetail}?id=${facts.revisionOf}'),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Previous revision', style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.blueBright)),
                    SizedBox(width: 3.w),
                    Icon(PhosphorIconsBold.arrowUpRight, size: 12.sp, color: AppColors.blueBright),
                  ]),
                ),
              ],
            ]),
          ),
        ]),
        if (grand.isNotEmpty) ...[
          SizedBox(height: 12.h),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text('GRAND TOTAL',
                style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.4)),
            const Spacer(),
            Text(quoteMoney(grand), style: AppText.custom(size: 20, weight: FontWeight.w800, color: AppColors.navy, letterSpacing: -0.4)),
          ]),
          if (estimate)
            Align(alignment: Alignment.centerRight, child: Text('incl. GST (estimate)', style: AppText.caption())),
        ],
        const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 15)),
        Row(children: [
          Expanded(
            flex: 10,
            child: Opacity(
              opacity: a.isReadOnly ? 0.5 : 1,
              child: GestureDetector(
                onTap: _busy ? null : () => _openStatusPicker(facts, a, statuses, legacy),
                child: Container(
                  height: 44.h,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(11.r),
                    border: Border.all(color: const Color(0xFFE6E7EA)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8.w, height: 8.w, decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle)),
                    SizedBox(width: 8.w),
                    Flexible(
                      child: Text(meta.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textBody)),
                    ),
                    SizedBox(width: 6.w),
                    Icon(PhosphorIconsBold.caretDown, size: 11.sp, color: AppColors.textMuted2),
                  ]),
                ),
              ),
            ),
          ),
          if (primary != null) ...[
            SizedBox(width: 10.w),
            Expanded(
              flex: 14,
              child: Opacity(
                opacity: primary.blocked ? 0.45 : 1,
                child: GestureDetector(
                  onTap: _busy
                      ? null
                      : () {
                          if (!canUpdate) {
                            ensurePermission(ref, 'quotation', PermVerb.update);
                            return;
                          }
                          primary.onTap();
                        },
                  child: Container(
                    height: 44.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(11.r)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(primary.icon, size: 15.sp, color: AppColors.white),
                      SizedBox(width: 7.w),
                      Flexible(
                        child: Text(primary.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.white)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ],
          if (a.canReject) ...[
            SizedBox(width: 10.w),
            GestureDetector(
              onTap: _busy ? null : () => _tapReject(facts, statuses),
              child: Container(
                width: 44.w,
                height: 44.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(11.r),
                  border: Border.all(color: const Color(0xFFF3C1C1), width: 1.5),
                ),
                child: Icon(PhosphorIconsBold.x, size: 16.sp, color: AppColors.error),
              ),
            ),
          ],
        ]),
        if (primary != null && primary.blocked && primary.reason.isNotEmpty) ...[
          SizedBox(height: 8.h),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(PhosphorIconsRegular.info, size: 13.sp, color: AppColors.textMuted),
            SizedBox(width: 6.w),
            Expanded(child: Text(primary.reason, style: AppText.caption())),
          ]),
        ],
      ]),
    );
  }

  static bool parseMoneyNonZero(Object? v) => (double.tryParse(_str(v)) ?? 0).abs() >= 0.005;

  void _openMenu(QuoteFacts facts, QuoteLifecycleActions a, List<QuoteStatusRow> statuses, Map<String, dynamic> row,
      {required bool canUpdate, required bool canCreate, required bool canDelete, required bool canExport}) {
    String? perm(bool ok, PermVerb v) => ok ? null : permissionCopy(v);
    final deleteReason = deleteBlockedReason(facts);
    final ownerId = row['owner'] is Map ? _str((row['owner'] as Map)['user_id']) : _str(row['owner']);
    showActionMenu(context, actions: [
      if (!a.isSuperseded)
        MenuAction(
          icon: PhosphorIconsRegular.pencilSimple,
          label: 'Edit quote',
          enabled: canUpdate,
          sublabel: facts.isLocked && canUpdate
              ? 'Sent quotes are locked — prices, lines and terms change through Revise'
              : perm(canUpdate, PermVerb.update),
          onTap: () async {
            final r = await context.push<Object?>(
                '${Routes.editQuote}?id=${facts.id}${a.canRevise ? '&revise=1' : ''}');
            if (r == 'revise' && mounted) await _revise(facts);
          },
        ),
      if (a.canMarkSent)
        MenuAction(
          icon: PhosphorIconsRegular.paperPlaneTilt,
          label: 'Mark as sent',
          enabled: canUpdate && !a.sendBlocked,
          sublabel: a.sendBlocked ? a.sendBlockedReason : perm(canUpdate, PermVerb.update),
          onTap: () => _markSent(facts, a, statuses),
        ),
      if (a.canAccept)
        MenuAction(
          icon: PhosphorIconsRegular.checkCircle,
          label: 'Accept quote',
          enabled: canUpdate && !a.acceptBlocked,
          sublabel: a.acceptBlocked ? a.acceptBlockedReason : perm(canUpdate, PermVerb.update),
          onTap: () => _tapAccept(facts, a, statuses),
        ),
      if (a.canReject)
        MenuAction(
          icon: PhosphorIconsRegular.xCircle,
          label: 'Reject',
          enabled: canUpdate,
          sublabel: perm(canUpdate, PermVerb.update),
          onTap: () => _tapReject(facts, statuses),
        ),
      if (a.canRevise)
        MenuAction(
          icon: PhosphorIconsRegular.gitBranch,
          label: 'Revise',
          enabled: canUpdate && canCreate,
          sublabel: perm(canUpdate && canCreate, PermVerb.update),
          onTap: () => _revise(facts),
        ),
      if (!a.isSuperseded)
        MenuAction(
          icon: PhosphorIconsRegular.copy,
          label: 'Duplicate',
          enabled: canCreate,
          sublabel: perm(canCreate, PermVerb.update),
          onTap: () => _duplicate(facts),
        ),
      if (a.canRenew)
        MenuAction(
          icon: PhosphorIconsRegular.arrowsClockwise,
          label: 'Renew',
          enabled: canUpdate && canCreate,
          sublabel: perm(canUpdate && canCreate, PermVerb.update),
          onTap: () => _renew(facts),
        ),
      MenuAction(
        icon: PhosphorIconsRegular.downloadSimple,
        label: _pdfBusy ? 'Preparing…' : 'Download PDF',
        enabled: canExport && !_pdfBusy,
        sublabel: canExport ? null : kExportDenied,
        onTap: () => _downloadPdf(facts),
      ),
      if (!a.isSuperseded)
        MenuAction(
          icon: PhosphorIconsRegular.filePlus,
          label: 'Generate document',
          enabled: canUpdate,
          sublabel: perm(canUpdate, PermVerb.update),
          onTap: () => _generateDocument(facts),
        ),
      if (!a.isReadOnly)
        MenuAction(
          icon: PhosphorIconsRegular.userSwitch,
          label: 'Reassign owner',
          enabled: canUpdate,
          sublabel: perm(canUpdate, PermVerb.update),
          onTap: () => _reassignOwner(facts, ownerId),
        ),
      MenuAction(
        icon: PhosphorIconsRegular.trash,
        label: 'Delete quote',
        destructive: true,
        enabled: canDelete && deleteReason.isEmpty,
        sublabel: deleteReason.isNotEmpty ? deleteReason : perm(canDelete, PermVerb.delete),
        onTap: () => _delete(facts),
      ),
    ]);
  }

  Widget _relatedCard(QuoteFacts facts, Map<String, dynamic> row) {
    final leadId = _str(row['lead']);
    final custId = _str(row['customer']);
    final leadRef = leadId.isEmpty ? '' : ref.watch(quoteLeadReferenceProvider(leadId)).valueOrNull ?? '';
    final custRef = custId.isEmpty ? '' : ref.watch(quoteCustomerReferenceProvider(custId)).valueOrNull ?? '';
    final invoices = ref.watch(invoicesProvider).valueOrNull ?? const [];
    final plan = facts.id.isEmpty ? null : invoices.where((i) => i.quoteUuid == facts.id).firstOrNull;
    final items = <(IconData, String, String, String?)>[
      if (leadId.isNotEmpty)
        (PhosphorIconsRegular.user, _str(row['lead_name']).isEmpty ? 'Lead' : _str(row['lead_name']),
            leadRef.isEmpty ? 'Lead' : 'Lead · $leadRef', '${Routes.leadDetail}?id=$leadId'),
      if (custId.isNotEmpty)
        (PhosphorIconsRegular.buildings, _str(row['customer_name']).isEmpty ? 'Customer' : _str(row['customer_name']),
            custRef.isEmpty ? 'Customer' : 'Customer · $custRef', '${Routes.customerDetail}?id=$custId'),
      if (facts.paymentPlanId.isNotEmpty)
        (PhosphorIconsRegular.scroll, facts.number.isEmpty ? 'Payment plan' : 'Plan for ${facts.number}', 'Payment plan',
            plan == null ? null : '${Routes.invoiceDetail}?id=${plan.id}'),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: 14.h),
      child: ClozrCard(
        radius: 18,
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: EdgeInsets.only(top: 7.h, bottom: 2.h),
            child: Text('RELATED',
                style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.5)),
          ),
          for (var i = 0; i < items.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: items[i].$4 == null ? null : () => context.push(items[i].$4!),
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 9.h),
                decoration: i == items.length - 1
                    ? null
                    : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
                child: Row(children: [
                  IconChip(icon: items[i].$1, size: 38, radius: 11, iconSize: 18),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(items[i].$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                      SizedBox(height: 1.h),
                      Text(items[i].$3, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
                    ]),
                  ),
                  if (items[i].$4 != null) Icon(PhosphorIconsBold.caretRight, size: 15.sp, color: AppColors.textPlaceholder),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _infoCard(QuoteFacts facts, QuoteLifecycleActions a, Map<String, dynamic> row,
      {required bool canUpdate, required bool readOnly, required void Function(String) onLocked}) {
    final editable = canUpdate && !readOnly;
    final moneyLocked = facts.isLocked || readOnly;
    const lockedCopy = 'Sent quotes are locked — prices, lines and terms change through Revise';
    final stateName = ref.watch(gstStateNameProvider);
    final states = ref.watch(gstStatesProvider).valueOrNull ?? const [];
    final pos = _str(row['place_of_supply_state_code']);
    final amountsAre = _str(row['amounts_are']).toUpperCase();
    final ownerName = row['owner'] is Map
        ? (_str((row['owner'] as Map)['full_name']).isNotEmpty
            ? _str((row['owner'] as Map)['full_name'])
            : _str((row['owner'] as Map)['email']))
        : '';
    final ownerId = row['owner'] is Map ? _str((row['owner'] as Map)['user_id']) : _str(row['owner']);
    final discount = _str(row['discount_pct']);
    final showDiscount = (double.tryParse(discount) ?? 0) > 0 || facts.approvalStatus != 'NOT_REQUIRED';
    final chip = approvalChipLabel(row);
    final declineName = _str(row['decline_reason_name']);
    final declineNote = _str(row['decline_note']);

    final rows = <QuoteInfoRow>[
      QuoteInfoRow(
        label: 'Quote title',
        value: facts.title.isEmpty ? '—' : facts.title,
        onTap: editable
            ? () => _editText(facts, 'Quote title', 'quotation_title', facts.title, 'e.g. CRM Annual Plan – ABC Corp', 'Quote title updated')
            : null,
      ),
      QuoteInfoRow(label: 'Template', value: _str(row['template_name']).isEmpty ? 'Standard' : _str(row['template_name'])),
      QuoteInfoRow(label: 'Payment type', value: facts.paymentType.isEmpty ? 'Lump sum' : planTypeLabel(facts.paymentType)),
      QuoteInfoRow(label: 'Currency', value: _str(row['currency']).isEmpty ? 'INR' : _str(row['currency'])),
      QuoteInfoRow(label: 'Lead', value: _str(row['lead_name']).isEmpty ? '—' : _str(row['lead_name'])),
      QuoteInfoRow(label: 'Customer', value: _str(row['customer_name']).isEmpty ? '—' : _str(row['customer_name'])),
      QuoteInfoRow(label: 'Issued', value: fmtQuoteDate(_str(row['created_at'])).isEmpty ? '—' : fmtQuoteDate(_str(row['created_at']))),
      QuoteInfoRow(
        label: 'Quote valid until',
        value: fmtQuoteDate(facts.validUntil).isEmpty ? '—' : fmtQuoteDate(facts.validUntil),
        onTap: editable ? () => _editDate(facts, 'valid_until', facts.validUntil, 'Valid until updated') : null,
      ),
      QuoteInfoRow(
        label: 'Due date',
        value: fmtQuoteDate(facts.dueDate).isEmpty ? '—' : fmtQuoteDate(facts.dueDate),
        onTap: editable ? () => _editDate(facts, 'due_date', facts.dueDate, 'Due date updated') : null,
      ),
      if (facts.revisionNo > 0)
        QuoteInfoRow(
          label: 'Revision',
          value: 'R${facts.revisionNo}',
          trailing: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text('R${facts.revisionNo}', style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
            if (facts.revisionOf.isNotEmpty) ...[
              SizedBox(width: 8.w),
              GestureDetector(
                onTap: () => context.push('${Routes.quoteDetail}?id=${facts.revisionOf}'),
                child: Text('Previous revision', style: AppText.custom(size: 12.5, weight: FontWeight.w700, color: AppColors.blueBright)),
              ),
            ],
          ]),
        ),
      if (showDiscount)
        QuoteInfoRow(
          label: 'Discount',
          value: pctLabel(discount),
          trailing: Wrap(alignment: WrapAlignment.end, spacing: 6.w, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(pctLabel(discount), style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
            if (chip != null)
              QuoteHeadChip(chip,
                  color: chip == 'APPROVED' ? AppColors.success : (chip == 'PENDING APPROVAL' ? AppColors.warningDeep : AppColors.error),
                  bg: chip == 'APPROVED' ? AppColors.tintGreen : (chip == 'PENDING APPROVAL' ? AppColors.tintAmber : AppColors.tintRed)),
          ]),
        ),
      if (_str(row['accepted_on']).isNotEmpty) QuoteInfoRow(label: 'Accepted on', value: fmtQuoteDate(_str(row['accepted_on']))),
      if (declineName.isNotEmpty)
        QuoteInfoRow(label: 'Decline reason', value: declineNote.isEmpty ? declineName : '$declineName — $declineNote'),
      QuoteInfoRow(
        label: 'Amounts are',
        value: amountsAre.isEmpty ? '—' : amountsAreLabel(amountsAre),
        lockedReason: moneyLocked && !readOnly ? lockedCopy : null,
        onLocked: onLocked,
        onTap: editable && !moneyLocked
            ? () => _editChoice(
                facts,
                'Amounts are',
                'amounts_are',
                const [CatalogOption(id: 'EXCLUSIVE', name: 'Tax exclusive'), CatalogOption(id: 'INCLUSIVE', name: 'Tax inclusive')],
                amountsAre,
                'Tax treatment updated')
            : null,
      ),
      QuoteInfoRow(
        label: 'Place of supply',
        value: pos.isEmpty ? '—' : stateName(pos),
        lockedReason: moneyLocked && !readOnly ? lockedCopy : null,
        onLocked: onLocked,
        onTap: editable && !moneyLocked
            ? () => _editChoice(facts, 'Place of supply', 'place_of_supply_state_code',
                [for (final s in states) CatalogOption(id: s.code, name: '${s.name} (${s.code})')], pos, 'Place of supply updated')
            : null,
      ),
      QuoteInfoRow(
        label: 'Contract reference',
        value: _str(row['contract_ref']).isEmpty ? '—' : _str(row['contract_ref']),
        last: true,
        onTap: editable
            ? () => _editText(facts, 'Contract reference', 'contract_ref', _str(row['contract_ref']), 'e.g. MSA-2026-014',
                'Contract reference updated')
            : null,
      ),
    ];

    final initials = ownerName.trim().isEmpty
        ? '?'
        : ownerName.trim().split(RegExp(r'\s+')).take(2).map((p) => p[0].toUpperCase()).join();
    return FinanceCard(
      title: 'Quote information',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ...rows,
        const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 13)),
        Row(children: [
          Container(
            width: 38.w,
            height: 38.w,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
            child: Text(initials, style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.white)),
          ),
          SizedBox(width: 11.w),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ownerName.isEmpty ? 'Unassigned' : ownerName,
                  style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
              Text('Quote owner', style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
            ]),
          ),
          if (!readOnly)
            GestureDetector(
              onTap: () => _reassignOwner(facts, ownerId),
              child: Container(
                width: 34.w,
                height: 34.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(9.r),
                  border: Border.all(color: AppColors.borderInput),
                ),
                child: Icon(PhosphorIconsRegular.repeat, size: 15.sp, color: AppColors.navy),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _totalRow(String label, String value, {bool strong = false}) => Padding(
        padding: EdgeInsets.symmetric(vertical: 3.h),
        child: Row(children: [
          Text(label,
              style: AppText.custom(
                  size: strong ? 13 : 12.5, weight: strong ? FontWeight.w700 : FontWeight.w500, color: AppColors.textMuted)),
          const Spacer(),
          Text(value,
              style: AppText.custom(
                  size: strong ? 18 : 13.5, weight: FontWeight.w800, color: strong ? AppColors.navy : AppColors.textPrimary)),
        ]),
      );

  Widget _lineItemsCard(Map<String, dynamic> row) {
    final items = quoteFromApi(row)?.items ?? const <QuoteItem>[];
    final ts = row['tax_summary'] is Map ? Map<String, dynamic>.from(row['tax_summary'] as Map) : null;
    bool nz(Object? v) => parseMoneyNonZero(v);
    final grand = _str(ts?['grand_total']).isNotEmpty ? ts!['grand_total'] : row['grand_total'];
    final taxable = _str(ts?['taxable_total']).isNotEmpty ? ts!['taxable_total'] : row['taxable_total'];
    final taxTotal = _str(ts?['tax_total']).isNotEmpty ? ts!['tax_total'] : row['tax_total'];
    final estimate = ts?['is_estimate'] == true && nz(taxTotal);
    final warnings = [
      for (final w in (ts?['warnings'] is List ? ts!['warnings'] as List : const []))
        if (w is Map && _str(w['message']).isNotEmpty) _str(w['message']),
    ];
    String pct(String? raw) {
      final v = double.tryParse(raw ?? '');
      if (v == null) return raw ?? '';
      return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    }

    return FinanceCard(
      title: 'Line items',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (items.isEmpty) Padding(padding: EdgeInsets.symmetric(vertical: 8.h), child: Text('No line items yet.', style: AppText.caption())),
        for (final it in items)
          Container(
            padding: EdgeInsets.symmetric(vertical: 11.h),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(it.name, style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textPrimary)),
                  SizedBox(height: 2.h),
                  Text(
                      'Qty ${formatQty(it.qty)} · ${it.rate}'
                      '${it.discount > 0 ? " · -${quoteMoney(it.discount)} off" : ""}'
                      '${it.hsn == null || it.hsn!.isEmpty ? "" : " · HSN ${it.hsn}"}'
                      '${it.ratePct == null ? "" : " · GST ${pct(it.ratePct)}%"}',
                      style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                ]),
              ),
              SizedBox(width: 14.w),
              Text(it.amt, style: AppText.custom(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
            ]),
          ),
        SizedBox(height: 10.h),
        if (_str(grand).isNotEmpty) ...[
          _totalRow('Taxable value', quoteMoney(taxable)),
          if (ts != null) ...[
            if (nz(ts['cgst'])) _totalRow('CGST', quoteMoney(ts['cgst'])),
            if (nz(ts['sgst'])) _totalRow('SGST', quoteMoney(ts['sgst'])),
            if (nz(ts['igst'])) _totalRow('IGST', quoteMoney(ts['igst'])),
            if (nz(ts['cess'])) _totalRow('Cess', quoteMoney(ts['cess'])),
            if (nz(ts['round_off'])) _totalRow('Round off', quoteMoney(ts['round_off'])),
          ] else
            _totalRow('Tax', quoteMoney(taxTotal)),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 8)),
          _totalRow('Grand total', quoteMoney(grand), strong: true),
          if (estimate) ...[
            SizedBox(height: 6.h),
            Text(
                'GST shown is an estimate — the tax invoice issued at billing is the final figure.'
                '${warnings.isEmpty ? '' : ' ${warnings.join(' ')}'}',
                style: AppText.caption()),
          ],
        ] else
          _totalRow('Total', quoteMoney(row['total_amount']), strong: true),
      ]),
    );
  }

  /// The shared notes thread (reply / pin / edit / delete), model `quotation`.
  Widget _notesThread(String uuid, bool readOnly) {
    final seed = CrmNotesSeed(uuid.isEmpty ? 'QUOTE-local' : uuid, () => const [], apiModel: uuid.isEmpty ? null : 'quotation');
    final notes = ref.watch(crmNotesProvider(seed));
    final notifier = ref.read(crmNotesProvider(seed).notifier);
    return NotesThread(
      author: ref.watch(noteAuthorProvider),
      notes: notes,
      onAddNote: (body, atts) => notifier.addNote(body, atts, ref.read(noteAuthorProvider)),
      onAddReply: (noteId, body) => notifier.addReply(noteId, body, ref.read(noteAuthorProvider)),
      webappToolbar: true,
      noteTypes: ref.watch(noteTypesProvider).valueOrNull ?? const [],
      mentionables: [
        for (final u in ref.watch(assignableUsersForModuleProvider('task')).valueOrNull ?? const <CatalogOption>[])
          (id: UserDirectory.realUserId(u.id) ?? u.id, name: u.name),
      ],
      currentUserId: UserDirectory.currentUserId,
      readOnly: readOnly,
      onAddTypedNote: (body, atts, typeId, typeName, mentions) => notifier.addNote(body, atts, ref.read(noteAuthorProvider),
          noteTypeId: typeId, noteTypeName: typeName, mentionedUserIds: mentions, authorId: UserDirectory.currentUserId),
      onTogglePin: notifier.togglePin,
      onEditNote: (id, body) => notifier.editNote(id, body),
      onDeleteNote: notifier.deleteNote,
    );
  }

  /// "Activity" — the record's audit trail (`model_name=Quotation`), with a
  /// derived fallback when it is unavailable.
  Widget _activityCard(String uuid, Map<String, dynamic> row) {
    final entries = uuid.isEmpty ? const <AuditEntry>[] : ref.watch(quoteActivityLogProvider(uuid)).valueOrNull ?? const [];
    final owner = row['owner'] is Map ? _str((row['owner'] as Map)['full_name']) : '';
    final rows = entries.isEmpty
        ? [
            ActivityEntry(
              icon: PhosphorIconsRegular.fileText,
              tone: AppColors.blueBright,
              bg: AppColors.tintBlue,
              title: 'Quote created',
              sub: [fmtQuoteDate(_str(row['created_at'])), owner].where((s) => s.isNotEmpty).join(' · '),
            ),
          ]
        : [for (final e in entries) _auditRow(e)];
    return FinanceCard(
      title: 'Activity',
      child: Padding(padding: EdgeInsets.only(top: 6.h), child: ActivityTimeline(entries: rows)),
    );
  }

  ActivityEntry _auditRow(AuditEntry e) {
    final (icon, tone, bg) = switch (e.kind) {
      AuditEventKind.created => (PhosphorIconsRegular.fileText, AppColors.blueBright, AppColors.tintBlue),
      AuditEventKind.statusChanged => (PhosphorIconsRegular.arrowsClockwise, AppColors.warning, AppColors.tintAmber),
      AuditEventKind.noteAdded => (PhosphorIconsRegular.note, AppColors.pending, AppColors.tintPurple),
      AuditEventKind.childAdded => (PhosphorIconsRegular.plusCircle, AppColors.success, AppColors.tintGreen),
      AuditEventKind.deleted => (PhosphorIconsRegular.trash, AppColors.error, AppColors.tintRed),
      _ => (PhosphorIconsRegular.pencilSimple, AppColors.blueBright, AppColors.tintBlue),
    };
    final when = e.at == null ? '' : relativeTime(e.at);
    final sub = [e.subtitle, e.actor, when].where((s) => s.isNotEmpty).join(' · ');
    return ActivityEntry(icon: icon, tone: tone, bg: bg, title: e.title, sub: sub);
  }
}

/// A one-field edit prompt. Owns its controller so it lives exactly as long as
/// the dialog — disposing it right after `showDialog` returned tore it down
/// while the closing animation still rebuilt the field, which crashed the
/// screen ("Something went wrong on this screen").
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({required this.title, required this.initial, required this.hint});

  final String title;
  final String initial;
  final String hint;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: widget.hint, border: const OutlineInputBorder()),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(_ctrl.text), child: const Text('Save')),
        ],
      );
}
