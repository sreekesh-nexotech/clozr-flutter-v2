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

  /// Mock mode has no server-side filter, so the seed is narrowed here — the
  /// same result the API returns for `?related_to=lead&related_to_id=…`.
  @override
  Future<List<CrmTask>> getTasksForLead(String leadId) async {
    await Future<void>.delayed(AppConstants.mockLatency);
    return _local.fetchTasks().where((t) => t.leadId == leadId).toList();
  }

  /// Local echo — builds the task the way the Add-task sheet does. Mock mode
  /// keeps its session-draft flow; this exists so the contract is honoured.
  @override
  Future<CrmTask?> createTask(Map<String, dynamic> fields) async {
    final due = (fields['due_date'] as String?)?.trim() ?? '';
    return CrmTask(
      id: 'TL-${DateTime.now().millisecondsSinceEpoch.remainder(100000)}',
      title: (fields['title'] as String?)?.trim() ?? '',
      type: fields['task_type'] as String? ?? 'Task',
      leadId: null,
      status: 'todo',
      priority: 'Medium',
      assignee: 'me',
      due: due.isEmpty ? 'No due date' : due,
      dueNote: '',
    );
  }

  /// No-op — mock mode persists status flips via the session override provider.
  @override
  Future<void> setTaskStatusByKey(String taskId, String uiStatusKey) async {}
}
