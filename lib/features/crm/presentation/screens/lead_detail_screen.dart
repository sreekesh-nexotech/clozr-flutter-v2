import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/models/note.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/notes_thread.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/crm_notes_providers.dart';
import '../../application/providers/crm_tasks_providers.dart';
import '../../application/providers/customers_providers.dart';
import '../../application/providers/followups_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../../domain/entities/lead.dart';
import '../components/crm_check_box.dart';
import '../components/crm_detail_parts.dart';
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
  final _notesKey = GlobalKey<NotesThreadState>();

  static const _tabLabels = ['Tasks', 'Call log', 'Follow-ups', 'Quotes', 'Files'];

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

  void _openLeadMenu(Lead lead, bool converted) {
    final toast = ref.read(toastProvider.notifier);
    final first = lead.name.split(' ').first;
    showActionMenu(
      context,
      actions: [
        MenuAction(icon: PhosphorIconsFill.phone, label: 'Call lead', onTap: () => toast.show('Calling $first…')),
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
        MenuAction(
          icon: PhosphorIconsRegular.pencilSimple,
          label: 'Edit lead',
          enabled: !converted,
          sublabel: converted ? 'Locked — lead converted' : null,
          onTap: () => context.push('${Routes.addLead}?id=${lead.id}'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final lead = ref.watch(leadByIdProvider(id));

    if (lead == null) {
      return Container(
        color: AppColors.bgDetail,
        child: Column(
          children: [
            DetailAppBar(section: 'Lead', onBack: () => context.pop()),
            const Expanded(child: Center(child: Text('Lead not found'))),
          ],
        ),
      );
    }

    final meta = StatusMeta$.lead[lead.status] ?? StatusMeta$.lead['new']!;
    final customers = ref.watch(customersProvider).valueOrNull ?? const [];
    final relCust = customers.where((c) => c.leadId == lead.id).toList();
    final converted = relCust.isNotEmpty;

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
                _profileCard(lead, meta),
                if (converted) ...[
                  SizedBox(height: 14.h),
                  _convertedBanner(relCust.first.id),
                ],
                SizedBox(height: 14.h),
                _scoreCard(lead),
                SizedBox(height: 14.h),
                _infoCard(lead),
                SizedBox(height: 14.h),
                _activityCard(lead),
                SizedBox(height: 14.h),
                NotesThread(
                  key: _notesKey,
                  notes: notes,
                  onAddNote: (body, atts) =>
                      ref.read(crmNotesProvider(notesSeed).notifier).addNote(body, atts, const NoteAuthor()),
                  onAddReply: (noteId, body) =>
                      ref.read(crmNotesProvider(notesSeed).notifier).addReply(noteId, body, const NoteAuthor()),
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
  Widget _profileCard(Lead lead, StatusMeta meta) {
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
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 15)),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => showCrmStatusSheet(
                    context: context,
                    ref: ref,
                    title: 'Update lead status',
                    options: StatusMeta$.leadAll,
                    meta: StatusMeta$.lead,
                    current: lead.status,
                  ),
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

  Widget _convertedBanner(String custId) {
    return GestureDetector(
      onTap: () => context.push('${Routes.customerDetail}?id=$custId'),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        decoration: BoxDecoration(color: AppColors.tintGreen, borderRadius: BorderRadius.circular(14.r)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(PhosphorIconsFill.sealCheck, size: 18.sp, color: AppColors.success),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Converted to customer', style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.success)),
                  SizedBox(height: 2.h),
                  Text('This lead is locked — manage ongoing work from the customer record.',
                      style: AppText.custom(size: 12, weight: FontWeight.w500, color: const Color(0xFF4A7C5B))),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            Icon(PhosphorIconsBold.caretRight, size: 13.sp, color: AppColors.success),
          ],
        ),
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

  // ── Information ──
  Widget _infoCard(Lead lead) {
    final all = <(String, String)>[
      ('Email', lead.email),
      ('Mobile', lead.phone),
      ('Lead source', lead.source),
      ('Product / Need', lead.project),
      ('Deal value', lead.value),
      ('Industry', lead.industry),
      ('Location', lead.location),
      ('Created on', lead.createdOn),
      ('Website', lead.website),
      ('Warranty period', '—'),
      ('Custom fields', 'Configured in web app'),
    ];
    final rows = _infoMore ? all : all.take(7).toList();
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
          for (final r in rows) DetailInfoRow(label: r.$1, value: r.$2),
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
                      Text('Lead owner', style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                _roundAction(PhosphorIconsRegular.arrowsClockwise, () => ref.read(toastProvider.notifier).show('Reassign owner')),
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
                _roundAction(PhosphorIconsRegular.userPlus, () => ref.read(toastProvider.notifier).show('Add assignee')),
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

  // ── Activity card (tabs) ──
  Widget _activityCard(Lead lead) {
    final ctaLabels = ['Add task', 'Log call', 'Add follow-up', 'Create quote', 'Upload file'];
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Lead activity', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary))),
              GestureDetector(
                onTap: () {
                  if (_tab == 3) {
                    context.push(Routes.addQuote);
                  } else {
                    ref.read(toastProvider.notifier).show(ctaLabels[_tab]);
                  }
                },
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(9.r), border: Border.all(color: const Color(0xFFE6E7EA))),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_tab >= 3 ? (_tab == 3 ? PhosphorIconsRegular.fileText : PhosphorIconsRegular.uploadSimple) : PhosphorIconsBold.plus, size: 13.sp, color: AppColors.textSecondary),
                      SizedBox(width: 6.w),
                      Text(ctaLabels[_tab], style: AppText.bodyStrong()),
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
        return _callLogTab();
      case 2:
        return _followupsTab(lead);
      case 3:
        return _quotesTab();
      default:
        return const DetailTabEmpty(
          icon: PhosphorIconsRegular.paperclip,
          title: 'No files shared',
          body: 'Drawings, moodboards and documents will appear here.',
        );
    }
  }

  Widget _tasksTab(Lead lead) {
    final tasks = (ref.watch(crmTasksProvider).valueOrNull ?? const []).where((t) => t.leadId == lead.id).toList();
    if (tasks.isEmpty) {
      return const DetailTabEmpty(icon: PhosphorIconsRegular.checkSquare, title: 'No tasks yet', body: 'Tasks linked to this lead will appear here.');
    }
    return Column(
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
    );
  }

  Widget _callLogTab() {
    final rows = <(IconData, Color, String, String)>[
      (PhosphorIconsRegular.phoneOutgoing, AppColors.success, 'Connected · 4m 12s', 'Today, 9:32 AM'),
      (PhosphorIconsRegular.phoneOutgoing, AppColors.textPlaceholder, 'No answer', 'Yesterday, 5:10 PM'),
      (PhosphorIconsRegular.phoneIncoming, AppColors.blueBright, 'Connected · 2m 40s', '2 days ago, 11:04 AM'),
      (PhosphorIconsRegular.phoneX, AppColors.error, 'Missed call', '4 days ago, 3:22 PM'),
    ];
    return Column(
      children: [
        for (final r in rows)
          Container(
            padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 2.w),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
            child: Row(
              children: [
                Container(
                  width: 38.w,
                  height: 38.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(11.r)),
                  child: Icon(r.$1, size: 18.sp, color: r.$2),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.$3, style: AppText.bodyStrong()),
                      SizedBox(height: 2.h),
                      Text(r.$4, style: AppText.caption()),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _followupsTab(Lead lead) {
    final fus = (ref.watch(followupsProvider).valueOrNull ?? const []).where((f) => f.leadId == lead.id).toList();
    if (fus.isEmpty) {
      return const DetailTabEmpty(icon: PhosphorIconsRegular.clock, title: 'No follow-ups scheduled', body: 'Follow-ups scheduled for this lead will appear here.');
    }
    return Padding(
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
    );
  }

  Widget _quotesTab() {
    return DetailTabEmpty(
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
    );
  }

  Widget _miniPill(StatusMeta meta) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 3.h),
      decoration: BoxDecoration(color: meta.color.withOpacity(0.09), borderRadius: BorderRadius.circular(7.r)),
      child: Text(meta.label, style: AppText.custom(size: 11, weight: FontWeight.w700, color: meta.color)),
    );
  }

  Widget _activityLogCard(Lead lead) {
    final owner = MockUsers.of(lead.owner);
    final items = <ActivityItem>[
      ActivityItem(icon: PhosphorIconsRegular.phone, tone: AppColors.success, bg: AppColors.tintGreen, title: 'Call logged', sub: 'Discussed scope and timeline with ${lead.name.split(' ').first}', time: 'Today · 9:32 AM'),
      ActivityItem(icon: PhosphorIconsRegular.paperPlaneTilt, tone: AppColors.blueBright, bg: AppColors.tintBlue, title: 'Quotation sent', sub: 'Shared estimate for ${lead.project}', time: 'Yesterday · 4:15 PM'),
      const ActivityItem(icon: PhosphorIconsRegular.mapPin, tone: AppColors.warningDeep, bg: AppColors.tintAmber, title: 'Site visit scheduled', sub: 'Measurement visit planned by Anjana Menon', time: '2 days ago'),
      ActivityItem(icon: PhosphorIconsRegular.userPlus, tone: AppColors.textMuted2, bg: AppColors.bgChipGrey, title: 'Lead created', sub: 'Source: ${lead.source} · assigned to ${owner.name}', time: '5 days ago'),
    ];
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
              onTap: () => ref.read(toastProvider.notifier).show('Calling ${lead.name.split(' ').first}…'),
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
          _squareAction(PhosphorIconsBold.notePencil, AppColors.white, _focusNotes, border: const Color(0xFFB9C2D8), borderWidth: 1.5),
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
