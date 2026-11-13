import 'package:intl/intl.dart';

import '../../../core/utils/relative_time.dart';
import 'customer_detail_rules.dart' show webMoney;
import 'quote_lifecycle.dart' show fmtQuoteDate, planTypeLabel;

// The webapp's plan-4.1 lead fields (`dealFields.ts` / `dealFieldFormat.ts` /
// `dealInfoFields.ts`): which detail group a field belongs to, how it reads and
// how an edit is shaped for the API. Pure, so the lead detail page and its tests
// share one table.

/// The detail section a plan-4.1 field sits under.
enum DealGroup { deal, billing, commercial, consent }

/// How a field is edited and displayed (webapp `DealFieldKind`).
enum DealKind {
  text,
  textarea,
  money,
  date,
  tristate,
  choice,
  state,
  gstin,
  pincode,
  datetime,
  integer
}

const _dealNames = [
  'designation',
  'requirement',
  'budget_min',
  'budget_max',
  'expected_close_date',
  'desired_start_date',
  'decision_maker',
  'competitors',
  'current_vendor',
  'deal_type',
];
const _addressParts = [
  'address_line1',
  'address_line2',
  'city',
  'state_code',
  'pincode',
  'country'
];
const _commercialNames = [
  'payment_preference',
  'po_reference',
  'preferred_language'
];
const _consentNames = ['consent_captured_at', 'consent_notice_version'];

final Map<String, DealGroup> _groupByName = {
  for (final n in _dealNames) n: DealGroup.deal,
  for (final p in _addressParts) 'billing_$p': DealGroup.billing,
  for (final p in _addressParts) 'delivery_$p': DealGroup.billing,
  'gstin': DealGroup.billing,
  for (final n in _commercialNames) n: DealGroup.commercial,
  for (final n in _consentNames) n: DealGroup.consent,
};

const Map<String, DealKind> _kindByName = {
  'designation': DealKind.text,
  'requirement': DealKind.textarea,
  'budget_min': DealKind.money,
  'budget_max': DealKind.money,
  'expected_close_date': DealKind.date,
  'desired_start_date': DealKind.date,
  'decision_maker': DealKind.tristate,
  'competitors': DealKind.textarea,
  'current_vendor': DealKind.text,
  'deal_type': DealKind.choice,
  'billing_address_line1': DealKind.text,
  'billing_address_line2': DealKind.text,
  'billing_city': DealKind.text,
  'billing_state_code': DealKind.state,
  'billing_pincode': DealKind.pincode,
  'billing_country': DealKind.text,
  'delivery_address_line1': DealKind.text,
  'delivery_address_line2': DealKind.text,
  'delivery_city': DealKind.text,
  'delivery_state_code': DealKind.state,
  'delivery_pincode': DealKind.pincode,
  'delivery_country': DealKind.text,
  'gstin': DealKind.gstin,
  'payment_preference': DealKind.choice,
  'po_reference': DealKind.text,
  'preferred_language': DealKind.text,
  'consent_captured_at': DealKind.datetime,
  'consent_notice_version': DealKind.integer,
};

/// The group of a plan-4.1 field, or null for any other field.
DealGroup? dealGroupOf(String name) => _groupByName[name];

/// The edit / display kind of a plan-4.1 field, or null for any other field.
DealKind? dealKindOf(String name) => _kindByName[name];

/// Section headings, in the order the sections render (consent is a line).
const Map<DealGroup, String> dealGroupTitles = {
  DealGroup.deal: 'Deal',
  DealGroup.billing: 'Billing & delivery',
  DealGroup.commercial: 'Commercial',
  DealGroup.consent: 'Consent',
};

const List<DealGroup> dealGroupOrder = [
  DealGroup.deal,
  DealGroup.billing,
  DealGroup.commercial
];

const String moneyInputError = 'Enter an amount, e.g. 150000 or 150000.50';
const String unknownLabel = 'Unknown';

/// Fixed options of a `choice` field (empty for any other field).
List<(String, String)> dealChoiceOptions(String name) => switch (name) {
      'deal_type' => const [('B2B', 'B2B'), ('B2C', 'B2C')],
      'payment_preference' => [
          for (final v in const [
            'lumpsum',
            'subscription',
            'installment_even',
            'installment_custom'
          ])
            (v, planTypeLabel(v))
        ],
      _ => const [],
    };

/// Decision maker: wire values are `true` / `false` / null (unknown).
const List<(String, String)> decisionMakerOptions = [
  ('true', 'Yes'),
  ('false', 'No')
];

bool _blank(Object? v) => v == null || (v is String && v.trim().isEmpty);

/// What a field reads as on the detail ('' when blank — the caller picks its
/// own empty marker). [stateName] resolves a state code ("Kerala (32)").
String formatDealValue(String name, Object? value,
    {String Function(String?)? stateName}) {
  final kind = dealKindOf(name);
  if (kind == DealKind.tristate) {
    return value == true
        ? 'Yes'
        : value == false
            ? 'No'
            : '';
  }
  if (_blank(value)) return '';
  final text = '$value'.trim();
  switch (kind) {
    case DealKind.money:
      final n = num.tryParse(text);
      return n == null ? text : webMoney(n);
    case DealKind.date:
      final d = fmtQuoteDate(text);
      return d.isEmpty ? text : d;
    case DealKind.datetime:
      return _dateTime(text) ?? text;
    case DealKind.state:
      return stateName == null ? text : stateName(text);
    case DealKind.choice:
      return name == 'payment_preference' ? planTypeLabel(text) : text;
    case DealKind.integer:
      return name == 'consent_notice_version' ? 'v$text' : text;
    default:
      return text;
  }
}

String? _dateTime(String iso) {
  final at = parseApiDate(iso);
  return at == null
      ? null
      : DateFormat('dd/MM/yyyy, HH:mm').format(at.toLocal());
}

/// "08 Oct 2026, 14:05 · notice v3" — null when no consent was captured (the
/// line is then left out rather than shown empty).
String? consentLine(Object? capturedAt, Object? version) {
  final when = capturedAt is String ? _dateTime(capturedAt) : null;
  final hasVersion =
      version is num || (version is String && version.trim().isNotEmpty);
  if (when == null && !hasVersion) return null;
  return [if (when != null) when else '—', if (hasVersion) 'notice v$version']
      .join(' · ');
}

/// Row label of the consent line.
const String consentRowLabel = 'Captured on';

/// The wire value for one edited field: ok with the value (null clears), or the
/// message to show beside the field. The server still validates (GSTIN
/// checksum, PIN, budget range …).
({bool ok, Object? value, String? error}) toDealWire(
    DealKind kind, String raw) {
  final t = raw.trim();
  if (t.isEmpty) return (ok: true, value: null, error: null);
  switch (kind) {
    case DealKind.money:
      final cleaned = t.replaceAll(RegExp(r'[,\s₹]'), '');
      if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(cleaned)) {
        return (ok: false, value: null, error: moneyInputError);
      }
      final parts = cleaned.split('.');
      final frac = (parts.length > 1 ? parts[1] : '').padRight(2, '0');
      return (ok: true, value: '${parts[0]}.$frac', error: null);
    case DealKind.tristate:
      return (
        ok: true,
        value: t == 'true'
            ? true
            : t == 'false'
                ? false
                : null,
        error: null
      );
    case DealKind.gstin:
      return (
        ok: true,
        value: t.replaceAll(RegExp(r'\s+'), '').toUpperCase(),
        error: null
      );
    default:
      return (ok: true, value: t, error: null);
  }
}
