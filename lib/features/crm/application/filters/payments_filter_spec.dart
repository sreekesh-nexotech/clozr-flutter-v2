import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/filters/filter_models.dart';
import '../../../../core/filters/saved_view.dart';
import '../../../../data/mock/mock_users.dart';
import '../../../../data/mock/status_meta.dart';
import '../../domain/entities/payment.dart';
import '../../infrastructure/data_sources/local/crm_party_directory.dart';
import '../providers/payments_providers.dart';

/// Payments filter — spec-driven drawer wired like the Leads reference (audit §7).
/// Generic drawer (title "Payments").

const _months = {
  'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
  'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
};

/// Extract the "dd Mon yyyy" from a payment date line, which may be prefixed
/// ("Overdue 24 Jun 2026", "Due 05 Jul 2026", "Scheduled 15 Jul 2026") or bare
/// ("05 May 2026"). Returns null when no date is present ("Paid just now").
DateTime? parsePaymentDate(String s) {
  final m = RegExp(r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})').firstMatch(s);
  if (m == null) return null;
  final day = int.tryParse(m.group(1)!);
  final month = _months[m.group(2)!];
  final year = int.tryParse(m.group(3)!);
  if (day == null || month == null || year == null) return null;
  return DateTime(year, month, day);
}

/// The company label a payment resolves to.
String? paymentCompany(Payment p) =>
    CrmPartyDirectory.customer(p.custId)?.company ?? CrmPartyDirectory.customer(p.custId)?.name;

/// Build the Payments drawer spec from the current payment set.
FilterSpec buildPaymentsFilterSpec(List<Payment> payments) {
  // Canonical method vocabulary (audit §7).
  const methodValues = ['Bank transfer', 'UPI', 'Card', 'Cash', 'Cheque'];
  final methods = [for (final m in methodValues) FilterOption(id: m, label: m)];
  const statusKeys = ['paid', 'due', 'overdue', 'scheduled'];
  final statuses = [
    for (final k in statusKeys) FilterOption(id: k, label: StatusMeta$.payment[k]!.label),
  ];
  final ownerIds = payments.map((p) => p.owner).toSet();
  final owners = [
    for (final u in MockUsers.reps)
      if (ownerIds.contains(u.id)) FilterOption(id: u.id, label: u.name),
  ];
  final companies = (payments
          .map(paymentCompany)
          .whereType<String>()
          .toSet()
          .toList()
        ..sort())
      .map((c) => FilterOption(id: c, label: c))
      .toList();

  return FilterSpec(
    title: 'Payments',
    sections: [
      FilterSection(title: 'Payment details', fields: [
        FilterField(
            id: 'method',
            label: 'Method',
            control: FilterControl.checkboxGroup,
            twoCol: true,
            options: methods),
        FilterField(
            id: 'status',
            label: 'Status',
            control: FilterControl.checkboxGroup,
            twoCol: true,
            options: statuses),
        FilterField(
            id: 'recordedBy',
            label: 'Recorded by',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search user…',
            options: owners),
        FilterField(
            id: 'company',
            label: 'Customer / Company',
            control: FilterControl.searchSelect,
            searchable: true,
            isNotToggle: true,
            placeholder: 'Search customer…',
            options: companies),
      ]),
      FilterSection(title: 'Amount & date', fields: [
        const FilterField(
            id: 'amount',
            label: 'Amount',
            control: FilterControl.numberRange,
            unit: '₹ lakhs',
            unitScale: 100000),
        const FilterField(
            id: 'paymentDate',
            label: 'Payment date',
            control: FilterControl.dateRange,
            dateChips: ['overdue', 'today', 'tomorrow', 'last7', 'last30', 'next7', 'next30', 'next90']),
      ]),
    ],
  );
}

/// Evaluate a payment against applied filter values.
bool paymentMatchesFilters(Payment p, FilterValues v) {
  if (!FilterMatch.matchAnyOf(v.choice('method'), [p.method])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('status'), [p.status])) return false;
  if (!FilterMatch.matchAnyOf(v.choice('recordedBy'), [p.owner])) return false;
  final company = paymentCompany(p);
  if (!FilterMatch.matchAnyOf(v.choice('company'), company == null ? const [] : [company])) {
    return false;
  }
  if (!FilterMatch.matchRange(v.range('amount'), p.amountNum, scale: 100000)) return false;
  if (!FilterMatch.matchDate(v.date('paymentDate'), parsePaymentDate(p.date))) return false;
  return true;
}

// ── Providers ──

/// The Payments drawer spec, derived from the loaded payments.
final paymentsFilterSpecProvider = Provider<FilterSpec>((ref) {
  final payments = ref.watch(allPaymentsProvider);
  return buildPaymentsFilterSpec(payments);
});

/// Applied drawer filters for the Payments list (source of the badge count).
final paymentFiltersProvider = StateProvider<FilterValues>((ref) => FilterValues());

/// Saved views for the Payments list (bookmark chips).
final paymentSavedViewsProvider =
    StateNotifierProvider<SavedViewsController, SavedViewsState>((ref) => SavedViewsController());
