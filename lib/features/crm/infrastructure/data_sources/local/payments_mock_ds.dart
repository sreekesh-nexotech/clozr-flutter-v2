import '../../../domain/entities/payment.dart';

/// Static payment seed — a 1:1 port of the prototype's `payments` array. This is
/// the ONLY place payment sample data lives. To integrate the API, replace this
/// class with a remote data source returning `List<Payment>`.
class PaymentsMockDataSource {
  const PaymentsMockDataSource();

  List<Payment> fetchPayments() => const [
        Payment(id: 'PAY-4001', custId: 'C2001', invId: 'INV-3001', label: 'Full payment', amount: '₹18L', amountNum: 1800000, method: 'Bank transfer', status: 'paid', date: '05 May 2026', owner: 'am'),
        Payment(id: 'PAY-4002', custId: 'C2003', invId: 'INV-3002', label: 'Advance (40%)', amount: '₹18.3L', amountNum: 1830000, method: 'Cheque', status: 'paid', date: '18 May 2026', owner: 'fa'),
        Payment(id: 'PAY-4003', custId: 'C2003', invId: 'INV-3002', label: 'Milestone (30%)', amount: '₹18.3L', amountNum: 1830000, method: 'UPI', status: 'paid', date: '02 Jun 2026', owner: 'fa'),
        Payment(id: 'PAY-4004', custId: 'C2003', invId: 'INV-3002', label: 'On handover (30%)', amount: '₹18.3L', amountNum: 1830000, method: '—', status: 'overdue', date: 'Overdue 24 Jun 2026', owner: 'fa'),
        Payment(id: 'PAY-4005', custId: 'C2005', invId: 'INV-3003', label: 'Advance (50%)', amount: '₹46L', amountNum: 4600000, method: 'UPI', status: 'paid', date: '02 Jun 2026', owner: 'st'),
        Payment(id: 'PAY-4006', custId: 'C2005', invId: 'INV-3003', label: 'Balance (50%)', amount: '₹46L', amountNum: 4600000, method: 'Auto-debit', status: 'paid', date: '12 Jun 2026', owner: 'st'),
        Payment(id: 'PAY-4007', custId: 'C2007', invId: 'INV-3004', label: 'Advance (40%)', amount: '₹43L', amountNum: 4300000, method: 'Auto-debit', status: 'paid', date: '12 Jun 2026', owner: 'am'),
        Payment(id: 'PAY-4008', custId: 'C2007', invId: 'INV-3004', label: 'Milestone (30%)', amount: '₹43L', amountNum: 4300000, method: 'Bank transfer', status: 'paid', date: '20 Jun 2026', owner: 'am'),
        Payment(id: 'PAY-4009', custId: 'C2007', invId: 'INV-3004', label: 'On handover (30%)', amount: '₹43L', amountNum: 4300000, method: '—', status: 'overdue', date: 'Overdue 24 Jun 2026', owner: 'am'),
        Payment(id: 'PAY-4010', custId: 'C2010', invId: 'INV-3005', label: 'Advance (50%)', amount: '₹1.01Cr', amountNum: 10100000, method: 'Bank transfer', status: 'paid', date: '20 Jun 2026', owner: 'st'),
        Payment(id: 'PAY-4011', custId: 'C2010', invId: 'INV-3005', label: 'Balance (50%)', amount: '₹1.01Cr', amountNum: 10100000, method: '—', status: 'due', date: 'Due 05 Jul 2026', owner: 'st'),
        Payment(id: 'PAY-4012', custId: 'C2012', invId: 'INV-3006', label: 'Full payment', amount: '₹18L', amountNum: 1800000, method: 'Cheque', status: 'paid', date: '05 May 2026', owner: 'dr'),
        Payment(id: 'PAY-4013', custId: 'C2006', invId: 'INV-3008', label: 'Advance (50%)', amount: '₹14L', amountNum: 1400000, method: '—', status: 'due', date: 'Due 10 Jul 2026', owner: 'an'),
        Payment(id: 'PAY-4014', custId: 'C2009', invId: null, label: 'Advance (30%)', amount: '₹50L', amountNum: 5000000, method: '—', status: 'scheduled', date: 'Scheduled 15 Jul 2026', owner: 'fa'),
      ];
}
