import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/network/network_providers.dart';
import '../../../../core/network/paginated.dart';
import '../../domain/entities/call_log.dart';
import '../../infrastructure/data_sources/remote/call_logs_remote_ds.dart';
import '../customer_activity_view.dart';
import 'crm_module_schema_providers.dart';

/// Data for the customer detail's activity tabs that the older
/// `customer_activity_providers.dart` does not carry: payment plans with their
/// instalments, call rows with medium / duration / parent, the customer's
/// `linked_leads` (Opportunities) and the source tags of its notes.
///
/// Same endpoints and params as the webapp (`customers.api.ts`).

ApiService? _api(Ref ref) => ApiConfig.apiEnabled ? ref.watch(apiServiceProvider) : null;

Future<List<Map<String, dynamic>>> _allRows(ApiService api, String path, Map<String, dynamic> query) async {
  final rows = <Map<String, dynamic>>[];
  for (var page = 1; page <= 20; page++) {
    final body = await api.get(path, query: {...query, if (page > 1) 'page': page});
    final chunk = Paginated.fromAny<Map<String, dynamic>>(body, (m) => m);
    rows.addAll(chunk.results);
    if (!chunk.hasMore) break;
  }
  return rows;
}

// ── Payments ──
//
// `GET /quotations/payments/?customer_id=` (plan headers) +
// `GET /quotations/payment-records/?customer_id=` (instalments), joined on the
// plan id — webapp `getCustomerPayments` / `getCustomerPaymentRecords`.

final customerPaymentPlansProvider =
    FutureProvider.autoDispose.family<List<CustomerPayment>, String>((ref, customerId) async {
  final api = _api(ref);
  if (api == null || customerId.isEmpty) return const [];
  final query = {'customer_id': customerId, 'page_size': 100};
  final results = await Future.wait([
    _allRows(api, ApiEndpoints.payments, query),
    _allRows(api, ApiEndpoints.paymentRecords, query),
  ]);
  return customerPaymentsFromRows(results[0], results[1]);
});

// ── Call log ──

/// One call: the webapp row view plus the mapped [CallLog] the shared
/// per-call actions sheet takes.
typedef CustomerCallItem = ({CustomerCallRow row, CallLog log});

final customerCallItemsProvider =
    FutureProvider.autoDispose.family<List<CustomerCallItem>, String>((ref, customerId) async {
  final api = _api(ref);
  if (api == null || customerId.isEmpty) return const [];
  final raw = await CallLogsRemoteDataSource(api)
      .fetchCallLogRowsFor(relatedTo: 'customer', relatedToId: customerId);
  final items = <CustomerCallItem>[
    for (final r in raw)
      if (CallLogsRemoteDataSource.callLogFromJson(r) case final log?)
        (row: CustomerCallRow.fromJson(r), log: log),
  ];
  // Newest first — the endpoint returns oldest-first and ignores `ordering`.
  items.sort((a, b) {
    final x = a.row.startedAt, y = b.row.startedAt;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return y.compareTo(x);
  });
  return items;
});

/// `POST /crm/call-logs/` linked to the customer (webapp `postCustomerCall`).
Future<void> createCustomerCallLog(
  ApiService api, {
  required String customerId,
  required String from,
  required String to,
  required String direction,
  required String medium,
  String duration = '',
}) =>
    api.post(ApiEndpoints.callLogs,
        body: customerCallLogBody(
          customerId: customerId,
          from: from,
          to: to,
          direction: direction,
          medium: medium,
          duration: duration,
        ));

// ── Opportunities ──
//
// The customer record's own `linked_leads` (source lead + upsells), as the
// webapp's Opportunities tab reads it. Rides on the detail row the screen has
// already fetched.

final customerLinkedLeadsProvider =
    FutureProvider.autoDispose.family<List<CustomerLinkedLead>, String>((ref, customerId) async {
  if (customerId.isEmpty) return const [];
  final row = await ref.watch(customerRowProvider(customerId).future);
  return CustomerLinkedLead.listFrom(row?['linked_leads']);
});

// ── Notes source tags ──
//
// `GET /crm/notes/?related_to=customer&related_to_id=` returns each note's
// `source`; the mapped NoteEntry drops it, so it is read here and keyed by
// note id. A failure just leaves every note untagged.

final customerNoteTagsProvider =
    FutureProvider.autoDispose.family<Map<String, ({String text, bool readOnly})>, String>(
        (ref, customerId) async {
  final api = _api(ref);
  if (api == null || customerId.isEmpty) return const {};
  try {
    final body = await api.get(ApiEndpoints.notes,
        query: {'related_to': 'customer', 'related_to_id': customerId, 'page_size': 100}, quiet: true);
    final out = <String, ({String text, bool readOnly})>{};
    for (final n in Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results) {
      final id = '${n['note_id'] ?? ''}';
      final tag = noteSourceTag(n['source'], customerId);
      if (id.isNotEmpty && tag != null) out[id] = tag;
    }
    return out;
  } on Object {
    return const {};
  }
});
