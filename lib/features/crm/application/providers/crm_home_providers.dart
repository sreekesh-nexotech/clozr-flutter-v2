import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../operations/application/providers/projects_providers.dart'
    show opsModuleReadable;
import '../../domain/entities/crm_home_models.dart';
import '../../infrastructure/data_sources/remote/crm_home_remote_ds.dart';
import '../../infrastructure/repositories/crm_home_repository.dart';

export '../../domain/entities/crm_home_models.dart'
    show WinRow, OverdueRow, CrmHomeData;

/// The dashboard Period selector (webapp `toApiPeriod`): API value + label.
enum CrmPeriod {
  thisMonth('this_month', 'This month'),
  lastMonth('last_month', 'Last month'),
  thisQuarter('this_quarter', 'This quarter'),
  ytd('ytd', 'Year to date'),
  last30('last_30_days', 'Last 30 days'),
  last90('last_90_days', 'Last 90 days'),
  custom('custom', 'Custom range');

  const CrmPeriod(this.api, this.label);
  final String api;
  final String label;

  /// Query params for the widgets. This month is the server's default, so it
  /// sends nothing; a custom range sends its inclusive `from` / `to`.
  Map<String, dynamic> query(DateTimeRange? range) {
    if (this == thisMonth) return const {};
    if (this == custom) {
      if (range == null) return const {};
      String d(DateTime t) =>
          '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
      return {'period': api, 'from': d(range.start), 'to': d(range.end)};
    }
    return {'period': api};
  }
}

final crmPeriodProvider =
    StateProvider<CrmPeriod>((ref) => CrmPeriod.thisMonth);

/// The concrete dates a Home period covers, for a list link that must count
/// the same leads as the card (`created_at_after` / `before` on the Leads
/// list). Mirrors the server's windows: calendar month / quarter / year to
/// [today], trailing 30 / 90 days including today, or the custom range.
({DateTime from, DateTime to}) crmPeriodRange(CrmPeriod period,
    {DateTimeRange? custom, DateTime? today}) {
  final now = today ?? DateTime.now();
  final t = DateTime(now.year, now.month, now.day);
  switch (period) {
    case CrmPeriod.thisMonth:
      return (from: DateTime(t.year, t.month, 1), to: t);
    case CrmPeriod.lastMonth:
      final first = DateTime(t.year, t.month - 1, 1);
      return (from: first, to: DateTime(t.year, t.month, 0));
    case CrmPeriod.thisQuarter:
      final q0 = ((t.month - 1) ~/ 3) * 3 + 1;
      return (from: DateTime(t.year, q0, 1), to: t);
    case CrmPeriod.ytd:
      return (from: DateTime(t.year, 1, 1), to: t);
    case CrmPeriod.last30:
      return (from: t.subtract(const Duration(days: 29)), to: t);
    case CrmPeriod.last90:
      return (from: t.subtract(const Duration(days: 89)), to: t);
    case CrmPeriod.custom:
      if (custom == null) return (from: DateTime(t.year, t.month, 1), to: t);
      return (from: custom.start, to: custom.end);
  }
}

/// `from=…&to=…` for a Leads link, from the Home's current period.
String crmPeriodQuery(CrmPeriod period, DateTimeRange? custom) {
  final r = crmPeriodRange(period, custom: custom);
  String d(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  return 'from=${d(r.from)}&to=${d(r.to)}';
}

final crmCustomRangeProvider = StateProvider<DateTimeRange?>((ref) => null);

/// Active chip on the Home "Overdue items" module.
final crmOverdueTabProvider = StateProvider<String>((ref) => 'fu');

// ── API-backed source (used only when ApiConfig.apiEnabled) ──

/// DI seam for the CRM Home repository.
final crmHomeRepositoryProvider = Provider<CrmHomeRepository>(
  (ref) =>
      CrmHomeRepository(CrmHomeRemoteDataSource(ref.watch(apiServiceProvider))),
);

/// The personal CRM Home bundle. Watched by the screen **only in API mode**; in
/// mock mode the screen renders the const literals below and never creates this.
final crmHomeProvider = FutureProvider<CrmHomeData>((ref) async {
  final period = ref.watch(crmPeriodProvider);
  final range = ref.watch(crmCustomRangeProvider);
  // Every widget is a `dashboard-crm/*` call, which the server refuses for a
  // role without `crm_dashboard`. Don't fire seven calls just to collect 403s
  // (one of them used to raise a permission toast, and the follow-ups list
  // that did answer made the screen render zeros as if they were data): say so
  // up front, and the screen shows "Overview not included in your role".
  if (!await opsModuleReadable(ref, 'crm_dashboard')) {
    throw const AppError(
        type: AppErrorType.forbidden,
        message: 'You do not have permission to view the CRM dashboard.');
  }
  return ref
      .watch(crmHomeRepositoryProvider)
      .getHome(period: period.query(range));
});

// ── Mock literals (rendered verbatim when ApiConfig.apiEnabled is false) ──

/// Summary line above "My recent wins".
const crmWinsCount = '5 deals won';
const crmWinsTotal = '₹3.12Cr total value';

/// Static "recent wins" list — a local port of the prototype's `chWins`.
const crmRecentWins = <WinRow>[
  WinRow(
      name: 'Kalyan Silks',
      deal: 'Showroom interiors',
      amt: '₹18L',
      when: 'Won 28 Jun',
      route: Routes.leadDetail,
      id: 'L1001'),
  WinRow(
      name: 'Marari Sands Resort',
      deal: 'Resort villa interiors',
      amt: '₹55L',
      when: 'Won 14 Jun',
      route: Routes.leadDetail,
      id: 'L1003'),
  WinRow(
      name: 'Aster Medcity OPD',
      deal: 'Multi-speciality OPD',
      amt: '₹92L',
      when: 'Won 09 Jun',
      route: Routes.leadDetail,
      id: 'L1005'),
  WinRow(
      name: 'Federal Bank Aluva',
      deal: 'Workspace fit-out · 80 seats',
      amt: '₹1.29Cr',
      when: 'Won 30 May',
      route: Routes.leadDetail,
      id: 'L1007'),
  WinRow(
      name: 'Paragon Restaurant',
      deal: 'Dining hall interiors',
      amt: '₹18L',
      when: 'Won 22 May',
      route: Routes.customerDetail,
      id: 'C2012'),
];

/// Static "overdue items" data keyed by chip — a local port of `chOdData`.
const crmOverdueData = <String, List<OverdueRow>>{
  'fu': [
    OverdueRow(
        name: 'Ramesh Pillai',
        sub: 'Kalyan Silks · Anjana Menon',
        amt: '₹18L',
        age: '23 days ago',
        route: Routes.followupDetail,
        id: 'F901'),
    OverdueRow(
        name: 'Suresh Nair',
        sub: 'KIMS Clinic · Arjun Nair',
        amt: '₹1.10Cr',
        age: '18 days ago',
        route: Routes.followupDetail,
        id: 'F906'),
    OverdueRow(
        name: 'Ashraf Ali',
        sub: 'Malabar Gold Showroom · Sneha Thomas',
        amt: '₹2.03Cr',
        age: '23 days ago',
        route: Routes.followupDetail,
        id: 'F911'),
  ],
  'pay': [
    OverdueRow(
        name: 'Marari Sands Resort',
        sub: 'On handover (30%) · Fariz Ahmed',
        amt: '₹18.3L',
        age: '15 days ago',
        route: Routes.paymentDetail,
        id: 'PAY-4004'),
    OverdueRow(
        name: 'Federal Bank Aluva',
        sub: 'On handover (30%) · Anjana Menon',
        amt: '₹43L',
        age: '15 days ago',
        route: Routes.paymentDetail,
        id: 'PAY-4009'),
  ],
  'quotes': [
    OverdueRow(
        name: 'Lulu Fashion Store',
        sub: '#Q2002 · Rahul Krishnan',
        amt: '₹58.9L',
        age: '72 days ago',
        route: Routes.quoteDetail,
        id: 'Q2002'),
    OverdueRow(
        name: 'Taj Gateway Annexe',
        sub: '#Q2004 · Deepak Raj',
        amt: '₹85.7L',
        age: '48 days ago',
        route: Routes.quoteDetail,
        id: 'Q2004'),
    OverdueRow(
        name: 'Kalyan Silks',
        sub: '#Q2050 · Anjana Menon',
        amt: '₹2.5L',
        age: '37 days ago',
        route: Routes.quoteDetail,
        id: 'Q2050'),
  ],
  'noproj': [
    OverdueRow(
        name: 'Federal Bank Aluva',
        sub: 'Won lead · Anjana Menon',
        amt: '₹1.29Cr',
        age: '40 days ago',
        route: Routes.leadDetail,
        id: 'L1007'),
    OverdueRow(
        name: 'Malabar Gold Showroom',
        sub: 'Active customer · Sneha Thomas',
        amt: '₹2.03Cr',
        age: '62 days ago',
        route: Routes.customerDetail,
        id: 'C2010'),
  ],
};
