import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../crm/application/providers/crm_party_providers.dart';
import '../../../crm/presentation/components/finance_widgets.dart';
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/reports_providers.dart';
import '../../application/providers/settlement_providers.dart';
import '../../domain/entities/acc_reports.dart';
import '../components/acc_widgets.dart';
import '../config/accounting_copy.dart';

const _titles = <String, String>{
  'ar_aging': 'Receivable aging',
  'ap_aging': 'Payable aging',
  'pnl': 'Profit & loss',
  'balance_sheet': 'Balance sheet',
  'trial_balance': 'Trial balance',
  'customer_statement': 'Statement',
  'vendor_statement': 'Statement',
};

/// One report (plan §4.12), picked by `?kind=` — read-only, no export.
///
/// Every date sent is built by [isoDay]: report parameters are not validated
/// server-side, and a malformed one is a 500 (handover §12.6).
class AccReportScreen extends ConsumerStatefulWidget {
  const AccReportScreen({super.key});

  @override
  ConsumerState<AccReportScreen> createState() => _AccReportScreenState();
}

class _AccReportScreenState extends ConsumerState<AccReportScreen> {
  DateTime _asOf = DateTime.now();
  late DateTime _from = _fyStart(DateTime.now());
  DateTime _to = DateTime.now();

  /// 1 April of the Indian fiscal year [d] falls in.
  static DateTime _fyStart(DateTime d) => DateTime(d.month >= 4 ? d.year : d.year - 1, 4, 1);

  String get _kind => GoRouterState.of(context).uri.queryParameters['kind'] ?? 'ar_aging';
  String get _party => GoRouterState.of(context).uri.queryParameters['party'] ?? '';

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    String? partyName;
    if (kind == 'customer_statement') {
      partyName = ref.watch(crmPartyLookupProvider)(custId: _party)?.name;
    } else if (kind == 'vendor_statement') {
      partyName = ref.watch(vendorNameProvider)(_party);
    }
    final canRead = ref.watch(accPermProvider('acc_report')).read;
    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(section: _titles[kind] ?? 'Report', name: partyName, onBack: () => context.pop()),
          Expanded(
            child: AccountingGate(
              child: !canRead
                  ? ListView(children: const [
                      EmptyState(
                        icon: PhosphorIconsRegular.lock,
                        title: 'No access',
                        body: 'Your role cannot see accounting reports.',
                      ),
                    ])
                  : _body(kind),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(String kind) {
    switch (kind) {
      case 'ar_aging':
      case 'ap_aging':
        final vendor = kind == 'ap_aging';
        final p = vendor ? apAgingProvider : arAgingProvider;
        return _async<AgingReport>(ref.watch(p), () => ref.invalidate(p), (r) => _aging(r, vendor));
      case 'pnl':
        final p = pnlProvider(isoDay(_asOf));
        return _async<PnlReport>(ref.watch(p), () => ref.invalidate(p), _pnl, header: _asOfBox());
      case 'balance_sheet':
        final p = balanceSheetProvider(isoDay(_asOf));
        return _async<BalanceSheetReport>(ref.watch(p), () => ref.invalidate(p), _bs, header: _asOfBox());
      case 'trial_balance':
        final p = trialBalanceProvider(isoDay(_asOf));
        return _async<TrialBalanceReport>(ref.watch(p), () => ref.invalidate(p), _tb, header: _asOfBox());
      case 'customer_statement':
      case 'vendor_statement':
        if (_party.isEmpty) {
          return ListView(children: const [
            EmptyState(icon: PhosphorIconsRegular.userCircle, title: 'No party', body: 'Open a statement from a customer or vendor.'),
          ]);
        }
        final p = statementProvider(
            (vendor: kind == 'vendor_statement', partyId: _party, from: isoDay(_from), to: isoDay(_to)));
        return _async<PartyStatement>(ref.watch(p), () => ref.invalidate(p), _statement, header: _rangeBox());
      default:
        return ListView(children: const [
          EmptyState(icon: PhosphorIconsRegular.question, title: 'Unknown report', body: 'This report does not exist.'),
        ]);
    }
  }

  /// Loading / error / data, with an optional control strip above that stays
  /// put while the report reloads.
  Widget _async<T>(AsyncValue<T> value, VoidCallback retry, List<Widget> Function(T) data, {Widget? header}) {
    Future<void> refresh() async => retry();
    final pad = EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 32.h);
    return AppRefresh(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pad,
        children: [
          if (header != null) ...[header, SizedBox(height: 14.h)],
          ...value.when(
            skipLoadingOnRefresh: true,
            loading: () => [const DetailSkeleton()],
            error: (e, _) => [
              ErrorState.forError(
                e is AppError ? e : const AppError(type: AppErrorType.unknown, message: 'Could not load the report.'),
                onRetry: retry,
              ),
            ],
            data: data,
          ),
        ],
      ),
    );
  }

  Widget _asOfBox() => AccDateBox(
        label: 'As of',
        value: _asOf,
        showIstHint: true,
        onChanged: (d) => setState(() => _asOf = d ?? _asOf),
      );

  Widget _rangeBox() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: AccDateBox(label: 'From', value: _from, onChanged: (d) => setState(() => _from = d ?? _from))),
          SizedBox(width: 9.w),
          Expanded(child: AccDateBox(label: 'To', value: _to, onChanged: (d) => setState(() => _to = d ?? _to))),
        ],
      );

  // ── Aging ──

  List<Widget> _aging(AgingReport r, bool vendor) {
    final lookup = ref.watch(crmPartyLookupProvider);
    final vendorName = ref.watch(vendorNameProvider);
    return [
      FinanceCard(
        title: vendor ? 'You owe' : 'Owed to you',
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6.h),
              child: Row(
                children: [
                  Expanded(child: Text('Total', style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary))),
                  Text(formatMoneyStr(r.grandTotal),
                      style: AppText.custom(size: 18, weight: FontWeight.w800, color: AppColors.textPrimary)),
                ],
              ),
            ),
            for (int i = 0; i < agingBuckets.length; i++)
              MoneyRow(label: '${agingBuckets[i]} days', value: r.totals[agingBuckets[i]] ?? '0', last: i == agingBuckets.length - 1),
            if (r.asOf != null) ...[
              SizedBox(height: 6.h),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('As of ${formatApiDay(r.asOf)}', style: AppText.micro()),
              ),
            ],
          ],
        ),
      ),
      SizedBox(height: 14.h),
      if (r.rows.isEmpty)
        EmptyState(
          icon: PhosphorIconsRegular.checkCircle,
          title: 'Nothing outstanding',
          body: vendor ? 'No vendor has an open bill.' : 'No customer owes anything.',
        )
      else
        for (final row in r.rows) ...[
          _agingRow(row, vendor,
              row.partyName ?? (vendor ? vendorName(row.partyId) : lookup(custId: row.partyId)?.name) ?? 'Party'),
          SizedBox(height: 10.h),
        ],
    ];
  }

  Widget _agingRow(AgingRow row, bool vendor, String name) {
    final chips = [for (final b in agingBuckets) if (!moneyIsZero(row.buckets[b])) b];
    return ClozrCard(
      radius: 14,
      padding: EdgeInsets.all(13.r),
      onTap: () => context.push(
          '${Routes.accReport}?kind=${vendor ? 'vendor_statement' : 'customer_statement'}&party=${row.partyId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              Text(formatMoneyStr(row.total), style: AppText.custom(size: 15, weight: FontWeight.w800, color: AppColors.textPrimary)),
            ],
          ),
          if (chips.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Wrap(
              spacing: 6.w,
              runSpacing: 6.h,
              children: [
                for (final b in chips)
                  StatusPill(
                    label: '$b · ${formatMoneyCompact(row.buckets[b])}',
                    color: b == '90+' ? AppColors.error : (b == '61-90' ? AppColors.warningDeep : AppColors.textMuted),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── P&L ──

  List<Widget> _pnl(PnlReport r) => [
        _Section(title: 'Income', total: r.totalIncome, accounts: r.income),
        SizedBox(height: 12.h),
        _Section(title: 'Expenses', total: r.totalExpense, accounts: r.expense),
        SizedBox(height: 12.h),
        FinanceCard(
          child: Row(
            children: [
              Expanded(child: Text('Net profit', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary))),
              Text(formatMoneyStr(r.netProfit),
                  style: AppText.custom(
                      size: 18,
                      weight: FontWeight.w800,
                      color: moneyNum(r.netProfit) < 0 ? AppColors.error : AppColors.success)),
            ],
          ),
        ),
      ];

  // ── Balance sheet ──

  List<Widget> _bs(BalanceSheetReport r) => [
        Align(alignment: Alignment.centerLeft, child: _balancedPill(r.balanced)),
        SizedBox(height: 12.h),
        _Section(title: 'Assets', total: r.totalAssets, accounts: r.assets),
        SizedBox(height: 12.h),
        _Section(title: 'Liabilities', total: r.totalLiabilities, accounts: r.liabilities),
        SizedBox(height: 12.h),
        _Section(title: 'Equity', total: r.totalEquity, accounts: r.equity),
        SizedBox(height: 12.h),
        FinanceCard(
          child: Column(
            children: [
              MoneyRow(label: 'Net profit', value: r.netProfit),
              MoneyRow(label: 'Total assets', value: r.totalAssets),
              MoneyRow(label: 'Liabilities + equity', value: r.liabilitiesAndEquity, last: true),
            ],
          ),
        ),
      ];

  // ── Trial balance ──

  List<Widget> _tb(TrialBalanceReport r) => [
        Align(alignment: Alignment.centerLeft, child: _balancedPill(r.balanced)),
        SizedBox(height: 12.h),
        for (final g in r.groups) ...[
          _TbGroup(group: g),
          SizedBox(height: 12.h),
        ],
        FinanceCard(
          child: Column(
            children: [
              MoneyRow(label: 'Total debit', value: r.totalDebit),
              MoneyRow(label: 'Total credit', value: r.totalCredit, last: true),
            ],
          ),
        ),
      ];

  Widget _balancedPill(bool ok) =>
      StatusPill(label: ok ? 'Balanced' : 'Does not balance', color: ok ? AppColors.success : AppColors.error);

  // ── Statement ──

  List<Widget> _statement(PartyStatement s) => [
        FinanceCard(
          child: Column(
            children: [
              MoneyRow(label: 'Opening balance', value: s.openingBalance),
              MoneyRow(label: 'Debits', value: s.totalDebit),
              MoneyRow(label: 'Credits', value: s.totalCredit),
              MoneyRow(label: 'Closing balance', value: s.closingBalance, last: true),
            ],
          ),
        ),
        SizedBox(height: 14.h),
        if (s.lines.isEmpty)
          const EmptyState(
            icon: PhosphorIconsRegular.listDashes,
            title: 'No entries',
            body: 'Nothing was billed or paid in this period.',
          )
        else
          FinanceCard(
            title: 'Entries',
            child: Column(
              children: [
                for (int i = 0; i < s.lines.length; i++) _stmtLine(s.lines[i], i == s.lines.length - 1),
              ],
            ),
          ),
      ];

  Widget _stmtLine(StatementLine l, bool last) {
    final opens = l.kind == 'DOCUMENT' && (l.refId ?? '').isNotEmpty;
    final debit = !moneyIsZero(l.debit);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: opens ? () => context.push('${Routes.accDocumentDetail}?id=${l.refId}') : null,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10.h),
        decoration: last ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.reference ?? label(docTypeLabels, l.docType ?? l.kind),
                      style: AppText.custom(
                          size: 13.5, weight: FontWeight.w700, color: opens ? AppColors.blueBright : AppColors.textPrimary)),
                  SizedBox(height: 2.h),
                  Text(
                    [formatApiDay(l.date), if (l.docType != null) label(docTypeLabels, l.docType) else label(const {}, l.kind)]
                        .join(' · '),
                    style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder),
                  ),
                ],
              ),
            ),
            SizedBox(width: 10.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${debit ? '+' : '−'} ${formatMoneyStr(debit ? l.debit : l.credit)}',
                    style: AppText.custom(size: 13, weight: FontWeight.w800, color: debit ? AppColors.textPrimary : AppColors.success)),
                SizedBox(height: 2.h),
                Text('Bal ${formatMoneyStr(l.balance)}',
                    style: AppText.custom(size: 11.5, weight: FontWeight.w600, color: AppColors.textMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A collapsible report section: title and total, accounts underneath.
class _Section extends StatefulWidget {
  const _Section({required this.title, required this.total, required this.accounts});

  final String title;
  final String total;
  final List<ReportAccount> accounts;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    return FinanceCard(
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.title,
                      style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
                Text(formatMoneyStr(widget.total),
                    style: AppText.custom(size: 15, weight: FontWeight.w800, color: AppColors.textPrimary)),
                SizedBox(width: 6.w),
                Icon(_open ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown,
                    size: 12.sp, color: AppColors.textPlaceholder),
              ],
            ),
          ),
          if (_open) ...[
            SizedBox(height: 4.h),
            if (widget.accounts.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8.h),
                child: Align(alignment: Alignment.centerLeft, child: Text('No accounts', style: AppText.caption())),
              ),
            for (int i = 0; i < widget.accounts.length; i++)
              MoneyRow(
                label: [if (widget.accounts[i].code != null) widget.accounts[i].code!, widget.accounts[i].name].join(' · '),
                value: widget.accounts[i].amount,
                last: i == widget.accounts.length - 1,
              ),
          ],
        ],
      ),
    );
  }
}

/// A trial balance bucket: its totals, expandable to closing balances.
class _TbGroup extends StatefulWidget {
  const _TbGroup({required this.group});
  final TrialBalanceGroup group;

  @override
  State<_TbGroup> createState() => _TbGroupState();
}

class _TbGroupState extends State<_TbGroup> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    TextStyle num(Color c) => AppText.custom(size: 12.5, weight: FontWeight.w700, color: c);
    return FinanceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                Expanded(
                  child: Text(label(const {}, g.bucket),
                      style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
                Icon(_open ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown,
                    size: 12.sp, color: AppColors.textPlaceholder),
              ],
            ),
          ),
          SizedBox(height: 4.h),
          MoneyRow(label: 'Debit', value: g.debit),
          MoneyRow(label: 'Credit', value: g.credit, last: !_open),
          if (_open)
            for (final a in g.accounts)
              Container(
                padding: EdgeInsets.symmetric(vertical: 8.h),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF3F4F5)))),
                child: Row(
                  children: [
                    Expanded(
                      child: Text([if (a.code != null) a.code!, a.name].join(' · '),
                          style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textBody)),
                    ),
                    SizedBox(
                      width: 84.w,
                      child: Text(moneyIsZero(a.closingDebit) ? '' : formatMoneyStr(a.closingDebit),
                          textAlign: TextAlign.right, style: num(AppColors.textPrimary)),
                    ),
                    SizedBox(
                      width: 84.w,
                      child: Text(moneyIsZero(a.closingCredit) ? '' : formatMoneyStr(a.closingCredit),
                          textAlign: TextAlign.right, style: num(AppColors.textMuted)),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
