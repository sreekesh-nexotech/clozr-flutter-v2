import '../entities/invoice.dart';

/// Abstract contract for invoice data. The presentation layer depends only on
/// this; whether invoices come from a mock source or a REST API is an
/// infrastructure detail.
abstract class InvoicesRepository {
  Future<List<Invoice>> getInvoices();
}
