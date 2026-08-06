import '../../../../app/config/constants.dart';
import '../../domain/entities/call_log.dart';
import '../../domain/repositories/call_logs_repository.dart';
import '../data_sources/local/call_logs_mock_ds.dart';

/// Mock-backed implementation.
class CallLogsRepositoryImpl implements CallLogsRepository {
  const CallLogsRepositoryImpl(this._local);

  final CallLogsMockDataSource _local;

  @override
  Future<List<CallLog>> getCallLogsForLead(String leadId) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchCallLogsForLead(leadId);
  }

  /// Mock mode has no backend to record against; the seed call list is fixed.
  @override
  Future<void> logOutgoingCall({
    required String leadId,
    required String fromNumber,
    required String toNumber,
  }) async {}
}
