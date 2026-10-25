import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/network/paginated.dart';
import '../../domain/entities/crm_catalog.dart';

// The two record-lifecycle flows the webapp runs from a lead or customer
// detail page: moving it to a Lost status (a reason is required, open invoices
// are checked first) and converting a won lead into a customer.

/// The org's active lost reasons — `GET /crm/lead-lost-reasons/` (leads and
/// customers share the list, as on the webapp).
final leadLostReasonsProvider = FutureProvider.autoDispose<List<CatalogOption>>((ref) async {
  final body = await ref.read(apiServiceProvider).get(
    ApiEndpoints.leadLostReasons,
    query: {'page_size': 100, 'is_active': true},
    quiet: true,
  );
  return [
    for (final r in Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results)
      if (r['is_active'] != false && r['lead_lost_reason_id'] != null)
        CatalogOption(id: '${r['lead_lost_reason_id']}', name: '${r['name'] ?? ''}'),
  ];
});

/// One unpaid issued invoice that a Lost move would credit.
class LostInvoice {
  const LostInvoice({required this.number, required this.date, required this.amountDue, this.leadName});

  final String number;
  final String date;
  final Object? amountDue;
  final String? leadName;
}

/// `GET /crm/{leads|customers}/{id}/lost-impact/` — what moving the record to
/// Lost would close. The customer variant also reports the deals it closes.
class LostImpact {
  const LostImpact({
    this.openInvoices = const [],
    this.openAmountDue,
    this.canCredit = false,
    this.openInstalments = 0,
    this.openInstalmentsAmount = 0,
    this.draftInvoices = 0,
    this.moneyReceived = 0,
    this.customerCredit,
    this.upsellLeads = const [],
    this.otherQuotes = const [],
  });

  factory LostImpact.fromJson(Map<String, dynamic> j) {
    double num0(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
    List<Map<String, dynamic>> rows(Object? v) =>
        v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];
    final instalments = rows(j['open_instalments']).where((r) => r['invoiced'] != true).toList();
    final money = j['money_received'] is Map ? Map<String, dynamic>.from(j['money_received'] as Map) : const <String, dynamic>{};
    return LostImpact(
      openInvoices: [
        for (final r in rows(j['open_invoices']))
          LostInvoice(
            number: '${r['number'] ?? r['document_number'] ?? ''}',
            date: '${r['date'] ?? r['document_date'] ?? ''}',
            amountDue: r['amount_due'],
            leadName: r['lead_name']?.toString(),
          ),
      ],
      openAmountDue: j['open_amount_due'],
      canCredit: j['can_credit'] == true,
      openInstalments: instalments.length,
      openInstalmentsAmount: instalments.fold<double>(0, (s, r) => s + num0(r['amount_expected'])),
      draftInvoices: rows(j['draft_invoices']).length,
      moneyReceived: num0(money['amount']),
      customerCredit: money['customer_credit'],
      upsellLeads: [for (final r in rows(j['upsell_leads'])) '${r['lead_name'] ?? ''}'],
      otherQuotes: [for (final r in rows(j['legacy_quotes'])) '${r['quotation_number'] ?? ''}'],
    );
  }

  final List<LostInvoice> openInvoices;
  final Object? openAmountDue;
  final bool canCredit;
  final int openInstalments;
  final double openInstalmentsAmount;
  final int draftInvoices;
  final double moneyReceived;
  final Object? customerCredit;
  final List<String> upsellLeads;
  final List<String> otherQuotes;

  bool get hasOpenInvoices => openInvoices.isNotEmpty;

  /// Open invoices the user cannot credit: the move is blocked.
  bool get blocked => hasOpenInvoices && !canCredit;
}

/// Which record a Lost move is for: `('lead' | 'customer', id)`.
typedef LostTarget = (String kind, String id);

/// The impact check, run when the Lost sheet opens. Null when the check
/// itself failed — the sheet then lets the move go ahead and the server's own
/// 409 guard still applies.
final lostImpactProvider = FutureProvider.autoDispose.family<LostImpact?, LostTarget>((ref, t) async {
  // A lead still being created has nothing to close yet.
  if (t.$2.isEmpty) return null;
  try {
    final body = await ref.read(apiServiceProvider).get(
          t.$1 == 'customer' ? ApiEndpoints.customerLostImpact(t.$2) : ApiEndpoints.leadLostImpact(t.$2),
          quiet: true,
        );
    return body is Map ? LostImpact.fromJson(Map<String, dynamic>.from(body)) : const LostImpact();
  } on AppError {
    return null;
  }
});

/// What the user chose in the Lost sheet — the fields the PATCH carries.
class LostChoice {
  const LostChoice({required this.reasonId, this.note = '', this.creditOpenInvoices = false});

  final String reasonId;
  final String note;
  final bool creditOpenInvoices;

  Map<String, dynamic> toBody() => {
        'lost_reason': reasonId,
        if (note.trim().isNotEmpty) 'lost_reason_note': note.trim(),
        if (creditOpenInvoices) 'credit_open_invoices': true,
      };
}

// ── Conversion ──

/// A lead's conversion state, read from the record (`GET /crm/leads/{id}/`).
/// List rows omit these keys, so the detail screen reads the raw record.
class LeadConversion {
  const LeadConversion({
    this.isConverted = false,
    this.customerId,
    this.customerName,
    this.pendingApproval = false,
    this.waitingForQuote = false,
    this.lostReasonName,
    this.lostReasonNote,
  });

  factory LeadConversion.fromRow(Map<String, dynamic>? row, {required bool isWon}) {
    if (row == null) return const LeadConversion();
    final customer = row['converted_customer'];
    final requiresApproval = row['conversion_requires_approval'] == true;
    final converted = row['is_converted'] == true;
    String? str(Object? v) {
      final s = v?.toString().trim();
      return s == null || s.isEmpty ? null : s;
    }

    return LeadConversion(
      isConverted: converted,
      customerId: customer is Map ? str(customer['customer_id']) : null,
      customerName: customer is Map ? str(customer['name']) : null,
      pendingApproval: requiresApproval && row['pending_conversion'] is Map,
      waitingForQuote: isWon && !converted && row['conversion_mode'] == 'quote' && row['has_accepted_quote'] == false,
      lostReasonName: str(row['lost_reason_name']),
      lostReasonNote: str(row['lost_reason_note']),
    );
  }

  final bool isConverted;
  final String? customerId;
  final String? customerName;
  final bool pendingApproval;
  final bool waitingForQuote;
  final String? lostReasonName;
  final String? lostReasonNote;

  /// Webapp `lostReasonText`: "name — note", either alone, or the fallback.
  String get lostReasonText {
    if (lostReasonName != null && lostReasonNote != null) return '$lostReasonName — $lostReasonNote';
    return lostReasonName ?? lostReasonNote ?? 'No reason recorded';
  }
}

/// A `409 CUSTOMER_MATCH` answer to a convert: customers that already look
/// like this lead.
class CustomerMatch {
  const CustomerMatch({
    required this.message,
    this.candidates = const [],
    this.hiddenCount = 0,
    this.suggestedName = '',
    this.nameTaken = false,
  });

  factory CustomerMatch.fromError(AppError e) {
    final c = e.causeMap;
    return CustomerMatch(
      message: e.message,
      candidates: [
        for (final r in (c['candidates'] is List ? c['candidates'] as List : const []))
          if (r is Map && r['customer_id'] != null)
            MatchCandidate(
              id: '${r['customer_id']}',
              name: '${r['name'] ?? ''}',
              reference: '${r['reference'] ?? ''}',
              email: r['email']?.toString() ?? '',
              phone: r['phone']?.toString() ?? '',
              matchOn: [for (final k in (r['match_on'] is List ? r['match_on'] as List : const [])) '$k'],
            ),
      ],
      hiddenCount: (c['hidden_count'] as num?)?.toInt() ?? 0,
      suggestedName: '${c['suggested_name'] ?? ''}',
      nameTaken: c['name_taken'] == true,
    );
  }

  final String message;
  final List<MatchCandidate> candidates;
  final int hiddenCount;
  final String suggestedName;
  final bool nameTaken;

  /// Webapp `ConvertCustomerMatchDialog` name check; null when the name is fine.
  String? nameProblem(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return 'Enter a name for the new customer.';
    if (nameTaken && name.toLowerCase() == suggestedName.trim().toLowerCase()) {
      return 'A customer named “$suggestedName” already exists. Enter a different name.';
    }
    for (final c in candidates) {
      if (c.name.trim().toLowerCase() == name.toLowerCase()) {
        return '“${c.name}” already exists. Enter a different name, or attach the lead to it.';
      }
    }
    return null;
  }
}

class MatchCandidate {
  const MatchCandidate({
    required this.id,
    required this.name,
    required this.reference,
    required this.email,
    required this.phone,
    required this.matchOn,
  });

  final String id;
  final String name;
  final String reference;
  final String email;
  final String phone;
  final List<String> matchOn;

  /// "Same name and email", or "Possible match" when the server named no key.
  String get matchLabel {
    if (matchOn.isEmpty) return 'Possible match';
    final keys = matchOn.join(' and ');
    return 'Same $keys';
  }
}

/// The outcome of `POST /crm/leads/{id}/convert/`.
sealed class ConvertResult {
  const ConvertResult();
}

/// 201: a customer was created, or the lead was attached to an existing one.
class Converted extends ConvertResult {
  const Converted({required this.customerId, required this.customerName, required this.attached});

  final String customerId;
  final String customerName;
  final bool attached;
}

/// 202: the org requires approval; a request was raised.
class ConversionRequested extends ConvertResult {
  const ConversionRequested();
}

/// 409 CUSTOMER_MATCH: the user must attach to a candidate or name a new one.
class NeedsCustomerChoice extends ConvertResult {
  const NeedsCustomerChoice(this.match);

  final CustomerMatch match;
}

/// Converts [leadId]. [body] is `{}` for a plain convert, or the match
/// dialog's `{attach_to_customer_id}` / `{create_new_customer, customer_name}`.
/// Other refusals (not Won, already converted, 403) throw their [AppError].
Future<ConvertResult> convertLead(WidgetRef ref, String leadId, [Map<String, dynamic> body = const {}]) async {
  try {
    final res = await ref.read(apiServiceProvider).post(ApiEndpoints.leadConvert(leadId), body: body);
    final map = res is Map ? Map<String, dynamic>.from(res) : const <String, dynamic>{};
    if (map['approval_id'] != null && map['customer_id'] == null) return const ConversionRequested();
    return Converted(
      customerId: '${map['customer_id'] ?? ''}',
      customerName: '${map['name'] ?? ''}',
      attached: map['attached_to_existing'] == true,
    );
  } on AppError catch (e) {
    if (e.statusCode == 409 && e.code == 'CUSTOMER_MATCH') {
      return NeedsCustomerChoice(CustomerMatch.fromError(e));
    }
    rethrow;
  }
}
