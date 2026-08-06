import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../data/api/roster.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/models/note.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/notes_thread.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/attachments_providers.dart';
import '../../application/providers/call_logs_providers.dart';
import '../../application/providers/crm_catalog_providers.dart';
import '../../application/providers/lead_call_providers.dart';
import '../../application/providers/crm_notes_providers.dart';
import '../../application/providers/crm_tasks_providers.dart';
import '../../../../core/utils/relative_time.dart';
import '../../application/leads_columns.dart';
import '../../application/providers/audit_log_providers.dart';
import '../../application/providers/followups_providers.dart';
import '../../application/providers/lead_schema_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../../application/providers/quotes_providers.dart';
import '../../domain/entities/call_log.dart';
import '../../domain/entities/crm_catalog.dart';
import '../../domain/entities/crm_task.dart';
import '../../domain/entities/followup.dart';
import '../../domain/entities/audit_entry.dart';
import '../../domain/entities/lead.dart';
import '../../domain/entities/lead_file.dart';
import '../../domain/entities/quote.dart';
import '../components/crm_async.dart';
import '../components/crm_check_box.dart';
import '../components/crm_detail_parts.dart';
import '../sheets/add_followup_sheet.dart';
import '../sheets/add_task_sheet.dart';
import '../sheets/log_call_sheet.dart';
import 'crm_status_sheet.dart';

/// Lead detail — profile card, lead-score/AI card, information card with
/// owner & assignees, a tabbed activity card (Tasks / Call log / Follow-ups /
/// Quotes / Files), notes and an activity log, over a sticky call CTA bar.
class LeadDetailScreen extends ConsumerStatefulWidget {
  const LeadDetailScreen({super.key});

  @override
  ConsumerState<LeadDetailScreen> createState() => _LeadDetailScreenState();
}

class _LeadDetailScreenState extends ConsumerState<LeadDetailScreen> {
  int _tab = 0;
  bool _infoMore = false;
  bool _scoreInfo = false;

  /// True while a file upload is in flight, so the CTA can report progress and
  /// refuse a second batch on top of the first.
  bool _uploading = false;
  final _notesKey = GlobalKey<NotesThreadState>();

  static const _tabLabels = ['Tasks', 'Call log', 'Follow-ups', 'Quotes', 'Files'];

  /// Information rows shown before "Show more". An org with a long detail
  /// layout collapses to this; a shorter one shows every row and drops the
  /// toggle entirely.
  static const _infoRowsCollapsed = 7;

  /// Scrolls the notes card into view and focuses the composer — wired to the
  /// sticky-bar note-pencil affordance (#13).
  void _focusNotes() {
    final ctx = _notesKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 300), alignment: 0.05, curve: Curves.easeOut);
    }
    _notesKey.currentState?.focusComposer();
  }

  /// Opens the lead form in edit mode. Reached from two places — the overflow
  /// menu's "Edit lead" and the sticky bar's pencil — so the converted guard
  /// lives here rather than at each call site.
  ///
  /// A converted lead is frozen server-side (`403` on `PATCH`); say so instead
  /// of opening a form whose save could only fail.
  void _editLead(Lead lead) {
    if (lead.status == 'won') {
      ref
          .read(toastProvider.notifier)
          .show('This lead has converted — edit the customer instead.');
      return;
    }
    context.push('${Routes.addLead}?id=${lead.id}');
  }

  void _openLeadMenu(Lead lead, bool converted) {
    final toast = ref.read(toastProvider.notifier);
    showActionMenu(
      context,
      actions: [
        MenuAction(icon: PhosphorIconsFill.phone, label: 'Call lead', onTap: () => _callLead(lead)),
        MenuAction(icon: PhosphorIconsRegular.whatsappLogo, label: 'WhatsApp chat', onTap: () => toast.show('Opening WhatsApp…')),
        MenuAction(icon: PhosphorIconsRegular.envelopeSimple, label: 'Send email', onTap: () => toast.show('Composing email…')),
        MenuAction(
          icon: PhosphorIconsRegular.handshake,
          label: 'Convert to customer',
          enabled: !converted,
          sublabel: converted ? 'Already converted' : null,
          onTap: () => toast.show('Converting to customer…'),
        ),
        MenuAction(icon: PhosphorIconsRegular.userSwitch, label: 'Reassign owner', onTap: () => toast.show('Reassign owner')),
        // The sticky bar's pencil now opens Edit lead, so the notes composer
        // keeps its shortcut here rather than losing one entirely.
        MenuAction(icon: PhosphorIconsRegular.notePencil, label: 'Add note', onTap: _focusNotes),
        MenuAction(
          icon: PhosphorIconsRegular.pencilSimple,
          label: 'Edit lead',
          enabled: !converted,
          sublabel: converted ? 'Locked — lead converted' : null,
          onTap: () => _editLead(lead),
        ),
      ],
    );
  }

  /// Wraps a loading / error / not-found state under the section app bar so the
  /// back control stays available in every state.
  Widget _stateScaffold(Widget child) => Container(
        color: AppColors.bgDetail,
        child: Column(
          children: [
            DetailAppBar(section: 'Lead', onBack: () => context.pop()),
            Expanded(child: child),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final record = ref.watch(leadDetailProvider(id));

    // The record is authoritative — it is the only source carrying the owner,
    // email, mobile, WhatsApp and territory. The list row stands in until it
    // lands so the page paints straight away rather than flashing a skeleton.
    final lead = record.valueOrNull ?? ref.watch(leadByIdProvider(id));
    if (lead != null) return _buildLead(context, lead);

    if (record.isLoading) return _stateScaffold(const DetailSkeleton());
    if (record.hasError) {
      return _stateScaffold(ErrorState.forError(
        crmAppError(record.error!),
        onRetry: () => ref.invalidate(leadDetailProvider(id)),
      ));
    }
    // Loaded, and the server has no such lead for this caller.
    return _stateScaffold(const EmptyState(
      icon: PhosphorIconsRegular.magnifyingGlass,
      title: 'Lead not found',
      body: 'This lead may have been removed or you no longer have access to it.',
    ));
  }

  /// Places a call to the lead. [LeadCallService] picks the route — Exotel
  /// click-to-call when the org has telephony, the device dialler otherwise —
  /// and this only reports the outcome and refreshes what the call changed.
  Future<void> _callLead(Lead lead) async {
    final outcome = await ref.read(leadCallServiceProvider).call(
          leadId: lead.id,
          toNumber: lead.phone,
          status: ref.read(exotelStatusValueProvider),
        );
    if (!mounted) return;

    // Every route that reached the network leaves a call log behind — the
    // server's own on the Exotel route, ours on the dialler route — and a
    // logged call re-scores the lead.
    if (outcome.result == LeadCallResult.ringingViaExotel ||
        outcome.result == LeadCallResult.dialledAndLogged) {
      ref.invalidate(leadCallLogsProvider(lead.id));
      ref.invalidate(leadDetailProvider(lead.id));
      markRecordChanged(ref, lead.id);
    }

    final toast = ref.read(toastProvider.notifier);
    if (outcome.message != null) toast.show(outcome.message!);
    switch (outcome.result) {
      case LeadCallResult.ringingViaExotel:
        toast.show('Ringing your phone…');
      case LeadCallResult.noNumber:
        toast.show('This lead has no phone number.');
      case LeadCallResult.diallerUnavailable:
        toast.show('Could not open the dialler.');
      case LeadCallResult.dialledNotLogged:
        toast.show('Call not logged — add your phone number to your profile.');
      case LeadCallResult.dialledAndLogged:
      case LeadCallResult.dialledLogFailed:
        break; // the dialler is on screen; a log failure already toasted
    }
  }

  /// Opens the stage picker.
  ///
  /// With the org catalog loaded the options are the org's own stages and
  /// picking one writes it. Without it (mock mode, or a failed fetch) it falls
  /// back to the built-in vocabulary with no `onSelect` — the prototype's
  /// toast-only behaviour, because there is nothing to persist to.
  void _openStatusSheet(Lead lead, List<CatalogOption> statuses) {
    if (statuses.isEmpty) {
      showCrmStatusSheet(
        context: context,
        ref: ref,
        title: 'Update lead status',
        options: StatusMeta$.leadAll,
        meta: StatusMeta$.lead,
        current: lead.status,
      );
      return;
    }
    // The record does not echo `status_id` back, so the current selection is
    // matched on the stage name the API did send.
    final currentKey = lead.statusName.toLowerCase().trim();
    showCrmStatusSheet(
      context: context,
      ref: ref,
      title: 'Update lead status',
      options: [for (final s in statuses) s.id],
      meta: {
        for (final s in statuses) s.id: StatusMeta(s.name, leadStatusColor(s)),
      },
      current: statuses
          .where((s) => s.key == currentKey)
          .map((s) => s.id)
          .firstOrNull ?? '',
      onSelect: (statusId) => _setStatus(lead, statusId),
    );
  }

  /// Writes the new stage, then refreshes the record and every lead list so the
  /// card pill and the tab counts follow.
  Future<void> _setStatus(Lead lead, String statusId) async {
    try {
      await ref.read(leadsRepositoryProvider).updateLeadStatus(lead.id, statusId);
      ref.invalidate(leadDetailProvider(lead.id));
      ref.invalidate(leadsScopedProvider);
      markRecordChanged(ref, lead.id);
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Status updated');
    } on Object catch (e) {
      if (!mounted) return;
      // A rejected write must not leave a stage on screen that was never saved.
      ref.read(toastProvider.notifier).show(
            e is AppError ? e.message : 'Could not update the status.',
          );
    }
  }

  Widget _buildLead(BuildContext context, Lead lead) {

    final statuses = ref.watch(leadStatusesProvider);
    // Watched only to start the telephony-status fetch at mount, so the Call
    // button knows its route before it is tapped.
    ref.watch(exotelStatusProvider);
    // Same resolution the list card uses, so the pill here and the pill there
    // never disagree about a lead's stage name or colour.
    final meta = leadStatusMeta(lead, statuses);
    // "Converted" is derived from the lead itself (won deals are locked from
    // re-conversion); the separate customers list is no longer fetched here.
    final converted = lead.status == 'won';

    // Notes thread (#13) — seeded from the lead's mock notes; via-tagged so the
    // Call/Email pills survive. Stays editable even when the lead is locked.
    final notesSeed = CrmNotesSeed(lead.id, () => [
          NoteEntry(
            id: '${lead.id}-n0',
            author: 'You',
            time: '2h ago',
            via: 'Call',
            body: 'Spoke with ${lead.name.split(' ').first}. Wants a site visit this week for ${lead.project}. Following up with a quote.',
          ),
          NoteEntry(
            id: '${lead.id}-n1',
            author: 'Anjana Menon',
            time: '1d ago',
            via: 'Email',
            avatarColor: AppColors.blueBright,
            body: 'Shared capability deck & reference projects for ${lead.project}. Client responded positively.',
          ),
          NoteEntry(
            id: '${lead.id}-n2',
            author: 'You',
            time: '3d ago',
            body: '${lead.industry} enquiry from ${lead.source} — ${lead.company ?? lead.name}. Value around ${lead.value}.',
          ),
        ], apiModel: 'lead');
    final notes = ref.watch(crmNotesProvider(notesSeed));

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: 'Lead',
            name: lead.name,
            onBack: () => context.pop(),
            trailing: DetailIconAction(
              icon: PhosphorIconsBold.dotsThreeVertical,
              onTap: () => _openLeadMenu(lead, converted),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 140.h),
              children: [
                _profileCard(lead, meta, statuses),
                SizedBox(height: 14.h),
                // The whole score card is one configurable column; an org that
                // hides `lead_score` should not see a card about it.
                if (ref.watch(leadDetailSchemaProvider).shows('lead_score')) ...[
                  _scoreCard(lead),
                  SizedBox(height: 14.h),
                ],
                _infoCard(lead),
                SizedBox(height: 14.h),
                _activityCard(lead),
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
                _activityLogCard(lead),
              ],
            ),
          ),
          _bottomBar(lead),
        ],
      ),
    );
  }

  // ── Profile ──
  Widget _profileCard(Lead lead, StatusMeta meta, List<CatalogOption> statuses) {
    final sd = lead.statusDays;
    final stageLine = sd == 0 ? 'In status since today' : '$sd ${sd == 1 ? 'day' : 'days'} in status';
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
                child: Text(lead.initials, style: AppText.custom(size: 17, weight: FontWeight.w700, color: AppColors.navy, letterSpacing: 0.4)),
              ),
              SizedBox(width: 13.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(lead.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.custom(size: 20, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
                        ),
                        if (lead.upsell) ...[SizedBox(width: 8.w), _upsellBadge()],
                      ],
                    ),
                    SizedBox(height: 3.h),
                    Text('#${lead.id} · ${lead.company ?? lead.location}', style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                    SizedBox(height: 5.h),
                    Row(
                      children: [
                        Icon(PhosphorIconsRegular.clock, size: 13.sp, color: AppColors.textPlaceholder),
                        SizedBox(width: 5.w),
                        Text(stageLine, style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textMuted2)),
                      ],
                    ),
                  ],
                ),
              ),
              if (ref.watch(leadDetailSchemaProvider).shows('lead_value')) ...[
                SizedBox(width: 8.w),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(lead.value, style: AppText.custom(size: 20, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
                    SizedBox(height: 1.h),
                    Text('VALUE', style: AppText.custom(size: 10, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.4)),
                  ],
                ),
              ],
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 15)),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _openStatusSheet(lead, statuses),
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
                  onTap: () => context.push(Routes.addQuote),
                  child: Container(
                    height: 44.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(11.r)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(PhosphorIconsRegular.fileText, size: 16.sp, color: AppColors.white),
                        SizedBox(width: 8.w),
                        Text('Create quote', style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.white)),
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

  // ── Score + AI ──
  Widget _scoreCard(Lead lead) {
    final score = lead.score;
    final color = score >= 75 ? AppColors.success : (score >= 45 ? AppColors.warningDeep : AppColors.error);
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text('Lead score', style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
                  SizedBox(width: 6.w),
                  GestureDetector(
                    onTap: () => setState(() => _scoreInfo = !_scoreInfo),
                    child: Icon(PhosphorIconsRegular.info, size: 15.sp, color: AppColors.textPlaceholder),
                  ),
                ],
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 2.h),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(7.r)),
                child: Text('$score / 100', style: AppText.custom(size: 12, weight: FontWeight.w700, color: color)),
              ),
            ],
          ),
          if (_scoreInfo) ...[
            SizedBox(height: 9.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 11.w, vertical: 9.h),
              decoration: BoxDecoration(color: const Color(0xFFF6F8FB), borderRadius: BorderRadius.circular(10.r)),
              child: Text('Blends recency, engagement, deal size and stage progress. Scoring rules are configured in the web app.',
                  style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textLabelAlt).copyWith(height: 1.55)),
            ),
          ],
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
  /// before the layout became configurable.
  List<({String label, String value})> _fallbackInfoRows(Lead lead) => [
        (label: 'Email', value: lead.email),
        (label: 'Mobile', value: lead.phone),
        (label: 'Lead source', value: lead.source),
        (label: 'Product / Need', value: lead.project),
        (label: 'Deal value', value: lead.value),
        (label: 'Industry', value: lead.industry),
        (label: 'Location', value: lead.location),
        (label: 'Created on', value: lead.createdOn),
        (label: 'Website', value: lead.website),
      ];

  // ── Information ──
  Widget _infoCard(Lead lead) {
    // The org's own detail layout drives these rows: which fields, in what
    // order, under what labels. Empty schema → the built-in list above.
    final schema = ref.watch(leadDetailSchemaProvider);
    final all = schema.isEmpty
        ? _fallbackInfoRows(lead)
        : leadDetailRows(lead, schema);
    // Long layouts stay collapsed behind "Show more"; a short one shows whole.
    final collapsible = all.length > _infoRowsCollapsed;
    final rows =
        (_infoMore || !collapsible) ? all : all.take(_infoRowsCollapsed).toList();
    final owner = MockUsers.of(lead.owner);
    final assignees = lead.team.where((t) => t != lead.owner).toList();
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
          Text('Lead information', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 6.h),
          for (final r in rows) DetailInfoRow(label: r.label, value: r.value),
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
          SizedBox(height: 8.h),
          Row(
            children: [
              Icon(PhosphorIconsRegular.handTap, size: 13.sp, color: AppColors.textPlaceholder),
              SizedBox(width: 6.w),
              Text('Fields are edited in the web app', style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
            ],
          ),
          // The people block mirrors three configurable columns; when the org
          // has hidden all three there is nothing to head, so the whole section
          // goes with them.
          if (schema.showsAny(const ['lead_owner', 'assignees', 'assigned_team'])) ...[
          SizedBox(height: 18.h),
          Text('OWNER & ASSIGNEES', style: AppText.custom(size: 11, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.6)),
          SizedBox(height: 4.h),
          if (schema.shows('lead_owner'))
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
                      Text('Lead owner', style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                _roundAction(PhosphorIconsRegular.arrowsClockwise, () => ref.read(toastProvider.notifier).show('Reassign owner')),
              ],
            ),
          ),
          if (schema.shows('assignees'))
          Container(
            padding: EdgeInsets.symmetric(vertical: 10.h),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(schema.labelOf('assignees', 'Assignees'),
                          style: AppText.caption(color: AppColors.textMuted)),
                      SizedBox(height: 4.h),
                      if (assignees.isEmpty)
                        Text('No assignees yet', style: AppText.custom(size: 13.5, weight: FontWeight.w500, color: AppColors.textPlaceholder))
                      else
                        Text(assignees.map((t) => MockUsers.of(t).name.split(' ').first).join(', '),
                            style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                _roundAction(PhosphorIconsRegular.userPlus, () => ref.read(toastProvider.notifier).show('Add assignee')),
              ],
            ),
          ),
          if (schema.shows('assigned_team'))
          Padding(
            padding: EdgeInsets.only(top: 10.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(schema.labelOf('assigned_team', 'Assigned team'),
                    style: AppText.caption(color: AppColors.textMuted)),
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

  /// The activity card's CTA — one create path per tab, each carrying the lead
  /// so the new record comes back in this screen's own scoped fetch.
  Future<void> _activityCta(Lead lead) async {
    switch (_tab) {
      case 0:
        await showAddTaskSheet(context, ref, lead: lead);
      case 1:
        await showLogCallSheet(context, ref, lead: lead);
      case 2:
        await showAddFollowupSheet(context, ref, lead: lead);
      case 3:
        if (mounted) context.push('${Routes.addQuote}?leadId=${lead.id}');
      default:
        await _uploadFiles(lead);
    }
    // The sheets report no outcome, so this fires even on cancel — one wasted
    // read of a small log beats an activity entry that never shows up.
    if (mounted) markRecordChanged(ref, lead.id);
  }

  /// Picks files off the device and posts them to this lead.
  ///
  /// Uploads run one at a time and stop at the first rejection — pushing the
  /// remainder after a failure usually just repeats it, and a half-finished
  /// batch is easier to reason about when the count is reported.
  Future<void> _uploadFiles(Lead lead) async {
    if (_uploading) return;
    final toast = ref.read(toastProvider.notifier);

    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false, // paths only — a large file should not sit in memory
    );
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
        final saved = await repo.uploadFileForLead(
          leadId: lead.id,
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

    if (stored > 0) {
      ref.invalidate(leadFilesProvider(lead.id));
      markRecordChanged(ref, lead.id);
    }
    if (failure != null) {
      // Say what did land before what didn't, so a partial batch is not read
      // as a total failure.
      toast.show(stored == 0 ? failure : '$stored uploaded · $failure');
    } else {
      toast.show(stored == 1 ? 'File uploaded' : '$stored files uploaded');
    }
  }

  // ── Activity card (tabs) ──
  Widget _activityCard(Lead lead) {
    const ctaLabels = ['Add task', 'Log call', 'Add follow-up', 'Create quote', 'Upload file'];
    final ctaLabel = _uploading && _tab == 4 ? 'Uploading…' : ctaLabels[_tab];
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Lead activity', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary))),
              GestureDetector(
                onTap: () => _activityCta(lead),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(9.r), border: Border.all(color: const Color(0xFFE6E7EA))),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_tab >= 3 ? (_tab == 3 ? PhosphorIconsRegular.fileText : PhosphorIconsRegular.uploadSimple) : PhosphorIconsBold.plus, size: 13.sp, color: AppColors.textSecondary),
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
          _tabContent(lead),
        ],
      ),
    );
  }

  Widget _tabContent(Lead lead) {
    switch (_tab) {
      case 0:
        return _tasksTab(lead);
      case 1:
        return _callLogTab(lead);
      case 2:
        return _followupsTab(lead);
      case 3:
        return _quotesTab(lead);
      default:
        return _filesTab(lead);
    }
  }

  /// Loading / error / empty / data for one activity tab.
  ///
  /// Every tab reads its own lead-scoped provider, so a failed fetch shows a
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

  Widget _tasksTab(Lead lead) {
    return _tabAsync<CrmTask>(
      ref.watch(leadTasksProvider(lead.id)),
      onRetry: () => ref.invalidate(leadTasksProvider(lead.id)),
      empty: const DetailTabEmpty(icon: PhosphorIconsRegular.checkSquare, title: 'No tasks yet', body: 'Tasks linked to this lead will appear here.'),
      data: (tasks) => Column(
        children: [
          for (final t in tasks)
          Container(
            padding: EdgeInsets.symmetric(vertical: 13.h, horizontal: 2.w),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CrmCheckBox(done: t.status == 'done', onTap: () => ref.read(toastProvider.notifier).show('Task updated')),
                SizedBox(width: 12.w),
                Expanded(
                  child: GestureDetector(
                    onTap: () => context.push('${Routes.taskDetail}?id=${t.id}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.titleClean,
                            style: AppText.custom(size: 14, weight: FontWeight.w600, color: t.status == 'done' ? AppColors.textPlaceholder : AppColors.textPrimary)
                                .copyWith(decoration: t.status == 'done' ? TextDecoration.lineThrough : null)),
                        SizedBox(height: 3.h),
                        Text('${t.due} · ${MockUsers.of(t.assignee).name.split(' ').first} · ${t.priority}', style: AppText.caption()),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                _miniPill(StatusMeta$.task[t.status] ?? StatusMeta$.task['todo']!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _callLogTab(Lead lead) {
    return _tabAsync<CallLog>(
      ref.watch(leadCallLogsProvider(lead.id)),
      onRetry: () => ref.invalidate(leadCallLogsProvider(lead.id)),
      empty: const DetailTabEmpty(icon: PhosphorIconsRegular.phone, title: 'No calls logged', body: 'Calls made to or received from this lead will appear here.'),
      data: (calls) => Column(children: [for (final c in calls) _callRow(c)]),
    );
  }

  /// One call row. The icon shows direction, the tint shows how it ended —
  /// answered (green out / blue in), unanswered (grey) or missed (red).
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
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 2.w),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38.w,
            height: 38.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(11.r)),
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
                      Icon(PhosphorIconsRegular.waveform, size: 14.sp, color: AppColors.textPlaceholder),
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
                      style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted).copyWith(height: 1.4)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _followupsTab(Lead lead) {
    return _tabAsync<Followup>(
      ref.watch(leadFollowupsProvider(lead.id)),
      onRetry: () => ref.invalidate(leadFollowupsProvider(lead.id)),
      empty: const DetailTabEmpty(icon: PhosphorIconsRegular.clock, title: 'No follow-ups scheduled', body: 'Follow-ups scheduled for this lead will appear here.'),
      data: (fus) => Padding(
        padding: EdgeInsets.only(top: 12.h),
        child: Column(
          children: [
            for (final f in fus)
            Container(
              margin: EdgeInsets.only(bottom: 12.h),
              padding: EdgeInsets.all(14.r),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14.r), border: Border.all(color: AppColors.borderCardSoft)),
              child: GestureDetector(
                onTap: () => context.push('${Routes.followupDetail}?id=${f.id}'),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42.w,
                      height: 42.w,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(12.r)),
                      child: Icon(PhosphorIconsRegular.calendarBlank, size: 19.sp, color: AppColors.navy),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.agenda.isEmpty ? '${f.kind} follow-up' : f.agenda,
                              style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                          SizedBox(height: 3.h),
                          Text('${f.kind} · ${f.contact}', style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted2)),
                          SizedBox(height: 3.h),
                          Text('${f.due.replaceAll(' 2026', '')} · ${f.time}', style: AppText.caption(color: AppColors.textPlaceholder)),
                        ],
                      ),
                    ),
                      _miniPill(StatusMeta$.followup[f.status] ?? StatusMeta$.followup['due']!),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _quotesTab(Lead lead) {
    return _tabAsync<Quote>(
      ref.watch(leadQuotesProvider(lead.id)),
      onRetry: () => ref.invalidate(leadQuotesProvider(lead.id)),
      empty: DetailTabEmpty(
        icon: PhosphorIconsRegular.fileText,
        title: 'No quotes yet',
        body: 'Create a quotation to share pricing with this lead.',
        cta: GestureDetector(
          onTap: () => context.push(Routes.addQuote),
          child: Container(
            height: 42.h,
            padding: EdgeInsets.symmetric(horizontal: 18.w),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(10.r)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIconsBold.plus, size: 14.sp, color: AppColors.white),
                SizedBox(width: 7.w),
                Text('Create quote', style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.white)),
              ],
            ),
          ),
        ),
      ),
      data: (quotes) => Column(children: [for (final q in quotes) _quoteRow(q)]),
    );
  }

  Widget _quoteRow(Quote q) {
    final meta = StatusMeta$.quote[q.status] ?? StatusMeta$.quote['draft']!;
    final validLabel = q.valid == '—' || q.valid.isEmpty ? 'Draft — not issued' : 'Valid till ${q.valid}';
    return Container(
      padding: EdgeInsets.symmetric(vertical: 13.h, horizontal: 2.w),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
      child: GestureDetector(
        onTap: () => context.push('${Routes.quoteDetail}?id=${q.id}'),
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38.w,
              height: 38.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(11.r)),
              child: Icon(PhosphorIconsRegular.fileText, size: 18.sp, color: AppColors.textSecondary),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('#${q.id}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textPrimary)),
                  SizedBox(height: 3.h),
                  Text(validLabel, style: AppText.caption()),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _miniPill(meta),
                SizedBox(height: 5.h),
                Text(q.amount, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _filesTab(Lead lead) {
    return _tabAsync<LeadFile>(
      ref.watch(leadFilesProvider(lead.id)),
      onRetry: () => ref.invalidate(leadFilesProvider(lead.id)),
      empty: const DetailTabEmpty(
        icon: PhosphorIconsRegular.paperclip,
        title: 'No files shared',
        body: 'Drawings, moodboards and documents will appear here.',
      ),
      data: (files) => Column(children: [for (final f in files) _fileRow(f)]),
    );
  }

  Widget _fileRow(LeadFile f) {
    final uploader = MockUsers.of(f.uploadedBy).name.split(' ').first;
    final meta = [f.ext, if (uploader.isNotEmpty) uploader, if (f.uploadedAt.isNotEmpty) f.uploadedAt].join(' · ');
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 2.w),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38.w,
            height: 38.w,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(11.r)),
            child: Icon(PhosphorIconsRegular.paperclip, size: 18.sp, color: AppColors.textSecondary),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textPrimary)),
                SizedBox(height: 3.h),
                Text(meta, style: AppText.caption()),
                if (f.description.isNotEmpty) ...[
                  SizedBox(height: 4.h),
                  Text(f.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted).copyWith(height: 1.4)),
                ],
              ],
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
        (PhosphorIconsRegular.userPlus, AppColors.textMuted2, AppColors.bgChipGrey),
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

  Widget _activityLogCard(Lead lead) {
    // The record's real audit trail. Empty in mock mode, on failure, and for a
    // user without `view_audit_log` — in which case the card is not rendered at
    // all rather than showing an invented history.
    final entries = ref.watch(leadActivityLogProvider(lead.id)).valueOrNull ?? const [];
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
              Icon(PhosphorIconsRegular.clockCounterClockwise, size: 16.sp, color: AppColors.textLabelAlt),
              SizedBox(width: 7.w),
              Text('Activity log', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          SizedBox(height: 12.h),
          ActivityTimeline(items: items),
        ],
      ),
    );
  }

  Widget _bottomBar(Lead lead) {
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
              onTap: () => _callLead(lead),
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
          // Same destination as the overflow menu's Edit lead, and the same
          // lock: a converted lead is frozen server-side (403), so offering the
          // form would only produce a rejected save.
          _squareAction(
            PhosphorIconsBold.pencilSimple,
            AppColors.white,
            () => _editLead(lead),
            border: const Color(0xFFB9C2D8),
            borderWidth: 1.5,
          ),
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
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13.r), border: Border.all(color: border, width: borderWidth)),
        child: Icon(icon, size: 22.sp, color: AppColors.navy),
      ),
    );
  }
}
