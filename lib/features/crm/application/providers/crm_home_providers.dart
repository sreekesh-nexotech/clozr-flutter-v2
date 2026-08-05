import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/crm_home_models.dart';
import '../../infrastructure/data_sources/remote/crm_home_remote_ds.dart';
import '../../infrastructure/repositories/crm_home_repository.dart';

export '../../domain/entities/crm_home_models.dart' show WinRow, OverdueRow, CrmHomeData;

/// Active chip on the Home "Overdue items" module.
final crmOverdueTabProvider = StateProvider<String>((ref) => 'fu');

// ── API-backed source (used only when ApiConfig.apiEnabled) ──

/// DI seam for the CRM Home repository.
final crmHomeRepositoryProvider = Provider<CrmHomeRepository>(
  (ref) => CrmHomeRepository(CrmHomeRemoteDataSource(ref.watch(apiServiceProvider))),
);

/// The personal CRM Home bundle. Watched by the screen **only in API mode**; in
/// mock mode the screen renders the const literals below and never creates this.
final crmHomeProvider = FutureProvider<CrmHomeData>(
  (ref) => ref.watch(crmHomeRepositoryProvider).getHome(),
);

// ── Mock literals (rendered verbatim when ApiConfig.apiEnabled is false) ──

/// Summary line above "My recent wins".
const crmWinsCount = '5 deals won';
const crmWinsTotal = '₹3.12Cr total value';

/// Static "recent wins" list — a local port of the prototype's `chWins`.
const crmRecentWins = <WinRow>[
  WinRow(name: 'Kalyan Silks', deal: 'Showroom interiors', amt: '₹18L', when: 'Won 28 Jun', route: Routes.leadDetail, id: 'L1001'),
  WinRow(name: 'Marari Sands Resort', deal: 'Resort villa interiors', amt: '₹55L', when: 'Won 14 Jun', route: Routes.leadDetail, id: 'L1003'),
  WinRow(name: 'Aster Medcity OPD', deal: 'Multi-speciality OPD', amt: '₹92L', when: 'Won 09 Jun', route: Routes.leadDetail, id: 'L1005'),
  WinRow(name: 'Federal Bank Aluva', deal: 'Workspace fit-out · 80 seats', amt: '₹1.29Cr', when: 'Won 30 May', route: Routes.leadDetail, id: 'L1007'),
  WinRow(name: 'Paragon Restaurant', deal: 'Dining hall interiors', amt: '₹18L', when: 'Won 22 May', route: Routes.customerDetail, id: 'C2012'),
];

/// Static "overdue items" data keyed by chip — a local port of `chOdData`.
const crmOverdueData = <String, List<OverdueRow>>{
  'fu': [
    OverdueRow(name: 'Ramesh Pillai', sub: 'Kalyan Silks · Anjana Menon', amt: '₹18L', age: '23 days ago', route: Routes.followupDetail, id: 'F901'),
    OverdueRow(name: 'Suresh Nair', sub: 'KIMS Clinic · Arjun Nair', amt: '₹1.10Cr', age: '18 days ago', route: Routes.followupDetail, id: 'F906'),
    OverdueRow(name: 'Ashraf Ali', sub: 'Malabar Gold Showroom · Sneha Thomas', amt: '₹2.03Cr', age: '23 days ago', route: Routes.followupDetail, id: 'F911'),
  ],
  'pay': [
    OverdueRow(name: 'Marari Sands Resort', sub: 'On handover (30%) · Fariz Ahmed', amt: '₹18.3L', age: '15 days ago', route: Routes.paymentDetail, id: 'PAY-4004'),
    OverdueRow(name: 'Federal Bank Aluva', sub: 'On handover (30%) · Anjana Menon', amt: '₹43L', age: '15 days ago', route: Routes.paymentDetail, id: 'PAY-4009'),
  ],
  'quotes': [
    OverdueRow(name: 'Lulu Fashion Store', sub: '#Q2002 · Rahul Krishnan', amt: '₹58.9L', age: '72 days ago', route: Routes.quoteDetail, id: 'Q2002'),
    OverdueRow(name: 'Taj Gateway Annexe', sub: '#Q2004 · Deepak Raj', amt: '₹85.7L', age: '48 days ago', route: Routes.quoteDetail, id: 'Q2004'),
    OverdueRow(name: 'Kalyan Silks', sub: '#Q2050 · Anjana Menon', amt: '₹2.5L', age: '37 days ago', route: Routes.quoteDetail, id: 'Q2050'),
  ],
  'noproj': [
    OverdueRow(name: 'Federal Bank Aluva', sub: 'Won lead · Anjana Menon', amt: '₹1.29Cr', age: '40 days ago', route: Routes.leadDetail, id: 'L1007'),
    OverdueRow(name: 'Malabar Gold Showroom', sub: 'Active customer · Sneha Thomas', amt: '₹2.03Cr', age: '62 days ago', route: Routes.customerDetail, id: 'C2010'),
  ],
};
