// The ticket's audit log has to reflect what just happened on the screen —
// a status move, an assignee change, a note, an attachment upload, a delete.
// It refetches off the app-wide write signal rather than off whichever call
// sites someone remembered to wire.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/core/network/network_providers.dart';
import 'package:clozrapp/core/storage/token_storage.dart';
import 'package:clozrapp/features/crm/domain/entities/audit_entry.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_catalog.dart';
import 'package:clozrapp/features/helpdesk/application/providers/tickets_providers.dart';
import 'package:clozrapp/features/helpdesk/domain/entities/issue_summary.dart';
import 'package:clozrapp/features/helpdesk/domain/entities/ticket.dart';
import 'package:clozrapp/features/helpdesk/domain/entities/ticket_task.dart';
import 'package:clozrapp/features/helpdesk/domain/repositories/tickets_repository.dart';

const _issueId = 'i-1';

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

/// Counts how often the ticket's activity feed was actually fetched.
class _CountingRepo implements TicketsRepository {
  int activityCalls = 0;

  @override
  Future<List<AuditEntry>> getActivity(String issueId,
      {Map<String, String> names = const {}}) async {
    activityCalls++;
    return const [];
  }

  @override
  Future<List<Ticket>> getTickets({Map<String, dynamic> filters = const {}}) async =>
      const [];

  @override
  Future<Ticket?> getTicket(String id) async => null;

  @override
  Future<List<CatalogOption>> getIssueStatuses() async => const [];

  @override
  Future<List<CatalogOption>> getIssueTypes() async => const [];

  @override
  Future<IssueSummary?> getSummary(Map<String, dynamic> filters) async => null;

  @override
  Future<Map<String, int>> getStatusCounts(Map<String, dynamic> filters) async => const {};

  @override
  Future<Ticket?> createTicket(Map<String, dynamic> fields) async => null;

  @override
  Future<void> updateTicket(String id, Map<String, dynamic> fields) async {}

  @override
  Future<void> setTicketStatusByKey(String id, String uiStatusKey) async {}

  @override
  Future<void> setAssignee(String id, String? userId) async {}

  @override
  Future<List<TicketTask>> getLinkedTasks(String issueId) async => const [];

  @override
  Future<TicketTask?> createLinkedTask(String issueId,
          {required String subject, String? priority}) async =>
      null;
}

ApiService _api() {
  final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))
    ..httpClientAdapter = _OkAdapter();
  return ApiService(tokens: TokenStorage(), dio: dio);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// Long enough for the write ticker's burst window to close.
Future<void> _afterQuietPeriod() =>
    Future<void>.delayed(const Duration(milliseconds: 400));

void main() {
  late _CountingRepo repo;
  late ApiService api;
  late ProviderContainer container;

  setUp(() {
    repo = _CountingRepo();
    api = _api();
    container = ProviderContainer(overrides: [
      apiServiceProvider.overrideWithValue(api),
      ticketsRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    // Kept alive for the test, standing in for the open detail screen.
    final sub = container.listen(ticketActivityProvider(_issueId), (_, __) {},
        fireImmediately: true);
    addTearDown(sub.close);
  });

  test('fetches once when the screen opens', () async {
    await _settle();
    expect(repo.activityCalls, 1);
  });

  test('a GET changes nothing — only writes signal', () async {
    await _settle();
    await api.get('/crm/issues/');
    await _afterQuietPeriod();
    expect(repo.activityCalls, 1);
  });

  for (final verb in ['POST', 'PATCH', 'PUT', 'DELETE']) {
    test('a $verb anywhere on the screen refetches the log', () async {
      await _settle();
      switch (verb) {
        case 'POST':
          await api.post('/crm/notes/', body: const {});
        case 'PATCH':
          await api.patch('/crm/issues/$_issueId/', body: const {});
        case 'PUT':
          await api.put('/crm/x/', body: const {});
        default:
          await api.delete('/crm/attachments/a-1/');
      }
      await _afterQuietPeriod();
      expect(repo.activityCalls, 2, reason: '$verb should have refreshed the log');
    });
  }

  test('a multipart attachment upload counts as a write', () async {
    await _settle();
    await api.postForm('/crm/attachments/', FormData.fromMap({'name': 'a.pdf'}));
    await _afterQuietPeriod();
    expect(repo.activityCalls, 2);
  });

  test('a burst of writes collapses into one refetch', () async {
    await _settle();
    // One user action is often several calls — a note, then its attachment.
    await api.post('/crm/notes/', body: const {});
    await api.postForm('/crm/attachments/', FormData.fromMap({'name': 'a.pdf'}));
    await _afterQuietPeriod();
    expect(repo.activityCalls, 2, reason: 'one refetch for the burst, not three');
  });
}
