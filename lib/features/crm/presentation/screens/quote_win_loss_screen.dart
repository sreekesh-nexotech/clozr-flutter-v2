import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/tab_chip.dart';
import '../../domain/entities/quote_win_loss.dart';
import '../components/crm_async.dart';

/// The report for one created-date range ('' bounds = open-ended). The server
/// caches it for 90 s; every figure on the screen comes from here.
final quoteWinLossReportProvider =
    FutureProvider.autoDispose.family<WinLossReport, ({String from, String to})>((ref, range) async {
  final body = await ref
      .read(apiServiceProvider)
      .get('/quotations/quotations/win-loss-report/', query: winLossQuery(range.from, range.to));
  return WinLossReport.fromJson(body);
});

enum _Grouping {
  owner('By owner', 'Unassigned'),
  product('By product', 'Unknown product'),
  source('By source', 'No source');

  const _Grouping(this.label, this.emptyName);
  final String label;
  final String emptyName;
}

/// Webapp `WinLossReportScreen` (Quotes › Win / loss report): a created-date
/// range, the summary figures, and breakdowns by owner / product / lead source
/// — the webapp's table rows become cards. No owner/team filter and no export,
/// matching the webapp.
class QuoteWinLossScreen extends ConsumerStatefulWidget {
  const QuoteWinLossScreen({super.key});

  @override
  ConsumerState<QuoteWinLossScreen> createState() => _QuoteWinLossScreenState();
}

class _QuoteWinLossScreenState extends ConsumerState<QuoteWinLossScreen> {
  /// Typed dates settle before refetching (webapp: 450 ms).
  static const _debounce = Duration(milliseconds: 450);

  WinLossPreset _preset = WinLossPreset.last90;
  final _fromCtl = TextEditingController();
  final _toCtl = TextEditingController();
  String _from = '';
  String _to = '';
  Timer? _timer;
  _Grouping _grouping = _Grouping.owner;

  /// The last report shown — kept on screen while a new range loads.
  WinLossReport? _last;

  @override
  void initState() {
    super.initState();
    final r = winLossPresetRange(_preset, DateTime.now());
    _fromCtl.text = _from = r.from;
    _toCtl.text = _to = r.to;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fromCtl.dispose();
    _toCtl.dispose();
    super.dispose();
  }

  void _applyPreset(WinLossPreset p) {
    _timer?.cancel();
    final r = winLossPresetRange(p, DateTime.now());
    setState(() {
      _preset = p;
      _fromCtl.text = _from = r.from;
      _toCtl.text = _to = r.to;
    });
  }

  void _typed() {
    if (_preset != WinLossPreset.custom) setState(() => _preset = WinLossPreset.custom);
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      if (!mounted) return;
      setState(() {
        _from = _fromCtl.text.trim();
        _to = _toCtl.text.trim();
      });
    });
  }

  Future<void> _pick(TextEditingController ctl) async {
    final current = DateTime.tryParse(ctl.text.trim());
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    _timer?.cancel();
    setState(() {
      ctl.text = isoDay(picked);
      _preset = WinLossPreset.custom;
      _from = _fromCtl.text.trim();
      _to = _toCtl.text.trim();
    });
  }

  ({String from, String to}) get _range {
    // Like the webapp, an invalid range is not sent — the request goes out open-ended.
    final invalid = winLossRangeError(_from, _to) != null;
    return (from: invalid ? '' : _from, to: invalid ? '' : _to);
  }

  @override
  Widget build(BuildContext context) {
    final range = _range;
    final async = ref.watch(quoteWinLossReportProvider(range));
    final report = async.valueOrNull ?? (async.isLoading ? _last : null);
    if (async.hasValue) _last = async.value;

    final Widget body;
    if (async.hasError && !async.isLoading) {
      body = Padding(
        padding: EdgeInsets.only(top: 24.h),
        child: ErrorState.forError(crmAppError(async.error!),
            onRetry: () => ref.invalidate(quoteWinLossReportProvider(range))),
      );
    } else if (report == null) {
      body = ListSkeleton(
        itemCount: 2,
        itemHeight: 160,
        padding: EdgeInsets.zero,
      );
    } else if (report.summary.total == 0) {
      body = const EmptyState(
        icon: PhosphorIconsRegular.chartBar,
        title: 'No quotes in this range',
        body: 'Widen the date range to see how quotes were won and lost.',
      );
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _SummaryCard(metrics: report.summary),
        SizedBox(height: 16.h),
        _breakdown(report),
      ]);
    }

    return Container(
      color: AppColors.bgDetail,
      child: Column(children: [
        DetailAppBar(section: 'Quotes', name: 'Win / loss report', onBack: () => context.pop()),
        if (async.isLoading && report != null) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(quoteWinLossReportProvider(range)),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 28.h),
              children: [
                _filters(),
                SizedBox(height: 16.h),
                body,
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ── range ──────────────────────────────────────────────────────────────────

  Widget _filters() {
    final error = winLossRangeError(_from, _to);
    return ClozrCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Quotes created', style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
        SizedBox(height: 8.h),
        TabChipRow(children: [
          for (final p in WinLossPreset.quick)
            TabChip(label: p.label, active: _preset == p, onTap: () => _applyPreset(p)),
        ]),
        SizedBox(height: 14.h),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _dateField('From', _fromCtl)),
          SizedBox(width: 12.w),
          Expanded(child: _dateField('To', _toCtl)),
        ]),
        if (error != null) ...[
          SizedBox(height: 6.h),
          Text(error, style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.error)),
        ],
      ]),
    );
  }

  Widget _dateField(String label, TextEditingController ctl) {
    return Stack(children: [
      AppTextField(
        label: label,
        controller: ctl,
        hint: 'YYYY-MM-DD',
        keyboardType: TextInputType.datetime,
        suffixIcon: PhosphorIconsRegular.calendarBlank,
        onChanged: (_) => _typed(),
      ),
      // The calendar icon opens a picker; the box itself stays typeable.
      Positioned(
        right: 0,
        bottom: 0,
        width: 40.w,
        height: 44.h,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _pick(ctl),
          child: Semantics(button: true, label: 'Pick $label date'),
        ),
      ),
    ]);
  }

  // ── breakdown ──────────────────────────────────────────────────────────────

  Widget _breakdown(WinLossReport report) {
    final rows = switch (_grouping) {
      _Grouping.owner => report.byOwner,
      _Grouping.product => report.byProduct,
      _Grouping.source => report.bySource,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TabChipRow(children: [
        for (final g in _Grouping.values)
          TabChip(label: g.label, active: _grouping == g, onTap: () => setState(() => _grouping = g)),
      ]),
      SizedBox(height: 12.h),
      if (rows.isEmpty)
        ClozrCard(
          child: Text(
            _grouping == _Grouping.product ? 'No catalog products on these quotes.' : 'Nothing to break down.',
            style: AppText.body(color: AppColors.textMuted),
          ),
        )
      else
        for (final r in rows) _GroupCard(row: r, name: r.name.isEmpty ? _grouping.emptyName : r.name),
      SizedBox(height: 4.h),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 2.w),
        child: Text(
          'Win rate = won ÷ (won + lost + expired). Won value is before GST.'
          '${_grouping == _Grouping.product ? ' A quote with several products counts once under each; value is the line amount.' : ''}',
          style: AppText.caption(),
        ),
      ),
    ]);
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.metrics});
  final WinLossMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return ClozrCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: _Figure(label: 'Win rate', value: winRateLabel(m.winRate), color: AppColors.navy, big: true)),
          Expanded(child: _Figure(label: 'Won value', value: formatMoneyStr(m.wonValue), big: true, alignEnd: true)),
        ]),
        SizedBox(height: 14.h),
        const ClozrDivider(),
        SizedBox(height: 14.h),
        Row(children: [
          Expanded(child: _Figure(label: 'Quotes', value: '${m.total}')),
          Expanded(child: _Figure(label: 'Won', value: '${m.won}', color: m.won > 0 ? AppColors.success : null)),
          Expanded(child: _Figure(label: 'Lost', value: '${m.lost}', color: m.lost > 0 ? AppColors.error : null)),
        ]),
        SizedBox(height: 14.h),
        Row(children: [
          Expanded(child: _Figure(label: 'Expired', value: '${m.expired}')),
          Expanded(child: _Figure(label: 'Open', value: '${m.open}')),
          const Expanded(child: SizedBox.shrink()),
        ]),
        SizedBox(height: 14.h),
        Row(children: [
          Expanded(child: _Figure(label: 'Avg. time to accept', value: daysLabel(m.avgDaysToAccept))),
          Expanded(child: _Figure(label: 'Avg. discount', value: discountLabel(m.avgDiscountPct))),
        ]),
      ]),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.color, this.big = false, this.alignEnd = false});
  final String label;
  final String value;
  final Color? color;
  final bool big;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: AppText.custom(size: 10.5, weight: FontWeight.w700, color: AppColors.textPlaceholder)),
        SizedBox(height: 4.h),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: big
                ? AppText.statNumber(color: color ?? AppColors.textPrimary)
                : AppText.custom(size: 16, weight: FontWeight.w800, color: color ?? AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

/// One breakdown row (a webapp table row) as a card.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.row, required this.name});
  final WinLossGroupRow row;
  final String name;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value, {Color? color, bool strong = false}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppText.micro()),
            SizedBox(height: 2.h),
            Text(value,
                style: AppText.custom(
                  size: 13.5,
                  weight: strong || color != null ? FontWeight.w700 : FontWeight.w500,
                  color: color ?? AppColors.textBody,
                )),
          ]),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: ClozrCard(
        radius: 14,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(name, style: AppText.bodyStrong())),
            SizedBox(width: 10.w),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatMoneyStr(row.wonValue), style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.navy)),
              Text('Won value', style: AppText.micro()),
            ]),
          ]),
          SizedBox(height: 10.h),
          Row(children: [
            stat('Quotes', '${row.total}'),
            stat('Won', '${row.won}', color: row.won > 0 ? AppColors.success : null),
            stat('Lost', '${row.lost}', color: row.lost > 0 ? AppColors.error : null),
            stat('Expired', '${row.expired}'),
            stat('Open', '${row.open}'),
          ]),
          SizedBox(height: 10.h),
          Row(children: [
            stat('Win rate', winRateLabel(row.winRate), color: AppColors.textPrimary),
            stat('Avg. time to accept', daysLabel(row.avgDaysToAccept)),
            stat('Avg. discount', discountLabel(row.avgDiscountPct)),
          ]),
        ]),
      ),
    );
  }
}
