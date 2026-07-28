import '../../../domain/entities/product.dart';

/// Static product/catalog seed — a 1:1 port of the prototype's `products` array.
/// This is the ONLY place catalog sample data lives. To integrate the API,
/// replace this class with a remote data source returning `List<Product>`.
class ProductsMockDataSource {
  const ProductsMockDataSource();

  List<Product> fetchProducts() => const [
        Product(id: 'FO-TURNKEY', name: 'Turnkey Office Fit-out', kind: 'product', cat: 'Fit-out', hsn: '995461', unit: 'per sq.ft.', price: '₹2,400', gst: 18, gstAmt: '₹432', gross: '₹2,832', deals: 18, revenue: '₹8.64Cr', revNum: 86400000, avg: '₹48L', active: true, desc: 'End-to-end design-and-build fit-out covering civil, ceiling, flooring, electrical and finishes. Delivered turnkey against a single per-sq.ft. rate.', notes: [ProductNote(author: 'Anjana Menon', time: '3 days ago', body: 'Rate card revised for FY27 — new quotes pick up ₹2,400 automatically.')]),
        Product(id: 'FO-PHASE1', name: 'Interior Fit-out — Phase 1', kind: 'product', cat: 'Fit-out', hsn: '995461', unit: 'per sq.ft.', price: '₹1,850', gst: 18, gstAmt: '₹333', gross: '₹2,183', deals: 24, revenue: '₹7.03Cr', revNum: 70300000, avg: '₹29.3L', active: true),
        Product(id: 'DS-CONCEPT', name: 'Concept & Space Planning', kind: 'product', cat: 'Design Services', hsn: '998391', unit: 'per project', price: '₹2,50,000', gst: 18, gstAmt: '₹45,000', gross: '₹2,95,000', deals: 31, revenue: '₹77.5L', revNum: 7750000, avg: '₹2.5L', active: true),
        Product(id: 'FN-WKSTN', name: 'Modular Workstations', kind: 'product', cat: 'Furniture', hsn: '940310', unit: 'per seat', price: '₹14,500', gst: 18, gstAmt: '₹2,610', gross: '₹17,110', deals: 22, revenue: '₹4.79Cr', revNum: 47900000, avg: '₹21.8L', active: true),
        Product(id: 'JN-RECEP', name: 'Reception Joinery', kind: 'product', cat: 'Joinery', hsn: '940360', unit: 'per unit', price: '₹3,20,000', gst: 18, gstAmt: '₹57,600', gross: '₹3,77,600', deals: 14, revenue: '₹44.8L', revNum: 4480000, avg: '₹3.2L', active: true),
        Product(id: 'FN-LOOSE', name: 'Loose Furniture Package', kind: 'product', cat: 'Furniture', hsn: '940179', unit: 'per package', price: '₹9,00,000', gst: 18, gstAmt: '₹1,62,000', gross: '₹10,62,000', deals: 9, revenue: '₹81L', revNum: 8100000, avg: '₹9L', active: true),
        Product(id: 'MEP-AV', name: 'Conference Room AV', kind: 'product', cat: 'MEP & Services', hsn: '851830', unit: 'per room', price: '₹4,80,000', gst: 18, gstAmt: '₹86,400', gross: '₹5,66,400', deals: 12, revenue: '₹57.6L', revNum: 5760000, avg: '₹4.8L', active: true),
        Product(id: 'FO-ACOUS', name: 'Acoustic Treatment', kind: 'product', cat: 'Fit-out', hsn: '995461', unit: 'per sq.ft.', price: '₹420', gst: 18, gstAmt: '₹76', gross: '₹496', deals: 8, revenue: '₹33.6L', revNum: 3360000, avg: '₹4.2L', active: true),
        Product(id: 'MEP-HVAC', name: 'MEP & HVAC Works', kind: 'product', cat: 'MEP & Services', hsn: '995461', unit: 'per project', price: '₹12,00,000', gst: 18, gstAmt: '₹2,16,000', gross: '₹14,16,000', deals: 11, revenue: '₹1.32Cr', revNum: 13200000, avg: '₹12L', active: true),
        Product(id: 'AMC-STD', name: 'Annual Maintenance Contract', kind: 'product', cat: 'AMC / Maintenance', hsn: '998719', unit: 'per year', price: '₹1,80,000', gst: 18, gstAmt: '₹32,400', gross: '₹2,12,400', deals: 16, revenue: '₹28.8L', revNum: 2880000, avg: '₹1.8L', active: true),
        Product(id: 'DS-SUPER', name: 'Site Supervision', kind: 'product', cat: 'Design Services', hsn: '998391', unit: 'per month', price: '₹85,000', gst: 18, gstAmt: '₹15,300', gross: '₹1,00,300', deals: 7, revenue: '₹6L', revNum: 600000, avg: '₹86K', active: true),
        Product(id: 'DS-3DVIZ', name: '3D Visualisation', kind: 'product', cat: 'Design Services', hsn: '998391', unit: 'per project', price: '₹1,20,000', gst: 18, gstAmt: '₹21,600', gross: '₹1,41,600', deals: 3, revenue: '₹3.6L', revNum: 360000, avg: '₹1.2L', active: false),
        Product(id: 'PKG-OFFICE', name: 'Office Starter Package', kind: 'package', cat: 'Package', hsn: '995461', unit: 'per package', price: '₹18,50,000', gst: 18, gstAmt: '₹3,33,000', gross: '₹21,83,000', deals: 6, revenue: '₹1.11Cr', revNum: 11100000, avg: '₹18.5L', active: true, desc: 'Bundled fit-out, modular workstations and conference AV for 20-seat offices — one line item, one rate.'),
        Product(id: 'PKG-RETAIL', name: 'Retail Refresh Package', kind: 'package', cat: 'Package', hsn: '995461', unit: 'per store', price: '₹9,50,000', gst: 18, gstAmt: '₹1,71,000', gross: '₹11,21,000', deals: 4, revenue: '₹38L', revNum: 3800000, avg: '₹9.5L', active: true, desc: 'Facade refresh, lighting rework and display joinery for retail stores up to 2,000 sq.ft.'),
      ];
}
