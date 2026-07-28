import '../entities/ops_task.dart';

/// Abstract contract for operations-task data. The presentation layer depends
/// only on this; the source (mock vs REST API) is an infrastructure detail.
abstract class OpsTasksRepository {
  Future<List<OpsTask>> getOpsTasks();
}
