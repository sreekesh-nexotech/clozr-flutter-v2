import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/crm_tasks_providers.dart';
import '../../application/providers/customers_providers.dart';
import '../../application/providers/followups_providers.dart';
import '../../application/providers/leads_providers.dart';
import '../../domain/entities/customer.dart';
import '../components/crm_check_box.dart';
import '../components/crm_detail_parts.dart';
import 'crm_status_sheet.dart';

/// A customer payment row (a small inline port of the seed `payments` filtered
/// by customer — the full payments module is owned elsewhere).
class _Pay {
  final String id;
  final String label;
  final String date;
  final String amount;
  final String status;
  const _Pay(this.id, this.label, this.date, this.amount, this.status);
}

const _custPayments = <String, List<_Pay>>{
  'C2001': [_Pay('PAY-4001', 'Full payment · Bank transfer', '05 May 2026', '₹18L', 'paid')],
  'C2003': [
    _Pay('PAY-4002', 'Advance (40%) · Cheque', '18 May 2026', '₹18.3L', 'paid'),
    _Pay('PAY-4003', 'Milestone (30%) · UPI', '02 Jun 2026', '₹18.3L', 'paid'),
    _Pay('PAY-4004', 'On handover (30%)', 'Overdue 24 Jun 2026', '₹18.3L', 'overdue'),
  ],
  'C2005': [
    _Pay('PAY-4005', 'Advance (50%) · UPI', '02 Jun 2026', '₹46L', 'paid'),
    _Pay('PAY-4006', 'Balance (50%) · Auto-debit', '12 Jun 2026', '₹46L', 'paid'),
  ],
  'C2007': [
    _Pay('PAY-4007', 'Advance (40%) · Auto-debit', '12 Jun 2026', '₹43L', 'paid'),
    _Pay('PAY-4008', 'Milestone (30%) · Bank transfer', '20 Jun 2026', '₹43L', 'paid'),
    _Pay('PAY-4009', 'On handover (30%)', 'Overdue 24 Jun 2026', '₹43L', 'overdue'),
  ],
  'C2010': [
    _Pay('PAY-4010', 'Advance (50%) · Bank transfer', '20 Jun 2026', '₹1.01Cr', 'paid'),
    _Pay('PAY-4011', 'Balance (50%)', 'Due 05 Jul 2026', '₹1.01Cr', 'due'),
  ],
  'C2006': [_Pay('PAY-4013', 'Advance (50%)', 'Due 10 Jul 2026', '₹14L', 'due')],
  'C2009': [_Pay('PAY-4014', 'Advance (30%)', 'Scheduled 15 Jul 2026', '₹50L', 'scheduled')],
  'C2012': [_Pay('PAY-4012', 'Full payment · Cheque', '05 May 2026', '₹18L', 'paid')],
};

class CustomerDetailScreen extends ConsumerStatefulWidget {
  const CustomerDetailScreen({super.key});

  @override
  ConsumerState<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  int _tab = 0;
  bool _infoMore = false;

  static const _tabLabels = ['Tasks', 'Call log', 'Follow-ups', 'Payments', 'Leads', 'Files'];

  @override
  Widget build(BuildContext context) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final cust = ref.watch(customerByIdProvider(id));

    if (cust == null) {
      return Container(
        color: AppColors.bgDetail,
        child: Column(
          children: [
            DetailAppBar(section: 'Customer', onBack: () => context.pop()),
            const Expanded(child: Center(child: Text('Customer not found'))),
          ],
        ),
      );
    }

    final meta = StatusMeta$.customer[cust.status] ?? StatusMeta$.customer['active']!;

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: 'Customer',
            name: cust.name,
            onBack: () => context.pop(),
            trailing: DetailIconAction(
              icon: PhosphorIconsBold.dotsThreeVertical,
              onTap: () => ref.read(toastProvider.notifier).show('Customer actions'),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 140.h),
              children: [
                _profileCard(cust, meta),
                SizedBox(height: 14.h),
                _scoreCard(cust),
                SizedBox(height: 14.h),
                _infoCard(cust),
                SizedBox(height: 14.h),
                _activityCard(cust),
                SizedBox(height: 14.h),
                DetailNotesCard(
                  count: 3,
                  notes: [
                    NoteEntry(author: 'You', time: '2h ago', body: 'Spoke with ${cust.name.split(' ').first}. Ongoing work on track; discussing an upsell.'),
                    NoteEntry(author: 'Anjana Menon', time: '1d ago', body: 'Shared the revised BOQ. Client happy with progress on ${cust.project}.'),
                    NoteEntry(author: 'You', time: '3d ago', body: '${cust.industry} account since ${cust.since}. Value ${cust.value}.'),
                  ],
                  onSend: () => ref.read(toastProvider.notifier).show('Note added'),
                ),
                SizedBox(height: 14.h),
                _activityLogCard(cust),
              ],
            ),
          ),
          _bottomBar(cust),
        ],
      ),
    );
  }

  Widget _profileCard(Customer cust, StatusMeta meta) {
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
                child: Text(cust.initials, style: AppText.custom(size: 17, weight: FontWeight.w700, color: AppColors.navy, letterSpacing: 0.4)),
              ),
              SizedBox(width: 13.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(cust.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.custom(size: 20, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
                        ),
                        if (cust.isUpsell) ...[SizedBox(width: 8.w), _upsellBadge()],
                      ],
                    ),
                    SizedBox(height: 3.h),
                    Text('#${cust.id} · ${cust.company ?? ''}', style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                    SizedBox(height: 5.h),
                    Row(
                      children: [
                        Icon(PhosphorIconsRegular.clock, size: 13.sp, color: AppColors.textPlaceholder),
                        SizedBox(width: 5.w),
                        Text('Customer since ${cust.since}', style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textMuted2)),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(cust.value, style: AppText.custom(size: 20, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
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
                    title: 'Update customer status',
                    options: StatusMeta$.customerOrder,
                    meta: StatusMeta$.customer,
                    current: cust.status,
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
                  onTap: () => ref.read(toastProvider.notifier).show('Creating upsell opportunity…'),
                  child: Container(
                    height: 44.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(11.r)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(PhosphorIconsFill.trendUp, size: 16.sp, color: AppColors.white),
                        SizedBox(width: 8.w),
                        Text('Upsell', style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.white)),
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

  Widget _scoreCard(Customer cust) {
    final score = cust.score;
    final color = score >= 75 ? AppColors.success : (score >= 45 ? AppColors.warningDeep : AppColors.error);
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Customer score', style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 2.h),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(7.r)),
                child: Text('$score / 100', style: AppText.custom(size: 12, weight: FontWeight.w700, color: color)),
              ),
            ],
          ),
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

  Widget _infoCard(Customer cust) {
    final all = <(String, String)>[
      ('Email', cust.email),
      ('Mobile', cust.phone),
      ('Location', cust.location),
      ('Source', cust.source),
      ('Customer since', cust.since),
      ('Product / Need', cust.project),
      ('Deal value', cust.value),
      ('Industry', cust.industry),
      ('Website', cust.website),
      ('Warranty period', '—'),
      ('Custom fields', 'Configured in web app'),
    ];
    final rows = _infoMore ? all : all.take(7).toList();
    final owner = MockUsers.of(cust.owner);
    final assignees = cust.team.where((t) => t != cust.owner).toList();
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
          Text('Customer information', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
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
                      Text('Account owner', style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
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

  Widget _activityCard(Customer cust) {
    final ctaLabels = ['Add task', 'Log call', 'Add follow-up', 'Record payment', 'New lead', 'Upload file'];
    return ClozrCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Customer activity', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary))),
              GestureDetector(
                onTap: () => ref.read(toastProvider.notifier).show(ctaLabels[_tab]),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(9.r), border: Border.all(color: const Color(0xFFE6E7EA))),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_tab == 5 ? PhosphorIconsRegular.uploadSimple : PhosphorIconsBold.plus, size: 13.sp, color: AppColors.textSecondary),
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
          _tabContent(cust),
        ],
      ),
    );
  }

  Widget _tabContent(Customer cust) {
    switch (_tab) {
      case 0:
        return _tasksTab(cust);
      case 1:
        return _callLogTab();
      case 2:
        return _followupsTab(cust);
      case 3:
        return _paymentsTab(cust);
      case 4:
        return _leadsTab(cust);
      default:
        return const DetailTabEmpty(
          icon: PhosphorIconsRegular.paperclip,
          title: 'No files shared',
          body: 'Drawings, BOQs and documents will appear here.',
        );
    }
  }

  Widget _tasksTab(Customer cust) {
    final tasks = (ref.watch(crmTasksProvider).valueOrNull ?? const []).where((t) => t.leadId == cust.leadId).toList();
    if (tasks.isEmpty) {
      return const DetailTabEmpty(icon: PhosphorIconsRegular.checkSquare, title: 'No tasks yet', body: 'Tasks linked to this customer will appear here.');
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

  Widget _followupsTab(Customer cust) {
    final fus = (ref.watch(followupsProvider).valueOrNull ?? const [])
        .where((f) => f.custId == cust.id || (cust.leadId != null && f.leadId == cust.leadId))
        .toList();
    if (fus.isEmpty) {
      return const DetailTabEmpty(icon: PhosphorIconsRegular.clock, title: 'No follow-ups scheduled', body: 'Follow-ups scheduled for this customer will appear here.');
    }
    return Padding(
      padding: EdgeInsets.only(top: 12.h),
      child: Column(
        children: [
          for (final f in fus)
            Container(
              margin: EdgeInsets.only(bottom: 12.h),
              padding: EdgeInsets.all(14.r),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(color: AppColors.borderCardSoft),
              ),
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

  Widget _paymentsTab(Customer cust) {
    final rows = _custPayments[cust.id] ?? const [];
    if (rows.isEmpty) {
      return const DetailTabEmpty(icon: PhosphorIconsRegular.wallet, title: 'No payments yet', body: 'Payments recorded for this customer will appear here.');
    }
    return Column(
      children: [
        for (final p in rows)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.push('${Routes.paymentDetail}?id=${p.id}'),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 2.w),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
              child: Row(
                children: [
                  Container(
                    width: 38.w,
                    height: 38.w,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.bgChipGrey, borderRadius: BorderRadius.circular(11.r)),
                    child: Icon(PhosphorIconsRegular.wallet, size: 18.sp, color: AppColors.navy),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textPrimary)),
                        SizedBox(height: 2.h),
                        Text(p.date, style: AppText.custom(size: 12, weight: FontWeight.w500, color: p.status == 'overdue' ? AppColors.error : AppColors.textPlaceholder)),
                      ],
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(p.amount, style: AppText.custom(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
                      SizedBox(height: 4.h),
                      _miniPill(StatusMeta$.payment[p.status] ?? StatusMeta$.payment['due']!),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _leadsTab(Customer cust) {
    final leads = (ref.watch(leadsProvider).valueOrNull ?? const [])
        .where((l) => l.id == cust.leadId || (cust.company != null && l.company == cust.company))
        .toList();
    if (leads.isEmpty) {
      return const DetailTabEmpty(icon: PhosphorIconsRegular.funnelSimple, title: 'No linked leads', body: 'Leads linked to this customer will appear here.');
    }
    return Column(
      children: [
        for (final l in leads)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.push('${Routes.leadDetail}?id=${l.id}'),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 2.w),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
              child: Row(
                children: [
                  Container(
                    width: 42.w,
                    height: 42.w,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Color(0xFFEEF1F4), shape: BoxShape.circle),
                    child: Text(l.initials, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.navy)),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.name, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
                        SizedBox(height: 2.h),
                        Text('#${l.id} · ${StatusMeta$.lead[l.status]?.label ?? ''} · ${l.value}', style: AppText.caption()),
                      ],
                    ),
                  ),
                  Icon(PhosphorIconsBold.caretRight, size: 14.sp, color: AppColors.textPlaceholder),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _miniPill(StatusMeta meta) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 3.h),
      decoration: BoxDecoration(color: meta.color.withOpacity(0.09), borderRadius: BorderRadius.circular(7.r)),
      child: Text(meta.label, style: AppText.custom(size: 11, weight: FontWeight.w700, color: meta.color)),
    );
  }

  Widget _activityLogCard(Customer cust) {
    final owner = MockUsers.of(cust.owner);
    final items = <ActivityItem>[
      ActivityItem(icon: PhosphorIconsRegular.phone, tone: AppColors.success, bg: AppColors.tintGreen, title: 'Call logged', sub: 'Discussed ongoing work with ${cust.name.split(' ').first}', time: 'Today · 9:32 AM'),
      ActivityItem(icon: PhosphorIconsRegular.paperPlaneTilt, tone: AppColors.blueBright, bg: AppColors.tintBlue, title: 'Invoice shared', sub: 'Milestone invoice for ${cust.project}', time: 'Yesterday · 4:15 PM'),
      const ActivityItem(icon: PhosphorIconsRegular.seal, tone: AppColors.warningDeep, bg: AppColors.tintAmber, title: 'Payment received', sub: 'Milestone payment cleared', time: '2 days ago'),
      ActivityItem(icon: PhosphorIconsRegular.handshake, tone: AppColors.textMuted2, bg: AppColors.bgChipGrey, title: 'Converted to customer', sub: 'Won lead · assigned to ${owner.name}', time: cust.since),
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

  Widget _bottomBar(Customer cust) {
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
              onTap: () => ref.read(toastProvider.notifier).show('Calling ${cust.name.split(' ').first}…'),
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
          _squareAction(PhosphorIconsBold.notePencil, AppColors.white, () => ref.read(toastProvider.notifier).show('Add a note'), border: const Color(0xFFB9C2D8), borderWidth: 1.5),
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
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(13.r),
          border: Border.all(color: border, width: borderWidth),
        ),
        child: Icon(icon, size: 22.sp, color: AppColors.navy),
      ),
    );
  }
}
