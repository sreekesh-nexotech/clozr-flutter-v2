// The activity log shows everything that happens to a lead, not one list, so
// it refetches off the app-wide write signal rather than off whichever call
// sites someone remembered to wire — a list that goes stale as actions are
// added.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/core/network/network_providers.dart';
import 'package:clozrapp/core/storage/token_storage.dart';
import 'package:clozrapp/features/crm/application/providers/audit_log_providers.dart';
import 'package:clozrapp/features/crm/application/providers/crm_catalog_providers.dart';
import 'package:clozrapp/features/crm/domain/entities/audit_entry.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/audit_log_remote_ds.dart';

const _leadId = 'lead-1';

/// Answers anything with 200.
class _OkAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(jsonEncode({'ok': true}), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  void close({bool force = false}) {}
}

/// Counts how many times the log was actually fetched.
class _CountingDs implements AuditLogRemoteDataSource {
  int calls = 0;

  @override
  Future<List<AuditEntry>> fetchFor({
    required String modelName,
    required String recordId,
    String recordLabel = 'Lead',
    Map<String, String> statusNames = const {},
  }) async {
    calls++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ApiService _api() {
  final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))
    ..httpClientAdapter = _OkAdapter();
  return ApiService(tokens: TokenStorage(), dio: dio);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// Long enough for the ticker's burst window to close.
Future<void> _afterQuietPeriod() =>
    Future<void>.delayed(const Duration(milliseconds: 400));

void main() {
  late _CountingDs ds;
  late ApiService api;
  late ProviderContainer container;
  late ProviderSubscription<AsyncValue<List<AuditEntry>>> sub;

  setUp(() {
    ds = _CountingDs();
    api = _api();
    container = ProviderContainer(overrides: [
      apiServiceProvider.overrideWithValue(api),
      auditLogRemoteDataSourceProvider.overrideWithValue(ds),
      leadStatusesProvider.overrideWithValue(const []),
    ]);
    addTearDown(container.dispose);
    // Kept alive for the test, standing in for the open detail screen.
    sub = container.listen(leadActivityLogProvider(_leadId), (_, __) {},
        fireImmediately: true);
    addTearDown(sub.close);
  });

  test('fetches once when the screen opens', () async {
    await _settle();
    expect(ds.calls, 1);
  });

  test('a GET changes nothing — only writes signal', () async {
    await _settle();
    await api.get('/crm/leads/');
    await _afterQuietPeriod();
    expect(ds.calls, 1);
  });

  for (final verb in ['POST', 'PATCH', 'PUT', 'DELETE']) {
    test('a $verb anywhere refetches the log', () async {
      await _settle();
      switch (verb) {
        case 'POST':
          await api.post('/crm/notes/', body: const {});
        case 'PATCH':
          await api.patch('/crm/leads/$_leadId/', body: const {});
        case 'PUT':
          await api.put('/crm/x/', body: const {});
        default:
          await api.delete('/crm/x/');
      }
      await _afterQuietPeriod();
      expect(ds.calls, 2, reason: '$verb should have refreshed the log');
    });
  }

  test('a burst of writes collapses into one refetch', () async {
    await _settle();
    // One user action is often several calls — a note, then its attachment.
    await api.post('/crm/notes/', body: const {});
    await api.post('/crm/attachments/', body: const {});
    await api.patch('/crm/leads/$_leadId/', body: const {});
    await _afterQuietPeriod();
    expect(ds.calls, 2, reason: 'one refetch for the burst, not three');
  });

  test('successive actions each refetch', () async {
    await _settle();
    await api.patch('/crm/leads/$_leadId/', body: const {});
    await _afterQuietPeriod();
    expect(ds.calls, 2);

    await api.post('/crm/call-logs/', body: const {});
    await _afterQuietPeriod();
    expect(ds.calls, 3);
  });

  test('no data source (mock mode) means no fetching at all', () async {
    final mock = ProviderContainer(overrides: [
      apiServiceProvider.overrideWithValue(api),
      auditLogRemoteDataSourceProvider.overrideWithValue(null),
      leadStatusesProvider.overrideWithValue(const []),
    ]);
    addTearDown(mock.dispose);

    final s = mock.listen(leadActivityLogProvider(_leadId), (_, __) {},
        fireImmediately: true);
    addTearDown(s.close);
    await _settle();
    expect(mock.read(leadActivityLogProvider(_leadId)).valueOrNull, isEmpty);
  });
}
