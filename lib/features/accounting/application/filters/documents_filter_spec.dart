import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/filters/filter_models.dart';
import '../../../../core/utils/money_format.dart';
import '../../../crm/application/providers/customers_providers.dart';
import '../../domain/entities/acc_document.dart';
import '../../presentation/config/accounting_copy.dart';
import '../providers/documents_providers.dart';

/// The Invoices screen's filter drawer, on the app's spec-driven filter engine.
///
/// Unlike the CRM lists these filters run **server-side** — the documents list
/// is paged, so filtering what is loaded would silently hide older rows. The
/// matcher below only drives the drawer's live "N results" preview over the
/// rows already on screen.
FilterSpec buildDocumentsFilterSpec({required bool creditNotes, required List<FilterOption> customers}) =>
    FilterSpec(title: creditNotes ? 'Filter credit notes' : 'Filter invoices', sections: [
      if (!creditNotes)
        FilterSection(title: 'Document', fields: [
          FilterField(
            id: 'type',
            label: 'Type',
            control: FilterControl.radio,
            options: [
              for (final t in manualInvoiceTypes) FilterOption(id: t, label: docTypeLabels[t]!),
            ],
          ),
        ]),
      const FilterSection(title: 'Payment', fields: [
        FilterField(
          id: 'payment',
          label: 'Payment state',
          control: FilterControl.radio,
          options: [
            FilterOption(id: 'any', label: 'Any'),
            FilterOption(id: 'UNPAID', label: 'Unpaid'),
            FilterOption(id: 'PARTIAL', label: 'Part paid'),
            FilterOption(id: 'PAID', label: 'Paid'),
          ],
        ),
      ]),
      FilterSection(title: 'Customer', fields: [
        FilterField(
          id: 'customer',
          label: 'Customer',
          control: FilterControl.radio,
          options: [const FilterOption(id: 'any', label: 'Any customer'), ...customers],
        ),
      ]),
      FilterSection(title: 'Dates', fields: [
        const FilterField(
          id: 'date',
          label: 'Document date',
          control: FilterControl.dateRange,
          dateChips: ['month', 'last30', 'last90'],
        ),
        if (!creditNotes)
          FilterField(
            id: 'source',
            label: 'Raised from',
            control: FilterControl.radio,
            options: [
              const FilterOption(id: 'any', label: 'Anywhere'),
              for (final k in const ['PLAN_RECORD', 'TICKET', 'MANUAL', 'MILESTONE', 'PERIODIC'])
                FilterOption(id: k, label: sourceTypeLabels[k]!),
            ],
          ),
      ]),
    ]);

final documentsFilterSpecProvider = Provider.family<FilterSpec, bool>((ref, creditNotes) {
  final customers = ref.watch(customersProvider).valueOrNull ?? const [];
  return buildDocumentsFilterSpec(
    creditNotes: creditNotes,
    customers: [for (final c in customers) FilterOption(id: c.id, label: c.name)],
  );
});

/// Invoices | Credit notes.
final accDocModeProvider = StateProvider<String>((ref) => 'invoices');

/// All | DRAFT | ISSUED | CANCELLED.
final accDocTabProvider = StateProvider<String>((ref) => 'all');
final accDocFiltersProvider = StateProvider<FilterValues>((ref) => FilterValues());
final accDocSearchProvider = StateProvider<String>((ref) => '');
final accDocSearchOpenProvider = StateProvider<bool>((ref) => false);

String? _radio(FilterValues f, String id) {
  final v = f.radio(id)?.id;
  return (v == null || v == 'any' || v.isEmpty) ? null : v;
}

(String?, String?) _dates(FilterValues f) {
  final d = f.date('date');
  if (d == null || !d.isActive) return (null, null);
  final (from, to) = d.chip != null ? FilterMatch.chipRange(d.chip!) : (d.from, d.to);
  return (from == null ? null : isoDay(from), to == null ? null : isoDay(to));
}

/// The query the Invoices screen is showing right now.
final accDocQueryProvider = Provider<DocQuery>((ref) {
  final credit = ref.watch(accDocModeProvider) == 'credit';
  final tab = ref.watch(accDocTabProvider);
  final f = ref.watch(accDocFiltersProvider);
  final search = ref.watch(accDocSearchProvider).trim();
  final (from, to) = _dates(f);
  return DocQuery(
    docType: credit ? 'CREDIT_NOTE' : (_radio(f, 'type') ?? 'TAX_INVOICE'),
    status: tab == 'all' ? null : tab,
    paymentState: _radio(f, 'payment'),
    customer: _radio(f, 'customer'),
    sourceType: credit ? null : _radio(f, 'source'),
    dateFrom: from,
    dateTo: to,
    // The server searches `number` and `vendor_invoice_no`, and caps at 64.
    search: search.isEmpty ? null : (search.length > 64 ? search.substring(0, 64) : search),
  );
});

/// Local twin of the server filter, for the drawer's preview count only.
bool documentMatchesFilters(AccDocument d, FilterValues f, {required bool creditNotes}) {
  final type = creditNotes ? 'CREDIT_NOTE' : (_radio(f, 'type') ?? 'TAX_INVOICE');
  if (d.docType != type) return false;
  final pay = _radio(f, 'payment');
  if (pay != null && d.paymentState != pay) return false;
  final cust = _radio(f, 'customer');
  if (cust != null && d.customerId != cust) return false;
  final src = _radio(f, 'source');
  if (!creditNotes && src != null && d.sourceType != src) return false;
  return FilterMatch.matchDate(f.date('date'), DateTime.tryParse(d.documentDate ?? ''));
}
