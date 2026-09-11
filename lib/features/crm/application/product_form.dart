import '../domain/entities/view_schema.dart';

/// The Add-product sheet's schema handling, kept out of the widget.
///
/// Pure so it can be tested without pumping a sheet — and because getting it
/// wrong is a whole-form failure rather than a cosmetic one: a field the schema
/// should not own renders as a box whose value the API discards, and a payload
/// key that should not be sent is a `400` or, worse, a silent overwrite.
///
/// Section references are to `docs-flutter/docs-backend/products.md`.

/// The fields the sheet owns itself, which the schema-driven form must not
/// render.
///
/// Every one of them would otherwise be a box that accepts input and throws it
/// away:
///
/// * **`product_name`** — the modal renders it explicitly as its first input,
///   which is exactly why §1 excludes it from the schema's form field list. A
///   deployment that does include it would draw a second name box that the
///   explicit one overwrites on submit.
/// * **`item_type`** — a model choice, so the schema reports its `choices` and
///   a form would render a picker for a value the Products/Packages toggle has
///   already decided and that **cannot be changed after create** (§4).
/// * **`price` on a package** — recomputed from the components on every write
///   (§7), so whatever is typed is overwritten server-side.
/// * **`is_active` on a package** — an active package with no components is a
///   `400` (§7), and this sheet has no component editor.
Set<String> productFormOwnedColumns({required bool isPackage}) => {
      'product_name',
      'item_type',
      if (isPackage) ...{'price', 'is_active'},
    };

/// The org's layout minus [productFormOwnedColumns].
///
/// An empty result is the documented "no opinion" value — mock mode, a failed
/// fetch, an org with no config — which the sheet reads as "render the built-in
/// form".
ViewSchema productFormSchema(ViewSchema schema, {required bool isPackage}) {
  final owned = productFormOwnedColumns(isPackage: isPackage);
  return ViewSchema(
    columns: [
      for (final c in schema.columns)
        if (!owned.contains(c.name)) c,
    ],
    hasOrgConfig: schema.hasOrgConfig,
  );
}

/// The `POST /crm/products/` body: what the schema-driven form collected, plus
/// the two keys the modal owns.
///
/// [formPayload] is the form's own output — already keyed by the API's field
/// names, so a field an admin adds tomorrow is saved with no code change here.
Map<String, dynamic> productCreatePayload(
  Map<String, dynamic> formPayload, {
  required String name,
  required bool isPackage,
}) {
  // A create has nothing to clear, so an empty box means "not provided" rather
  // than "blank this out" — the key is dropped and the server applies its own
  // default. `product_code` is unique per org (§3), so posting `""` stores
  // *the empty code* rather than no code and the next blank create collides
  // with it; `hsn_sac` and `product_type` are nullable, and `tax_rate`
  // defaults to 0. Booleans and numbers are untouched.
  final payload = <String, dynamic>{...formPayload}
    ..removeWhere((_, v) => v is String && v.trim().isEmpty);

  payload['product_name'] = name.trim();
  // Set once, at create, and immutable afterwards (§4).
  payload['item_type'] = isPackage ? 'package' : 'product';

  if (isPackage) {
    // Belt and braces with [productFormOwnedColumns]: the price is derived
    // from the composition (§7) and an active package needs components, so
    // neither may reach the API from a sheet that cannot edit components.
    payload.remove('price');
    payload['is_active'] = false;
    // Replace-wholesale sets (§7): omitting them leaves any existing ones
    // alone, which is what a create with no component editor wants.
    payload.remove('components');
    payload.remove('adjustments');
  }
  return payload;
}
