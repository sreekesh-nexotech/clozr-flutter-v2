import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/money_format.dart';
import '../../domain/entities/acc_ledger.dart';
import '../../domain/entities/acc_periods.dart';
import '../../domain/entities/acc_reports.dart';
import '../../domain/entities/acc_setup.dart';
import 'accounting_providers.dart';

final arAgingProvider = FutureProvider.autoDispose<AgingReport>(
  (ref) => ref.watch(accountingRepositoryProvider).aging(payable: false),
);

final apAgingProvider = FutureProvider.autoDispose<AgingReport>(
  (ref) => ref.watch(accountingRepositoryProvider).aging(payable: true),
);

/// A statement for one party over a date window.
typedef StatementKey = ({bool vendor, String partyId, String from, String to});

final statementProvider = FutureProvider.autoDispose.family<PartyStatement, StatementKey>(
  (ref, k) => ref
      .watch(accountingRepositoryProvider)
      .statement(vendor: k.vendor, partyId: k.partyId, from: k.from, to: k.to),
);

/// Reports are as of a day the user picks; default today.
final pnlProvider = FutureProvider.autoDispose.family<PnlReport, String>(
  (ref, asOf) => ref.watch(accountingRepositoryProvider).pnl(asOf: asOf),
);

final balanceSheetProvider = FutureProvider.autoDispose.family<BalanceSheetReport, String>(
  (ref, asOf) => ref.watch(accountingRepositoryProvider).balanceSheet(asOf: asOf),
);

final trialBalanceProvider = FutureProvider.autoDispose.family<TrialBalanceReport, String>(
  (ref, asOf) => ref.watch(accountingRepositoryProvider).trialBalance(asOf: asOf),
);

final periodRegisterProvider = FutureProvider.autoDispose<PeriodRegister>(
  (ref) => ref.watch(accountingRepositoryProvider).periodRegister(),
);

final gstChecklistProvider = FutureProvider.autoDispose.family<PeriodChecklist, String>(
  (ref, id) => ref.watch(accountingRepositoryProvider).gstChecklist(id),
);

final gstSummaryProvider = FutureProvider.autoDispose.family<GstSummary, String>(
  (ref, id) => ref.watch(accountingRepositoryProvider).gstSummary(id),
);

final tdsSummaryProvider = FutureProvider.autoDispose.family<TdsSummary, String?>(
  (ref, id) => ref.watch(accountingRepositoryProvider).tdsSummary(tdsPeriodId: id),
);

/// Postings the ledger refused — the "needs attention" list.
final rejectedEventsProvider = FutureProvider.autoDispose<List<LedgerEvent>>(
  (ref) => ref.watch(accountingRepositoryProvider).ledgerEvents(status: 'REJECTED'),
);

final journalEntryProvider = FutureProvider.autoDispose.family<JournalEntry?, String>(
  (ref, id) => ref.watch(accountingRepositoryProvider).journalEntry(id),
);

final tenantAttributesProvider = FutureProvider.autoDispose<List<TenantAttribute>>(
  (ref) => ref.watch(accountingRepositoryProvider).tenantAttributes(),
);

final gatesProvider = FutureProvider.autoDispose<GatesReport?>(
  (ref) => ref.watch(accountingRepositoryProvider).gates(),
);

final projectFinancialsProvider = FutureProvider.autoDispose.family<ProjectFinancials?, String>(
  (ref, id) => ref.watch(accountingRepositoryProvider).projectFinancials(id),
);

/// Today as the API wants it — the default "as of" for every report.
String todayIso() => isoDay(DateTime.now());
