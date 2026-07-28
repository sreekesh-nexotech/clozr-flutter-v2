import '../../../domain/entities/invoice.dart';

/// Static invoice seed — a 1:1 port of the prototype's `invoices` array. This is
/// the ONLY place invoice sample data lives. To integrate the API, replace this
/// class with a remote data source returning `List<Invoice>`.
class InvoicesMockDataSource {
  const InvoicesMockDataSource();

  List<Invoice> fetchInvoices() => const [
        Invoice(id: 'INV-3001', custId: 'C2001', quoteId: 'Q2001', type: 'Lump sum', total: '₹18L', totalNum: 1800000, settled: 1, of: 1, balance: '₹0L', status: 'completed'),
        Invoice(id: 'INV-3002', custId: 'C2003', quoteId: 'Q2003', type: 'Installments', total: '₹55L', totalNum: 5500000, settled: 2, of: 3, balance: '₹18.3L', status: 'partial'),
        Invoice(id: 'INV-3003', custId: 'C2005', quoteId: 'Q2005', type: 'Installments', total: '₹92L', totalNum: 9200000, settled: 2, of: 2, balance: '₹0L', status: 'completed'),
        Invoice(id: 'INV-3004', custId: 'C2007', quoteId: 'Q2007', type: 'Installments', total: '₹1.29Cr', totalNum: 12900000, settled: 2, of: 3, balance: '₹43L', status: 'partial'),
        Invoice(id: 'INV-3005', custId: 'C2010', quoteId: 'Q2009', type: 'Installments', total: '₹2.03Cr', totalNum: 20300000, settled: 1, of: 2, balance: '₹1.01Cr', status: 'partial'),
        Invoice(id: 'INV-3006', custId: 'C2012', quoteId: 'Q2012', type: 'Lump sum', total: '₹18L', totalNum: 1800000, settled: 1, of: 1, balance: '₹0L', status: 'completed'),
        Invoice(id: 'INV-3007', custId: 'C2001', quoteId: 'Q2051', type: 'Installments', total: '₹38L', totalNum: 3800000, settled: 0, of: 3, balance: '₹38L', status: 'unpaid'),
        Invoice(id: 'INV-3008', custId: 'C2006', quoteId: null, type: 'Installments', total: '₹28L', totalNum: 2800000, settled: 0, of: 2, balance: '₹28L', status: 'unpaid'),
        Invoice(id: 'INV-3009', custId: 'C2003', quoteId: 'Q2049', type: 'Installments', total: '₹42L', totalNum: 4200000, settled: 0, of: 3, balance: '₹42L', status: 'unpaid'),
      ];
}
