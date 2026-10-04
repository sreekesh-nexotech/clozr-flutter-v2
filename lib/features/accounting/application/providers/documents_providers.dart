import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/app_error.dart';
import '../../domain/entities/acc_document.dart';
import '../../domain/entities/acc_ledger.dart';
import 'accounting_providers.dart';

/// The server-side filters of one documents list.
///
/// `doc_type` is always sent (handover §12.4) — the rows are heavy, and an
/// unscoped list mixes vendor bills in with sales.
class DocQuery extends Equatable {
  const DocQuery({
    required this.docType,
    this.status,
    this.paymentState,
    this.customer,
    this.vendor,
    this.sourceType,
    this.dateFrom,
    this.dateTo,
    this.search,
  });

  final String docType;
  final String? status;
  final String? paymentState;
  final String? customer;
  final String? vendor;
  final String? sourceType;
  final String? dateFrom;
  final String? dateTo;
  final String? search;

  Map<String, Object?> toParams() => {
        'doc_type': docType,
        'status': status,
        'payment_state': paymentState,
        'customer': customer,
        'vendor': vendor,
        'source_type': sourceType,
        'date_from': dateFrom,
        'date_to': dateTo,
        'search': search,
      };

  @override
  List<Object?> get props =>
      [docType, status, paymentState, customer, vendor, sourceType, dateFrom, dateTo, search];
}

class DocListState {
  const DocListState({
    this.items = const [],
    this.count = 0,
    this.hasMore = false,
    this.loading = true,
    this.loadingMore = false,
    this.error,
  });

  final List<AccDocument> items;
  final int count;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final AppError? error;

  DocListState copyWith({
    List<AccDocument>? items,
    int? count,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    AppError? error,
    bool clearError = false,
  }) =>
      DocListState(
        items: items ?? this.items,
        count: count ?? this.count,
        hasMore: hasMore ?? this.hasMore,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
      );
}

/// A paged documents list for one [DocQuery] — page 1 on build, then
/// [loadMore] as the user scrolls.
class DocListController extends StateNotifier<DocListState> {
  DocListController(this._ref, this.query) : super(const DocListState()) {
    refresh();
  }

  final Ref _ref;
  final DocQuery query;
  int _page = 1;

  Future<void> refresh() async {
    state = state.copyWith(loading: state.items.isEmpty, clearError: true);
    try {
      final page = await _ref.read(accountingRepositoryProvider).documents(query.toParams());
      if (!mounted) return;
      _page = 1;
      state = DocListState(items: page.results, count: page.count, hasMore: page.hasMore, loading: false);
    } on AppError catch (e) {
      if (!mounted) return;
      if (e.isAccountingInactive) _ref.invalidate(accountingStatusProvider);
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.loadingMore || state.loading) return;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await _ref.read(accountingRepositoryProvider).documents(query.toParams(), page: _page + 1);
      if (!mounted) return;
      _page++;
      state = state.copyWith(
        items: [...state.items, ...page.results],
        hasMore: page.hasMore,
        loadingMore: false,
      );
    } on AppError {
      if (!mounted) return;
      // The rows already shown stay; the next scroll tries again.
      state = state.copyWith(loadingMore: false);
    }
  }
}

final docListProvider =
    StateNotifierProvider.autoDispose.family<DocListController, DocListState, DocQuery>(
  (ref, q) => DocListController(ref, q),
);

/// One document, fresh from the server.
final accDocumentProvider = FutureProvider.autoDispose.family<AccDocument?, String>(
  (ref, id) => ref.watch(accountingRepositoryProvider).document(id),
);

/// The posted journal behind a document.
final documentJournalProvider = FutureProvider.autoDispose.family<List<JournalEntry>, String>(
  (ref, id) => ref.watch(accountingRepositoryProvider).journalForDocument(id),
);

/// A customer's open, issued invoices — what a receipt can be targeted at and
/// what a statement tab lists.
final openInvoicesForCustomerProvider =
    FutureProvider.autoDispose.family<List<AccDocument>, String>((ref, customerId) async {
  final repo = ref.watch(accountingRepositoryProvider);
  final page = await repo.documents(DocQuery(
    docType: 'TAX_INVOICE',
    status: 'ISSUED',
    customer: customerId,
  ).toParams());
  return [
    for (final d in page.results)
      if (d.paymentState == 'UNPAID' || d.paymentState == 'PARTIAL') d,
  ];
});

/// Every document for one customer (the customer Accounting tab).
final documentsForCustomerProvider =
    FutureProvider.autoDispose.family<List<AccDocument>, String>((ref, customerId) async {
  final page = await ref
      .watch(accountingRepositoryProvider)
      .documents(DocQuery(docType: 'TAX_INVOICE', customer: customerId).toParams());
  return page.results;
});

/// A vendor's bills — the documents list now filters by `vendor` server-side.
final billsForVendorProvider =
    FutureProvider.autoDispose.family<List<AccDocument>, String>((ref, vendorId) async {
  final page = await ref
      .watch(accountingRepositoryProvider)
      .documents(DocQuery(docType: 'VENDOR_BILL', vendor: vendorId).toParams());
  return page.results;
});

/// Drafts and invoices the backend has already created for a plan record —
/// looked up **before** offering "Issue invoice", because every create call
/// makes a new draft and plans on `INVOICE_ON_DUE` pre-create one (§12.1).
final draftsForPaymentRecordProvider = FutureProvider.autoDispose
    .family<List<AccDocument>, ({String recordId, String? customerId})>((ref, key) async {
  final page = await ref.watch(accountingRepositoryProvider).documents(DocQuery(
        docType: 'TAX_INVOICE',
        status: 'DRAFT',
        sourceType: 'PLAN_RECORD',
        customer: key.customerId,
      ).toParams());
  return [for (final d in page.results) if (d.paymentRecordId == key.recordId) d];
});

/// Sales drafts waiting to be issued — the count and the first page, for the
/// home's "needs attention" list.
final draftInvoicesProvider = FutureProvider.autoDispose<AccDocumentPage>(
  (ref) => ref
      .watch(accountingRepositoryProvider)
      .documents(const DocQuery(docType: 'TAX_INVOICE', status: 'DRAFT').toParams()),
);
