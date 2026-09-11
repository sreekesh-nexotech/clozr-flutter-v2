// The Add product / Add package form is built from the org's own Product
// layout, so two workspaces with different column orders must get different
// forms. These run the **real** `GET /crm/products/schema/?view_type=detail`
// bodies from two live orgs (captured 2026-09-11) through `productFormSchema`,
// which is the only way to tell "follows the org" apart from "happens to match
// a hardcoded list".
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/application/product_form.dart';
import 'package:clozrapp/features/crm/domain/entities/view_schema.dart';

ViewSchema _schemaFrom(String fixture) {
  final body = jsonDecode(File('test/fixtures/$fixture').readAsStringSync());
  return ViewSchema.fromResponse(body as Map<String, dynamic>);
}

List<String> _formOrder(String fixture) => [
      for (final c in productFormSchema(_schemaFrom(fixture), isPackage: false)
          .editableColumns)
        c.name,
    ];

void main() {
  test('both orgs configure a Product layout, ordered differently', () {
    // If these ever matched, the test below would prove nothing.
    expect(_schemaFrom('ps_det_acme.json').hasOrgConfig, isTrue);
    expect(_schemaFrom('ps_det_nexo.json').hasOrgConfig, isTrue);
    expect(_formOrder('ps_det_acme.json'),
        isNot(equals(_formOrder('ps_det_nexo.json'))));
  });

  test('the form follows each org own order', () {
    // Acme puts the code before the category; Nexotech the reverse, and its
    // price sits after HSN rather than before the currency.
    expect(_formOrder('ps_det_acme.json').take(6),
        ['product_code', 'product_type', 'billing_unit', 'price', 'currency', 'hsn_sac']);

    expect(_formOrder('ps_det_nexo.json').take(6),
        ['product_type', 'billing_unit', 'product_code', 'hsn_sac', 'price', 'tax_rate']);
  });

  test('the two columns the modal owns are never rendered as inputs', () {
    for (final fixture in ['ps_det_acme.json', 'ps_det_nexo.json']) {
      final order = _formOrder(fixture);
      // `product_name` is the modal's own required first box, and `item_type`
      // is the product/package toggle — immutable after create.
      expect(order, isNot(contains('product_name')), reason: fixture);
      expect(order, isNot(contains('item_type')), reason: fixture);
    }
  });

  test("the org spare columns still reach the form, under the backend own labels",
      () {
    // The backend returns no human label for these six — `label` comes back as
    // the raw column name — so the form shows "c_date_1" rather than
    // "C Date 1". Faithful to the payload; a backend gap, not an app one.
    // Pinned here so a future label fix is a deliberate change, not a surprise.
    final columns = productFormSchema(_schemaFrom('ps_det_acme.json'),
            isPackage: false)
        .editableColumns;
    final byName = {for (final c in columns) c.name: c.label};

    expect(byName['c_date_1'], 'c_date_1');
    expect(byName['custom_fields'], 'custom_fields');
    // The real fields do carry proper labels, so this is specific to the spares.
    expect(byName['product_code'], 'SKU / Code');
    expect(byName['tax_rate'], 'GST Rate');
  });
}
