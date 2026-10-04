import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'documents_providers.dart';
import 'reports_providers.dart';
import 'settlement_providers.dart';

/// Refetches every accounting read a posting can move.
///
/// Called after any accounting write (plan rule 4). Broad on purpose: one
/// receipt moves a document's open balance, the customer's credits, both aging
/// reports and the home tiles, and a stale ledger figure is worse than a
/// refetch. Pass `ref.invalidate` from either a `Ref` or a `WidgetRef`.
void invalidateAccountingReads(void Function(ProviderOrFamily) invalidate) {
  for (final p in <ProviderOrFamily>[
    docListProvider,
    accDocumentProvider,
    documentJournalProvider,
    openInvoicesForCustomerProvider,
    documentsForCustomerProvider,
    billsForVendorProvider,
    draftsForPaymentRecordProvider,
    draftInvoicesProvider,
    receiptsProvider,
    receiptDetailProvider,
    advancesProvider,
    customerCreditsProvider,
    vendorPaymentsProvider,
    vendorPaymentDetailProvider,
    vendorAdvancesProvider,
    arAgingProvider,
    apAgingProvider,
    statementProvider,
    pnlProvider,
    balanceSheetProvider,
    trialBalanceProvider,
    rejectedEventsProvider,
    projectFinancialsProvider,
  ]) {
    invalidate(p);
  }
}
