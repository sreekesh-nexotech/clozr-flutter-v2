import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/call_log.dart';
import '../../domain/repositories/call_logs_repository.dart';
import '../../infrastructure/data_sources/local/call_logs_mock_ds.dart';
import '../../infrastructure/data_sources/remote/call_logs_remote_ds.dart';
import '../../infrastructure/repositories/call_logs_api_repository.dart';
import '../../infrastructure/repositories/call_logs_repository_impl.dart';

/// DI seam: API-backed when a base URL is configured, mock seed otherwise.
final callLogsRepositoryProvider = Provider<CallLogsRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const CallLogsRepositoryImpl(CallLogsMockDataSource());
  }
  return CallLogsApiRepository(
    CallLogsRemoteDataSource(ref.watch(apiServiceProvider)),
  );
});

/// Calls logged against one lead, newest first — the Call log tab on the lead
/// detail screen. Keyed by lead id: `GET /crm/call-logs/?related_to=lead&
/// related_to_id=<lead_id>`.
final leadCallLogsProvider =
    FutureProvider.family<List<CallLog>, String>((ref, leadId) {
  if (leadId.isEmpty) return Future.value(const <CallLog>[]);
  return ref.watch(callLogsRepositoryProvider).getCallLogsForLead(leadId);
});
