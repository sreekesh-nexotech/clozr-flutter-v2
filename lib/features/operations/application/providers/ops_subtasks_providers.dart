import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../domain/entities/ops_task.dart';
import '../../domain/repositories/ops_tasks_repository.dart';
import 'ops_tasks_providers.dart';

/// Subtask state for one ops task. The task detail list and the standalone
/// subtask page both read and write this, so a tick on either surface stays in
/// sync.
///
/// On the API a subtask **is a task** with `parent_task` set
/// (`operations-task.md` §3C): the list is `GET /projects/tasks/?parent=<id>`,
/// adding one is a `POST /projects/tasks/`, and ticking one is a
/// `PATCH /projects/tasks/{subtask_id}/ {"status": "<closed-status-uuid>"}`.
/// None of that used to happen — the checklist was a purely local list seeded
/// from the record, and API rows never carry embedded subtasks, so in API mode
/// the card was permanently empty and both writes went nowhere.
///
/// Mock mode keeps the old in-memory behaviour: the seed record carries the
/// checklist and there is nothing to write to.
class OpsSubtasksNotifier extends StateNotifier<List<Subtask>> {
  OpsSubtasksNotifier(this._ref, this._taskId, super.seed) {
    if (ApiConfig.apiEnabled) load();
  }

  final Ref _ref;
  final String _taskId;

  OpsTasksRepository get _repo => _ref.read(opsTasksRepositoryProvider);

  /// (Re)reads the child rows. Silent on failure — the card keeps whatever it
  /// already showed rather than blanking on a dropped connection.
  Future<void> load() async {
    if (_taskId.isEmpty) return;
    try {
      // The catalog decides which rows read as done, so it has to be in hand
      // before the rows are interpreted; `read` alone returns nothing on a
      // detail screen reached directly by link.
      await _ref.read(opsTaskStatusCatalogProvider.future);
      if (!mounted) return;
      final rows = await _repo.getSubtasks(
        _taskId,
        closedStatusIds: _ref.read(opsTaskClosedStatusIdsProvider),
      );
      if (mounted) state = rows;
    } on AppError {
      // Keep the current list.
    }
  }

  /// Ticks or un-ticks a subtask. Returns null on success, or the message to
  /// show when the write was refused.
  ///
  /// The parent's completion is gated on this (§3A), so the refusal path
  /// matters: the server's 400 names what is still open.
  Future<String?> toggle(int index) async {
    if (index < 0 || index >= state.length) return null;
    final s = state[index];

    if (!ApiConfig.apiEnabled) {
      _applyLocally(index, !s.done);
      return null;
    }
    if (s.id.isEmpty) return null; // nothing to write to

    final target = s.done
        ? _ref.read(opsTaskOpenStatusProvider)
        : _ref.read(opsTaskDoneStatusProvider);
    if (target == null) {
      return "Couldn't load your organisation's task statuses";
    }
    try {
      await _repo.updateOpsTask(s.id, {'status': target.id});
      if (!mounted) return null;
      // Optimistic, then confirmed by the reload — which also picks up any
      // rollup the server did on the parent.
      _applyLocally(index, !s.done);
      _refreshParent();
      await load();
      return null;
    } on AppError catch (e) {
      return e.message;
    }
  }

  /// Adds a subtask under this task. Returns null on success, else the message.
  Future<String?> add(String title) async {
    final t = title.trim();
    if (t.isEmpty) return null;

    if (!ApiConfig.apiEnabled) {
      state = [...state, Subtask(title: t, done: false, who: 'me', due: '')];
      return null;
    }
    try {
      // A subtask inherits its parent's project — the API wants it explicitly,
      // and a standalone parent simply has none to pass.
      await _repo.createSubtask(
        parentId: _taskId,
        subject: t,
        projectId: _ref.read(opsTaskDetailOrListProvider(_taskId))?.projId ?? '',
      );
      if (!mounted) return null;
      _refreshParent();
      await load();
      return null;
    } on AppError catch (e) {
      return e.message;
    }
  }

  void _applyLocally(int index, bool done) {
    final next = [...state];
    final s = next[index];
    next[index] = Subtask(id: s.id, title: s.title, done: done, who: s.who, due: s.due);
    state = next;
  }

  /// A subtask write moves the parent's `computed_progress`, `subtask_count`
  /// and completion gate, so the record it hangs off has to be re-read.
  void _refreshParent() {
    _ref.invalidate(opsTaskDetailProvider(_taskId));
  }
}

/// Subtasks for a task, keyed by task id.
///
/// `autoDispose` so re-opening a task re-reads its children instead of showing
/// whatever the session last cached. The task detail screen stays mounted
/// underneath the standalone subtask page, so navigating between the two keeps
/// one instance and one list.
final opsSubtasksProvider = StateNotifierProvider.autoDispose
    .family<OpsSubtasksNotifier, List<Subtask>, String>((ref, taskId) {
  // Mock mode seeds from the record and must re-seed when it resolves (the task
  // is null on the first frame of a cold navigation). In API mode the record
  // never carries subtasks — the notifier fetches its own — so watching the
  // list there would only rebuild it, and blank the card, on every refresh.
  final seed = ApiConfig.apiEnabled
      ? const <Subtask>[]
      : [
          for (final s in ref.watch(opsTaskByIdProvider(taskId))?.subtasks ??
              const <Subtask>[])
            Subtask(id: s.id, title: s.title, done: s.done, who: s.who, due: s.due),
        ];
  return OpsSubtasksNotifier(ref, taskId, seed);
});
