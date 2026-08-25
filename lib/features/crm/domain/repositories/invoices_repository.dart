import '../entities/invoice.dart';

/// Abstract contract for invoice data. The presentation layer depends only on
/// this; whether invoices come from a mock source or a REST API is an
/// infrastructure detail.
abstract class InvoicesRepository {
  Future<List<Invoice>> getInvoices();

  /// The server's own totals and schedule counts for one invoice, by
  /// `payment_id`. Null means "no server figures" — mock mode, an invoice with
  /// no uuid, or a failed call — and callers fall back to their own arithmetic.
  Future<InvoiceSummary?> getInvoiceSummary(String paymentId);
}
