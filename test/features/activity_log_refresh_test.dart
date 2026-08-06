// The activity log reflects every action on a detail screen, not one list, so
// it refetches off a per-record revision signal rather than off whichever
// provider a given action happens to refresh.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/application/providers/audit_log_providers.dart';
import 'package:clozrapp/features/crm/application/providers/crm_catalog_providers.dart';
import 'package:clozrapp/features/crm/domain/entities/audit_entry.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/audit_log_remote_ds.dart';

const _leadId = 'lead-1';
const _other = 'lead-2';

/// Counts how many times the log was actually fetched.
class _CountingDs implements AuditLogRemoteDataSource {
  int calls = 0;

  @override
  Future<List<AuditEntry>> fetchFor({
    required String modelName,
    required String recordId,
    Map<String, String> statusNames = const {},
    int limit = 50,
  }) async {
    calls++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _CountingDs ds;
  late ProviderContainer container;

  setUp(() {
    ds = _CountingDs();
    container = ProviderContainer(overrides: [
      auditLogRemoteDataSourceProvider.overrideWithValue(ds),
      leadStatusesProvider.overrideWithValue(const []),
    ]);
    addTearDown(container.dispose);
  });

  test('fetches once on open', () async {
    container.listen(leadActivityLogProvider(_leadId), (_, __) {},
        fireImmediately: true);
    await _settle();
    expect(ds.calls, 1);
  });

  test('a recorded change refetches it', () async {
    container.listen(leadActivityLogProvider(_leadId), (_, __) {},
        fireImmediately: true);
    await _settle();

    container.read(recordRevisionProvider(_leadId).notifier).update((v) => v + 1);
    await _settle();
    expect(ds.calls, 2);

    // Every subsequent action refetches too — a stage change, then a call.
    container.read(recordRevisionProvider(_leadId).notifier).update((v) => v + 1);
    await _settle();
    expect(ds.calls, 3);
  });

  test('another lead changing does not refetch this one', () async {
    container.listen(leadActivityLogProvider(_leadId), (_, __) {},
        fireImmediately: true);
    await _settle();

    container.read(recordRevisionProvider(_other).notifier).update((v) => v + 1);
    await _settle();
    expect(ds.calls, 1, reason: 'the signal is per record');
  });

  test('no data source (mock mode) means no fetching at all', () async {
    final mock = ProviderContainer(overrides: [
      auditLogRemoteDataSourceProvider.overrideWithValue(null),
      leadStatusesProvider.overrideWithValue(const []),
    ]);
    addTearDown(mock.dispose);

    mock.listen(leadActivityLogProvider(_leadId), (_, __) {}, fireImmediately: true);
    await _settle();
    expect(mock.read(leadActivityLogProvider(_leadId)).valueOrNull, isEmpty);
  });
}
