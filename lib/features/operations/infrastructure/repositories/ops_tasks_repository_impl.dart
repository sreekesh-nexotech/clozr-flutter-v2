import '../../../../app/config/constants.dart';
import '../../domain/entities/ops_task.dart';
import '../../domain/repositories/ops_tasks_repository.dart';
import '../data_sources/local/ops_tasks_mock_ds.dart';

/// Mock-backed implementation. Swap the data source for a remote one when the
/// API lands — the interface and every caller stay the same.
class OpsTasksRepositoryImpl implements OpsTasksRepository {
  const OpsTasksRepositoryImpl(this._local);

  final OpsTasksMockDataSource _local;

  @override
  Future<List<OpsTask>> getOpsTasks() async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchOpsTasks();
  }
}
