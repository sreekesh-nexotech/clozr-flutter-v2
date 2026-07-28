import '../../../../app/config/constants.dart';
import '../../domain/entities/member.dart';
import '../../domain/entities/role.dart';
import '../../domain/entities/team.dart';
import '../../domain/repositories/people_repository.dart';
import '../data_sources/local/people_mock_ds.dart';

/// Mock-backed implementation. Swap the data source for a remote one (Dio /
/// Retrofit) when the API lands — the interface and every caller stay the same.
class PeopleRepositoryImpl implements PeopleRepository {
  const PeopleRepositoryImpl(this._local);

  final PeopleMockDataSource _local;

  @override
  Future<List<Member>> getMembers() async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchMembers();
  }

  @override
  Future<List<Team>> getTeams() async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchTeams();
  }

  @override
  Future<List<Role>> getRoles() async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchRoles();
  }
}
