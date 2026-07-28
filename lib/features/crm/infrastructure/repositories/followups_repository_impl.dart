import '../../../../app/config/constants.dart';
import '../../domain/entities/followup.dart';
import '../../domain/repositories/followups_repository.dart';
import '../data_sources/local/followups_mock_ds.dart';

/// Mock-backed implementation.
class FollowupsRepositoryImpl implements FollowupsRepository {
  const FollowupsRepositoryImpl(this._local);

  final FollowupsMockDataSource _local;

  @override
  Future<List<Followup>> getFollowups() async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchFollowups();
  }
}
