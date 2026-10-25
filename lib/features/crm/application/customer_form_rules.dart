import '../domain/repositories/customers_repository.dart';

// Pure rules behind the Add / Edit customer forms — the webapp's
// `customerAddressForm.ts` and the bits of `AddCustomerModal` that are not UI.
//
// The server validates every address value (GSTIN pattern, checksum and state,
// PIN); the form only shapes what is sent and shows the server's messages under
// the matching inputs.

/// Inline message for an empty name (webapp `AddCustomerModal`).
const customerNameRequiredMessage = 'Enter a customer name';

/// The hint beside the GSTIN input.
const gstinHint = "15 characters; its first two digits are the billing state's GST code.";

/// One input of the address / GSTIN block.
class AddressFieldSpec {
  const AddressFieldSpec(this.name, this.label, this.kind);

  /// The API write key.
  final String name;
  final String label;

  /// `text`, `state`, `pincode` or `gstin`.
  final String kind;
}

List<AddressFieldSpec> _block(String prefix) => [
      AddressFieldSpec('${prefix}_address_line1', 'Address line 1', 'text'),
      AddressFieldSpec('${prefix}_address_line2', 'Address line 2', 'text'),
      AddressFieldSpec('${prefix}_city', 'City', 'text'),
      AddressFieldSpec('${prefix}_state_code', 'State', 'state'),
      AddressFieldSpec('${prefix}_pincode', 'PIN code', 'pincode'),
    ];

final List<AddressFieldSpec> billingAddressFields = List.unmodifiable(_block('billing'));
final List<AddressFieldSpec> deliveryAddressFields = List.unmodifiable(_block('delivery'));
const gstinField = AddressFieldSpec('gstin', 'GSTIN', 'gstin');

/// Every input of the block, in form order.
List<AddressFieldSpec> get allAddressFields =>
    [...billingAddressFields, ...deliveryAddressFields, gstinField];

/// Every column the block owns — kept off the schema-driven part of the form
/// so nothing renders twice — plus the legacy free-text `address`, which the
/// server now fills from the billing block.
final Set<String> addressOwnedColumns = {
  for (final p in const ['billing', 'delivery'])
    for (final part in const ['address_line1', 'address_line2', 'city', 'state_code', 'pincode', 'country'])
      '${p}_$part',
  'gstin',
  'address',
};

bool isAddressFormField(String name) => addressOwnedColumns.contains(name);

/// GSTIN as sent: whitespace removed and upper-cased; null when blank.
String? normalizeGstin(String raw) {
  final t = raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  return t.isEmpty ? null : t;
}

/// One input shaped to its wire value; null when blank.
String? addressWireValue(AddressFieldSpec spec, String raw) {
  if (spec.kind == 'gstin') return normalizeGstin(raw);
  final t = raw.trim();
  return t.isEmpty ? null : t;
}

/// The raw input each key takes its value from: with "Same as billing
/// address" the delivery block repeats the billing one.
String _sourceText(Map<String, String> values, AddressFieldSpec spec, bool sameAsBilling) {
  if (sameAsBilling) {
    final i = deliveryAddressFields.indexWhere((d) => d.name == spec.name);
    if (i >= 0) return values[billingAddressFields[i].name] ?? '';
  }
  return values[spec.name] ?? '';
}

/// The block's part of a **create** body (webapp `addressPayload`): blank
/// inputs are left out.
Map<String, String> customerAddressPayload(Map<String, String> values, {required bool sameAsBilling}) {
  final out = <String, String>{};
  for (final spec in allAddressFields) {
    final v = addressWireValue(spec, _sourceText(values, spec, sameAsBilling));
    if (v != null) out[spec.name] = v;
  }
  return out;
}

String _stored(Map<String, dynamic>? row, AddressFieldSpec spec) {
  final v = row?[spec.name];
  if (v == null) return '';
  return addressWireValue(spec, '$v') ?? '';
}

/// The block's part of an **edit** (PATCH) body: only keys whose value
/// differs from [row]; a cleared input is sent as null so the API clears it.
Map<String, String?> customerAddressPatch(
  Map<String, String> values,
  Map<String, dynamic>? row, {
  required bool sameAsBilling,
}) {
  final out = <String, String?>{};
  for (final spec in allAddressFields) {
    final next = addressWireValue(spec, _sourceText(values, spec, sameAsBilling));
    if ((next ?? '') != _stored(row, spec)) out[spec.name] = next;
  }
  return out;
}

/// The raw input values a record starts the form with.
Map<String, String> addressValuesFromRow(Map<String, dynamic>? row) => {
      for (final spec in allAddressFields)
        spec.name: row?[spec.name] == null ? '' : '${row![spec.name]}',
    };

/// Whether "Same as billing address" starts ticked for [row]: always for a
/// new record, and for a stored one when its delivery block is empty or
/// repeats the billing block.
bool deliveryMatchesBilling(Map<String, dynamic>? row) {
  var allBlank = true;
  var allSame = true;
  for (var i = 0; i < deliveryAddressFields.length; i++) {
    final d = _stored(row, deliveryAddressFields[i]);
    if (d.isNotEmpty) allBlank = false;
    if (d != _stored(row, billingAddressFields[i])) allSame = false;
  }
  return allBlank || allSame;
}

/// The address-block input a server error key belongs to, or null when it is
/// not one of the block's. With "Same as billing address" ticked the delivery
/// inputs are hidden, so their errors land on the billing input they copy; the
/// legacy `address` lands on Address line 1.
String? addressErrorField(String key, {required bool sameAsBilling}) {
  if (key == 'address') return billingAddressFields.first.name;
  if (key.endsWith('_country')) return null;
  if (!isAddressFormField(key)) return null;
  if (sameAsBilling) {
    final i = deliveryAddressFields.indexWhere((d) => d.name == key);
    if (i >= 0) return billingAddressFields[i].name;
  }
  return key;
}

/// DRF `{field: [messages]}` → the first message per field.
Map<String, String> firstFieldErrors(Map<String, List<String>>? errors) => {
      for (final e in (errors ?? const <String, List<String>>{}).entries)
        if (e.value.isNotEmpty) e.key: e.value.first,
    };

/// The status a new customer starts in (webapp `defaultCustomerStatusId`):
/// the org's first `active`-type status, else one with no type, else none
/// (the server then applies its own default). The mobile status catalog does
/// not carry `is_default`, so the active type stands in for it.
String? defaultCustomerStatusId(List<CustomerStatus> statuses) {
  for (final s in statuses) {
    if (s.statusType == 'active') return s.id;
  }
  for (final s in statuses) {
    if (s.statusType.isEmpty) return s.id;
  }
  return null;
}
