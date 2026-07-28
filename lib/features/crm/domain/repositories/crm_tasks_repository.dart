import '../entities/crm_task.dart';

/// Abstract contract for CRM task data.
abstract class CrmTasksRepository {
  Future<List<CrmTask>> getTasks();
}
