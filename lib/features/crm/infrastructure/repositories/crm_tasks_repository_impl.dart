import '../../../../app/config/constants.dart';
import '../../domain/entities/crm_task.dart';
import '../../domain/repositories/crm_tasks_repository.dart';
import '../data_sources/local/crm_tasks_mock_ds.dart';

/// Mock-backed implementation.
class CrmTasksRepositoryImpl implements CrmTasksRepository {
  const CrmTasksRepositoryImpl(this._local);

  final CrmTasksMockDataSource _local;

  @override
  Future<List<CrmTask>> getTasks() async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchTasks();
  }
}
