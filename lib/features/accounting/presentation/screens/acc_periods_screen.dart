import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/money_format.dart' show formatApiDay;
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../crm/presentation/components/crm_detail_parts.dart';
import '../../../crm/presentation/components/finance_widgets.dart';
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/reports_providers.dart';
import '../../domain/entities/acc_periods.dart';
import '../../domain/entities/acc_reports.dart';
import '../components/acc_widgets.dart';
import '../config/accounting_copy.dart';

const _webNote = 'Settle GST, deposit TDS and close periods on the web app.';

/// Periods (plan §4.11) — the register for the current fiscal year, read-only:
/// book months, GST return periods and TDS quarters. Tapping a GST or TDS
/// period shows its checklist and summary.
class AccPeriodsScreen extends ConsumerStatefulWidget {
  const AccPeriodsScreen({super.key});

  @override
  ConsumerState<AccPeriodsScreen> createState() => _AccPeriodsScreenState();
}

class _AccPeriodsScreenState extends ConsumerState<AccPeriodsScreen> {
  int _tab = 1;

  static const _tabs = ['Books', 'GST', 'TDS'];

  @override
  Widget build(BuildContext context) {
    final canRead = ref.watch(accPermProvider('acc_period')).read;
    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(section: 'Periods', onBack: () => context.pop()),
          Expanded(
            child: AccountingGate(
              child: !canRead
                  ? ListView(children: const [
                      EmptyState(
                        icon: PhosphorIconsRegular.lock,
                        title: 'No access',
                        body: 'Your role cannot see accounting periods.',
                      ),
                    ])
                  : _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final async = ref.watch(periodRegisterProvider);
    return AppRefresh(
      onRefresh: () async {
        ref.invalidate(periodRegisterProvider);
        await settle([ref.read(periodRegisterProvider.future)]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 32.h),
        children: async.when(
          skipLoadingOnRefresh: true,
          loading: () => [const DetailSkeleton()],
          error: (e, _) => [
            ErrorState.forError(
              e is AppError ? e : const AppError(type: AppErrorType.unknown, message: 'Could not load periods.'),
              onRetry: () => ref.invalidate(periodRegisterProvider),
            ),
          ],
          data: (reg) => [
            FinanceCard(
              child: Row(
                children: [
                  const IconChip(icon: PhosphorIconsRegular.calendarBlank, size: 46, radius: 13, iconSize: 22),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Financial year', style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                        SizedBox(height: 2.h),
                        Text(reg.fyLabel ?? '—',
                            style: AppText.custom(size: 18, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                      ],
                    ),
                  ),
                  if (reg.status != null) AccPill(StatusMeta$.accPeriod, reg.status!),
                ],
              ),
            ),
            SizedBox(height: 14.h),
            ClozrCard(
              radius: 18,
              padding: EdgeInsets.fromLTRB(18.w, 12.h, 18.w, 6.h),
              child: DetailUnderlineTabs(labels: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i)),
            ),
            SizedBox(height: 14.h),
            switch (_tab) {
              0 => _books(reg.bookPeriods),
              1 => _gst(reg.gstPeriods),
              _ => _tds(reg.tdsPeriods),
            },
            SizedBox(height: 14.h),
            const AccInfoBanner(_webNote, icon: PhosphorIconsRegular.desktop),
          ],
        ),
      ),
    );
  }

  String _range(String? s, String? e) => '${formatApiDay(s)} – ${formatApiDay(e)}';

  Widget _books(List<BookPeriod> periods) {
    if (periods.isEmpty) return _empty('No book periods');
    return FinanceCard(
      title: 'Book months',
      child: Column(
        children: [
          for (int i = 0; i < periods.length; i++)
            _row(
              title: periods[i].periodNo == null ? 'Period' : 'Period ${periods[i].periodNo}',
              sub: _range(periods[i].startDate, periods[i].endDate),
              pills: [AccPill(StatusMeta$.accPeriod, periods[i].status)],
              last: i == periods.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _gst(List<GstPeriod> periods) {
    if (periods.isEmpty) return _empty('No GST periods');
    return FinanceCard(
      title: 'GST returns',
      child: Column(
        children: [
          for (int i = 0; i < periods.length; i++)
            _row(
              title: _range(periods[i].startDate, periods[i].endDate),
              sub: periods[i].gstin ?? '',
              pills: [
                _labelled('GSTR-1', periods[i].gstr1Status),
                _labelled('3B', periods[i].gstr3bStatus),
                if (periods[i].settled) const StatusPill(label: 'Settled', color: AppColors.navy),
              ],
              onTap: () => _gstSheet(periods[i]),
              last: i == periods.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _tds(List<TdsPeriod> periods) {
    if (periods.isEmpty) return _empty('No TDS quarters');
    return FinanceCard(
      title: 'TDS quarters',
      child: Column(
        children: [
          for (int i = 0; i < periods.length; i++)
            _row(
              title: periods[i].quarter == null ? 'Quarter' : 'Q${periods[i].quarter}',
              sub: _range(periods[i].startDate, periods[i].endDate),
              pills: [AccPill(StatusMeta$.accPeriod, periods[i].status)],
              onTap: ref.watch(accPermProvider('acc_report')).read ? () => _tdsSheet(periods[i]) : null,
              last: i == periods.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _labelled(String prefix, String status) {
    final meta = StatusMeta$.accPeriod[status] ?? StatusMeta(label(const {}, status), AppColors.textMuted);
    return StatusPill(label: '$prefix ${meta.label}', color: meta.color);
  }

  Widget _empty(String title) => DetailTabEmpty(
        icon: PhosphorIconsRegular.calendarBlank,
        title: title,
        body: 'Periods are created when accounting is activated.',
      );

  Widget _row({
    required String title,
    required String sub,
    required List<Widget> pills,
    VoidCallback? onTap,
    bool last = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 11.h),
        decoration: last ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                  if (sub.isNotEmpty) ...[
                    SizedBox(height: 2.h),
                    Text(sub, style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
                  ],
                  SizedBox(height: 6.h),
                  Wrap(spacing: 6.w, runSpacing: 6.h, children: pills),
                ],
              ),
            ),
            if (onTap != null) Icon(PhosphorIconsBold.caretRight, size: 13.sp, color: AppColors.textPlaceholder),
          ],
        ),
      ),
    );
  }

  void _gstSheet(GstPeriod p) => showClozrSheet<void>(
        context: context,
        builder: (_) => _GstPeriodSheet(period: p),
      );

  void _tdsSheet(TdsPeriod p) => showClozrSheet<void>(
        context: context,
        builder: (_) => _TdsPeriodSheet(period: p),
      );
}

/// A GST period's checklist and, for report readers, its summary.
class _GstPeriodSheet extends ConsumerWidget {
  const _GstPeriodSheet({required this.period});
  final GstPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checklist = ref.watch(gstChecklistProvider(period.id));
    final canReport = ref.watch(accPermProvider('acc_report')).read;
    final summary = canReport ? ref.watch(gstSummaryProvider(period.id)) : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'GST ${formatApiDay(period.startDate)} – ${formatApiDay(period.endDate)}'),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 24.h),
            children: [
              ...checklist.when(
                loading: () => [_spinner()],
                error: (e, _) => [_error(e)],
                data: (c) => [_checklistCard(c)],
              ),
              if (summary != null) ...[
                SizedBox(height: 12.h),
                ...summary.when(
                  loading: () => [_spinner()],
                  error: (e, _) => [_error(e)],
                  data: (s) => [_summaryCard(s)],
                ),
              ],
              SizedBox(height: 12.h),
              const AccInfoBanner(_webNote, icon: PhosphorIconsRegular.desktop),
            ],
          ),
        ),
      ],
    );
  }

  Widget _checklistCard(PeriodChecklist c) {
    return FinanceCard(
      title: 'Checklist',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 4.h),
          StatusPill(
            label: c.canSettle ? 'Ready to settle' : 'Not ready to settle',
            color: c.canSettle ? AppColors.success : AppColors.warningDeep,
          ),
          SizedBox(height: 4.h),
          if (c.items.isEmpty)
            Padding(padding: EdgeInsets.only(top: 8.h), child: Text('No checks', style: AppText.caption())),
          for (int i = 0; i < c.items.length; i++) _item(c.items[i], i == c.items.length - 1),
        ],
      ),
    );
  }

  Widget _item(ChecklistItem it, bool last) {
    final (icon, color) = it.passed
        ? (PhosphorIconsFill.checkCircle, AppColors.success)
        : switch (it.severity) {
            'BLOCK' => (PhosphorIconsFill.xCircle, AppColors.error),
            'WARN' => (PhosphorIconsFill.warning, AppColors.warningDeep),
            _ => (PhosphorIconsFill.info, AppColors.blueBright),
          };
    return Container(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      decoration: last ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18.sp, color: color),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.label ?? label(const {}, it.code),
                    style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                if ((it.detail ?? '').isNotEmpty) ...[
                  SizedBox(height: 2.h),
                  Text(it.detail!, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted, height: 1.4)),
                ],
              ],
            ),
          ),
          if (!it.passed && it.severity == 'BLOCK') ...[
            SizedBox(width: 8.w),
            const StatusPill(label: 'Blocking', color: AppColors.error),
          ],
        ],
      ),
    );
  }

  /// `grand_totals` rendered as the server sends it — one group per section,
  /// head → amount. No output-minus-input figure: the section names are the
  /// server's and are not documented, so the app does not guess at a netting.
  Widget _summaryCard(GstSummary s) {
    if (s.grandTotals.isEmpty) {
      return FinanceCard(title: 'Summary', child: Text('Nothing recorded for this period.', style: AppText.caption()));
    }
    return FinanceCard(
      title: 'Summary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final section in s.grandTotals.entries) ...[
            Padding(
              padding: EdgeInsets.only(top: 10.h, bottom: 2.h),
              child: Text(label(const {}, section.key).toUpperCase(),
                  style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textPlaceholder, letterSpacing: 0.4)),
            ),
            for (final head in section.value.entries)
              MoneyRow(label: label(const {}, head.key), value: head.value, last: head.key == section.value.keys.last),
          ],
        ],
      ),
    );
  }
}

/// A TDS quarter's summary by nature.
class _TdsPeriodSheet extends ConsumerWidget {
  const _TdsPeriodSheet({required this.period});
  final TdsPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tdsSummaryProvider(period.id));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: 'TDS ${period.quarter == null ? '' : 'Q${period.quarter}'}'.trim()),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 24.h),
            children: [
              ...async.when(
                loading: () => [_spinner()],
                error: (e, _) => [_error(e)],
                data: (s) => [
                  if (s.rows.isEmpty)
                    FinanceCard(child: Text('No TDS deducted in this quarter.', style: AppText.caption()))
                  else
                    for (final r in s.rows) ...[
                      FinanceCard(
                        title: tdsNatures[r.natureKey] ?? label(const {}, r.natureKey),
                        child: Column(
                          children: [
                            MoneyRow(label: 'Deducted', value: r.deducted),
                            MoneyRow(label: 'Deposited', value: r.deposited),
                            MoneyRow(label: 'Pending', value: r.pending, last: true),
                          ],
                        ),
                      ),
                      SizedBox(height: 10.h),
                    ],
                  if (s.totals.isNotEmpty)
                    FinanceCard(
                      title: 'Total',
                      child: Column(
                        children: [
                          MoneyRow(label: 'Deducted', value: s.totals['deducted']),
                          MoneyRow(label: 'Deposited', value: s.totals['deposited']),
                          MoneyRow(label: 'Pending', value: s.totals['pending'], last: true),
                        ],
                      ),
                    ),
                ],
              ),
              SizedBox(height: 12.h),
              const AccInfoBanner(_webNote, icon: PhosphorIconsRegular.desktop),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _spinner() => SizedBox(
      height: 90.h,
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.navy)),
    );

Widget _error(Object e) => ErrorState.forError(
      e is AppError ? e : const AppError(type: AppErrorType.unknown, message: 'Could not load.'),
    );
