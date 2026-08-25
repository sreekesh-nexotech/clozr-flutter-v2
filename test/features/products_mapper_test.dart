import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/products_remote_ds.dart';
import 'package:clozrapp/features/crm/application/filters/products_filter_spec.dart';
import 'package:clozrapp/features/crm/application/products_counts.dart';
import 'package:clozrapp/features/crm/domain/entities/audit_entry.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/audit_log_remote_ds.dart';
import 'package:clozrapp/features/crm/domain/entities/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('productFromApi', () {
    test('maps a full row: money strings, gst/gross computed, category kept', () {
      final p = productFromApi({
        'product_id': 'uuid-1',
        'product_name': 'Turnkey Office Fit-out',
        'product_type': {'name': 'Fit-out'},
        'hsn_code': '995461',
        'unit': 'per sq.ft.',
        'price': '2400.00',
        'is_active': true,
        'description': 'End-to-end fit-out.',
      })!;

      expect(p.id, 'uuid-1');
      expect(p.name, 'Turnkey Office Fit-out');
      expect(p.kind, 'product');
      expect(p.cat, 'Fit-out');
      expect(p.hsn, '995461');
      expect(p.unit, 'per sq.ft.');
      expect(p.price, '₹2.4K');
      expect(p.gst, 18);
      expect(p.gstAmt, '₹432');
      expect(p.gross, '₹2.8K');
      expect(p.active, isTrue);
      expect(p.desc, 'End-to-end fit-out.');
    });

    test('defensive defaults on a minimal row', () {
      final p = productFromApi({'product_id': 'uuid-min'})!;

      expect(p.name, '');
      expect(p.kind, 'product');
      expect(p.cat, '');
      expect(p.hsn, '');
      expect(p.unit, '');
      expect(p.price, '₹0');
      expect(p.gst, 18);
      expect(p.deals, 0);
      expect(p.revenue, '₹0');
      expect(p.revNum, 0);
      expect(p.avg, '—');
      expect(p.active, isTrue);
      expect(p.desc, isNull);
      expect(p.notes, isEmpty);
    });

    test('package detection from type/category naming; inactive respected', () {
      final byType = productFromApi({
        'product_id': 'uuid-pkg',
        'product_name': 'Office Starter',
        'product_type': {'name': 'Interior Package'},
        'is_active': false,
      })!;
      expect(byType.kind, 'package');
      expect(byType.cat, 'Interior Package');
      expect(byType.active, isFalse);

      final byCategory = productFromApi({
        'product_id': 'uuid-pkg2',
        'product_name': 'Retail Refresh',
        'category': 'package',
      })!;
      expect(byCategory.kind, 'package');
    });

    test('field-name variants: category string, tax_percent, usage fields', () {
      final p = productFromApi({
        'product_id': 'uuid-v',
        'product_name': 'Custom Widget',
        'category': 'Custom Widgets',
        'tax_percent': 12,
        'price': 100000,
        'deals': 4,
        'revenue': '800000.00',
      })!;

      // Unknown category kept raw — the list handles unknown keys gracefully.
      expect(p.cat, 'Custom Widgets');
      expect(p.gst, 12);
      expect(p.price, '₹1L');
      expect(p.gstAmt, '₹12K');
      expect(p.gross, '₹1.1L');
      expect(p.deals, 4);
      expect(p.revenue, '₹8L');
      expect(p.revNum, 800000);
      expect(p.avg, '₹2L');
    });

    test('rows without product_id are skipped, never fatal', () {
      expect(productFromApi({'product_name': 'No id'}), isNull);
      final list = productsFromApiRows([
        {'product_name': 'No id'},
        {'product_id': 'uuid-ok', 'product_name': 'Kept'},
        'junk',
        null,
      ]);
      expect(list, hasLength(1));
      expect(list.single.id, 'uuid-ok');
    });
  });

  group('productFromApi — the live serializer', () {
    /// A row exactly as `GET /crm/products/` serves it, verified against the
    /// dev backend.
    Map<String, dynamic> liveRow() => {
          'id': 1,
          'product_id': '37d51ece-a7ca-4752-aa28-6bd3268eb76c',
          'product_name': 'NexoCRM Pro',
          'product_code': 'PRD-NEXOCR-9AF0',
          'item_type': 'product',
          'product_type': 'c9944229-93c7-4e6d-86a5-2723cf0e9584',
          'product_type_name': 'SaaS Platform',
          'description': 'Full-featured CRM.',
          'is_active': true,
          'price': '4999.000000',
          'currency': 'INR',
          'billing_unit': null,
          'hsn_sac': null,
          'tax_rate': '0.00',
        };

    test('the category is the type NAME, never its uuid', () {
      expect(productFromApi(liveRow())!.cat, 'SaaS Platform');
    });

    test('a bare uuid type resolves to no category rather than to itself', () {
      final row = liveRow()..remove('product_type_name');
      expect(productFromApi(row)!.cat, '');
    });

    test('tax_rate is read, so a 0%-rated item is not shown as 18%', () {
      final p = productFromApi(liveRow())!;
      expect(p.gst, 0);
      expect(p.gstAmt, '₹0');
      // Gross equals net when nothing is added on top.
      expect(p.gross, p.price);
    });

    test('a real rate string still parses', () {
      final p = productFromApi(liveRow()..['tax_rate'] = '18.00')!;
      expect(p.gst, 18);
    });

    test('the SKU is kept alongside the uuid', () {
      final p = productFromApi(liveRow())!;
      expect(p.code, 'PRD-NEXOCR-9AF0');
      expect(p.id, '37d51ece-a7ca-4752-aa28-6bd3268eb76c');
    });

    test('hsn_sac fills the HSN column', () {
      expect(productFromApi(liveRow()..['hsn_sac'] = '998314')!.hsn, '998314');
    });

    test('item_type is what makes an item a package', () {
      expect(productFromApi(liveRow())!.kind, 'product');
      expect(productFromApi(liveRow()..['item_type'] = 'package')!.kind, 'package');
    });

    test('a missing tax_rate is unknown, not 18%', () {
      // The org's Product view settings decide which columns the serializer
      // returns, and `tax_rate` is currently switched off — the list and the
      // detail both come back without it. The card must not print a rate then.
      final row = liveRow()..remove('tax_rate');
      final p = productFromApi(row)!;
      expect(p.gstKnown, isFalse);
      expect(p.gst, 18, reason: 'the fallback still drives arithmetic');
    });

    test('a rate that IS sent counts as known, including 0%', () {
      expect(productFromApi(liveRow())!.gstKnown, isTrue);
      expect(productFromApi(liveRow()..['tax_rate'] = '18.00')!.gstKnown, isTrue);
    });

    test('the trimmed 10-field row still maps to a usable product', () {
      // Exactly what `GET /crm/products/` returns under the current org config.
      final p = productFromApi({
        'product_id': '37d51ece-a7ca-4752-aa28-6bd3268eb76c',
        'product_name': 'NexoCRM Pro',
        'product_code': 'PRD-NEXOCR-9AF0',
        'product_type': 'c9944229-93c7-4e6d-86a5-2723cf0e9584',
        'product_type_name': 'SaaS Platform',
        'description': 'Full-featured CRM.',
        'is_active': true,
        'price': '4999.000000',
        'currency': 'INR',
        'custom_fields': <String, dynamic>{},
      })!;
      expect(p.name, 'NexoCRM Pro');
      expect(p.code, 'PRD-NEXOCR-9AF0');
      expect(p.cat, 'SaaS Platform');
      expect(p.price, '₹5K');
      expect(p.gstKnown, isFalse);
      expect(p.hsn, '');
      expect(p.unit, '');
      expect(p.kind, 'product');
    });
  });

  _priceFacetTests();
  _activityTests();
  _packageTests();
  _compositionTests();
  _packagesListTests();
}

/// `products.md` §2 — the drawer's Unit price facet is an absolute-rupee range.
/// It read the *display* string, which `formatInr` abbreviates, so a ₹4,999
/// product filtered as if it cost ₹5.
void _priceFacetTests() {
  group('products filter — unit price', () {
    test('reads the numeric price, not the abbreviated display', () {
      final p = productFromApi({
        'product_id': 'p-1',
        'product_name': 'NexoCRM Pro',
        'price': '4999.000000',
      })!;
      expect(p.price, '₹5K', reason: 'the display is abbreviated');
      expect(productPriceNum(p), 4999);
    });

    test('a six-figure price survives the same way', () {
      final p = productFromApi({'product_id': 'p-2', 'price': '184991.00'})!;
      expect(productPriceNum(p), 184991);
    });

    test('falls back to the display when there is no numeric price', () {
      const p = Product(
        id: 'p-3',
        name: 'Seed row',
        kind: 'product',
        cat: '',
        hsn: '',
        unit: '',
        price: '₹2,400',
        gst: 18,
        gstAmt: '₹432',
        gross: '₹2,832',
        deals: 0,
        revenue: '₹0',
        revNum: 0,
        avg: '—',
        active: true,
      );
      expect(productPriceNum(p), 2400);
    });
  });

}

/// The product detail's Activity card reads the shared audit trail
/// (`?model_name=Product`), since `products.md` documents no per-product feed.
/// The fixture is a real row from the dev backend.
void _activityTests() {
  group('product activity log', () {
    Map<String, dynamic> createRow() => {
          'audit_log_id': '27da1152-f5a2-45be-b460-f1f54af7e7c4',
          'user_full_name': 'Admin Acme',
          'user_email': 'admin@seed.acme.com',
          'action': 'create',
          'model_name': 'Product',
          'record_id': 'a548cbec-4980-4845-b232-fd6b76098fde',
          'changes': {
            'request_body': {
              'product_name': 'test products 3',
              'product_code': 'test',
              'billing_unit': 'per seat',
              'hsn_sac': '12234',
              'tax_rate': 5,
              'price': 14005880,
            },
          },
          'timestamp': '2026-08-17T10:53:16.811259Z',
        };

    test('a create reads as the product being created, by whom', () {
      final e = AuditLogRemoteDataSource.mapEntry(createRow(), recordLabel: 'Product')!;
      expect(e.title, 'Product created');
      expect(e.kind, AuditEventKind.created);
      expect(e.actor, 'Admin Acme');
      expect(e.at, isNotNull);
    });

    test('the label is what keeps it from saying "Lead created"', () {
      final e = AuditLogRemoteDataSource.mapEntry(createRow())!;
      expect(e.title, 'Lead created', reason: 'the default label, wrong here');
    });

    test('an update maps to an edit rather than a creation', () {
      final e = AuditLogRemoteDataSource.mapEntry(
          {...createRow(), 'action': 'update'},
          recordLabel: 'Product')!;
      expect(e.kind, isNot(AuditEventKind.created));
    });

    test('rows are skipped, never fatal, when they carry nothing', () {
      expect(AuditLogRemoteDataSource.mapEntries(const [null, 'x', 42]), isEmpty);
    });
  });
}

/// A package is only distinguishable by `item_type` — which this org's view
/// config strips from the payload. `products.md` §7 gives packages six computed
/// totals that plain products never carry, so those identify one instead.
void _packageTests() {
  group('package detection', () {
    /// A package row exactly as the live list serves it: no `item_type`, but
    /// the totals a package always carries.
    Map<String, dynamic> packageRow() => {
          'product_id': 'pkg-1',
          'product_name': 'test package',
          'price': '1500.000000',
          'components_subtotal_excl': '2000.00',
          'components_subtotal_incl': '2360.00',
          'adjustments_total_excl': '-500.00',
          'computed_total_excl': '1500.00',
          'computed_total_incl': '1860.00',
        };

    test('the computed totals identify a package when item_type is stripped', () {
      expect(productFromApi(packageRow())!.kind, 'package');
    });

    test('an explicit item_type still wins', () {
      final row = packageRow()..['item_type'] = 'product';
      expect(productFromApi(row)!.kind, 'product',
          reason: 'never override what the serializer actually said');
      expect(productFromApi({...packageRow(), 'item_type': 'package'})!.kind, 'package');
    });

    test('a plain product carries none of them and stays a product', () {
      final p = productFromApi({
        'product_id': 'p-1',
        'product_name': 'NexoCRM Pro',
        'price': '4999.000000',
      })!;
      expect(p.kind, 'product');
    });

    test('the derived price is the package total, not a sent one', () {
      // §7: `price` is recomputed from the composition on every write.
      expect(productFromApi(packageRow())!.priceNum, 1500);
    });
  });
}

/// `products.md` §7. The fixture is the doc's own example payload, checked
/// against a package built live on the dev backend.
void _compositionTests() {
  group('package composition', () {
    Map<String, dynamic> docPackage() => {
          'product_id': 'pkg-1',
          'item_type': 'package',
          'product_name': 'Starter Bundle',
          'price': '4998.000000',
          'components': [
            {
              'package_component_id': 'c-1',
              'component_product': 'prod-1',
              'product_name': 'NexoCRM Pro',
              'product_code': 'PRD-NEXOCR-9AF0',
              'billing_unit': 'per seat',
              'quantity': 2,
              'position': 0,
              'unit_price': '4999.000000',
              'tax_rate': '18.00',
              'line_excl': '9998.00',
              'line_incl': '11797.64',
            },
          ],
          'adjustments': [
            {
              'package_adjustment_id': 'a-1',
              'adjustment_type': 'bundle_discount',
              'label': 'Launch offer',
              'amount': '5000.00',
              'tax_rate': '0.00',
              'position': 0,
              'sign': -1,
              'amount_incl': '-5000.00',
            },
          ],
          'components_subtotal_excl': '9998.00',
          'components_subtotal_incl': '11797.64',
          'adjustments_total_excl': '-5000.00',
          'adjustments_total_incl': '-5000.00',
          'computed_total_excl': '4998.00',
          'computed_total_incl': '6797.64',
        };

    test('reads the six totals the server computed', () {
      final c = productFromApi(docPackage())!.composition!;
      expect(c.componentsExcl, 9998.00);
      expect(c.adjustmentsExcl, -5000.00);
      expect(c.totalExcl, 4998.00);
      expect(c.totalIncl, 6797.64);
      // Tax is the difference the server already worked out, not a rate applied.
      expect(c.taxAmount, closeTo(1799.64, 0.01));
    });

    test('reads a component line, priced off its product', () {
      final comp = productFromApi(docPackage())!.composition!.components.single;
      expect(comp.name, 'NexoCRM Pro');
      expect(comp.quantity, 2);
      expect(comp.unitPrice, 4999);
      expect(comp.lineExcl, 9998.00);
    });

    test('a discount keeps a positive amount and carries its sign', () {
      final adj = productFromApi(docPackage())!.composition!.adjustments.single;
      expect(adj.amount, 5000.00, reason: 'stored positive');
      expect(adj.isDiscount, isTrue);
      expect(adj.display, 'Launch offer');
    });

    test('an unlabelled adjustment falls back to its type', () {
      final row = docPackage();
      (row['adjustments'] as List).first['label'] = '';
      final adj = productFromApi(row)!.composition!.adjustments.single;
      expect(adj.display, 'Bundle discount');
    });

    test('totals without line items are still a composition', () {
      // What this org actually returns: the view config withholds the arrays.
      final c = productFromApi({
        'product_id': 'pkg-2',
        'product_name': 'test package',
        'components_subtotal_excl': '2000.00',
        'adjustments_total_excl': '-500.00',
        'computed_total_excl': '1500.00',
        'computed_total_incl': '1860.00',
      })!.composition!;
      expect(c.components, isEmpty);
      expect(c.totalIncl, 1860.00);
    });

    test('a plain product has no composition at all', () {
      final p = productFromApi({'product_id': 'p-1', 'price': '4999.000000'})!;
      expect(p.composition, isNull);
    });
  });
}

/// The Packages tab shares the Products list's chips and drawer, and both were
/// hardcoded to the product side.
void _packagesListTests() {
  Product item({required bool isPackage, String cat = 'SaaS Platform'}) => Product(
        id: isPackage ? 'pkg' : 'prod',
        name: isPackage ? 'test package' : 'NexoCRM Pro',
        kind: isPackage ? 'package' : 'product',
        cat: isPackage ? '' : cat,
        hsn: '',
        unit: '',
        price: '₹0',
        gst: 18,
        gstKnown: false,
        gstAmt: '₹0',
        gross: '₹0',
        deals: 0,
        revenue: '₹0',
        revNum: 0,
        avg: '—',
        active: true,
      );

    group('packages list', () {
    test('the category chips count the open mode, not always products', () {
      final catalog = [item(isPackage: false), item(isPackage: true)];
      expect(prodCatCount(catalog, 'all'), 1, reason: 'products by default');
      expect(prodCatCount(catalog, 'all', mode: 'packages'), 1);
      // The bug: every chip in the Packages tab counted the products behind it.
      expect(prodCatCount(catalog, 'SaaS Platform', mode: 'packages'), 0);
      expect(prodCatCount(catalog, 'SaaS Platform'), 1);
    });

    test('the mode counts split the catalog', () {
      final catalog = [item(isPackage: false), item(isPackage: true), item(isPackage: true)];
      expect(prodModeCount(catalog, 'products'), 1);
      expect(prodModeCount(catalog, 'packages'), 2);
    });
  });
}
