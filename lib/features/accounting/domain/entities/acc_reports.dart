import 'package:equatable/equatable.dart';

/// The four aging buckets, in the order the API lists them.
const agingBuckets = ['0-30', '31-60', '61-90', '90+'];

/// One party row of an AR / AP aging report.
class AgingRow extends Equatable {
  const AgingRow({required this.partyId, this.partyName, this.buckets = const {}, this.total = '0'});

  final String partyId;

  /// The one place the API returns party names (handover §8.8).
  final String? partyName;
  final Map<String, String> buckets;
  final String total;

  @override
  List<Object?> get props => [partyId, buckets, total];
}

/// `reports/ar-aging/` or `reports/ap-aging/`.
class AgingReport extends Equatable {
  const AgingReport({this.asOf, this.rows = const [], this.totals = const {}});

  final String? asOf;
  final List<AgingRow> rows;

  /// Per-bucket totals plus `total`.
  final Map<String, String> totals;

  String get grandTotal => totals['total'] ?? '0';

  @override
  List<Object?> get props => [asOf, rows, totals];
}

class StatementLine extends Equatable {
  const StatementLine({this.date, this.kind, this.docType, this.reference, this.refId, this.debit = '0', this.credit = '0', this.balance = '0'});

  final String? date;
  final String? kind; // DOCUMENT | RECEIPT | PAYMENT
  final String? docType;
  final String? reference;
  final String? refId;
  final String debit;
  final String credit;
  final String balance;

  @override
  List<Object?> get props => [date, reference, debit, credit, balance];
}

/// A customer or vendor statement.
class PartyStatement extends Equatable {
  const PartyStatement({
    this.dateFrom,
    this.dateTo,
    this.openingBalance = '0',
    this.closingBalance = '0',
    this.totalDebit = '0',
    this.totalCredit = '0',
    this.lines = const [],
  });

  final String? dateFrom;
  final String? dateTo;
  final String openingBalance;
  final String closingBalance;
  final String totalDebit;
  final String totalCredit;
  final List<StatementLine> lines;

  @override
  List<Object?> get props => [dateFrom, dateTo, openingBalance, closingBalance, lines];
}

/// One account and its amount in a P&L or balance sheet section.
class ReportAccount extends Equatable {
  const ReportAccount({this.code, required this.name, this.amount = '0'});

  final String? code;
  final String name;
  final String amount;

  @override
  List<Object?> get props => [code, name, amount];
}

class PnlReport extends Equatable {
  const PnlReport({
    this.asOf,
    this.income = const [],
    this.expense = const [],
    this.totalIncome = '0',
    this.totalExpense = '0',
    this.netProfit = '0',
  });

  final String? asOf;
  final List<ReportAccount> income;
  final List<ReportAccount> expense;
  final String totalIncome;
  final String totalExpense;
  final String netProfit;

  @override
  List<Object?> get props => [asOf, income, expense, netProfit];
}

class BalanceSheetReport extends Equatable {
  const BalanceSheetReport({
    this.asOf,
    this.assets = const [],
    this.liabilities = const [],
    this.equity = const [],
    this.netProfit = '0',
    this.totalAssets = '0',
    this.totalLiabilities = '0',
    this.totalEquity = '0',
    this.liabilitiesAndEquity = '0',
    this.balanced = false,
  });

  final String? asOf;
  final List<ReportAccount> assets;
  final List<ReportAccount> liabilities;
  final List<ReportAccount> equity;
  final String netProfit;
  final String totalAssets;
  final String totalLiabilities;
  final String totalEquity;
  final String liabilitiesAndEquity;
  final bool balanced;

  @override
  List<Object?> get props => [asOf, totalAssets, liabilitiesAndEquity, balanced];
}

class TrialBalanceAccount extends Equatable {
  const TrialBalanceAccount({this.code, required this.name, this.closingDebit = '0', this.closingCredit = '0'});

  final String? code;
  final String name;
  final String closingDebit;
  final String closingCredit;

  @override
  List<Object?> get props => [code, name, closingDebit, closingCredit];
}

class TrialBalanceGroup extends Equatable {
  const TrialBalanceGroup({required this.bucket, this.accounts = const [], this.debit = '0', this.credit = '0'});

  final String bucket;
  final List<TrialBalanceAccount> accounts;
  final String debit;
  final String credit;

  @override
  List<Object?> get props => [bucket, accounts, debit, credit];
}

class TrialBalanceReport extends Equatable {
  const TrialBalanceReport({this.asOf, this.groups = const [], this.totalDebit = '0', this.totalCredit = '0', this.balanced = false});

  final String? asOf;
  final List<TrialBalanceGroup> groups;
  final String totalDebit;
  final String totalCredit;
  final bool balanced;

  @override
  List<Object?> get props => [asOf, groups, totalDebit, totalCredit, balanced];
}

/// One nature row of the TDS summary.
class TdsSummaryRow extends Equatable {
  const TdsSummaryRow({required this.natureKey, this.quarter, this.base = '0', this.deducted = '0', this.deposited = '0', this.pending = '0', this.count = 0});

  final String natureKey;
  final int? quarter;
  final String base;
  final String deducted;
  final String deposited;
  final String pending;
  final int count;

  @override
  List<Object?> get props => [natureKey, quarter, deducted, pending];
}

class TdsSummary extends Equatable {
  const TdsSummary({this.rows = const [], this.totals = const {}});

  final List<TdsSummaryRow> rows;

  /// `base, deducted, deposited, pending` (money) and `count`.
  final Map<String, String> totals;

  @override
  List<Object?> get props => [rows, totals];
}

/// `reports/gst-summary/` — per-section head totals. The section vocabulary is
/// the server's, so it is carried as nested maps and rendered generically.
class GstSummary extends Equatable {
  const GstSummary({this.grandTotals = const {}});

  /// section → head → amount string.
  final Map<String, Map<String, String>> grandTotals;

  @override
  List<Object?> get props => [grandTotals];
}

/// `reports/project-financials/{id}/` (live) or a project's persisted
/// `financials` field.
class ProjectFinancials extends Equatable {
  const ProjectFinancials({
    this.billedTaxable = '0',
    this.billedGross = '0',
    this.creditNotesTaxable = '0',
    this.collected = '0',
    this.openAr = '0',
    this.purchaseTaxable = '0',
    this.expenseTaxable = '0',
    this.vendorOpenAp = '0',
    this.grossMargin = '0',
    this.asOfEntryNo,
    this.updatedAt,
  });

  final String billedTaxable;
  final String billedGross;
  final String creditNotesTaxable;
  final String collected;
  final String openAr;
  final String purchaseTaxable;
  final String expenseTaxable;
  final String vendorOpenAp;
  final String grossMargin;
  final String? asOfEntryNo;
  final String? updatedAt;

  @override
  List<Object?> get props => [billedGross, collected, openAr, grossMargin, asOfEntryNo, updatedAt];
}
