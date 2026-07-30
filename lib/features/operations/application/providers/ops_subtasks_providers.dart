import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/ops_task.dart';
import 'ops_tasks_providers.dart';

/// Mutable subtask state for one ops task (#12). The task detail list and the
/// standalone subtask page both read and write this, so a done toggle on either
/// surface stays in sync. Seeded once from the task's mock subtasks.
class OpsSubtasksNotifier extends StateNotifier<List<Subtask>> {
  OpsSubtasksNotifier(super.seed);

  void toggle(int index) {
    if (index < 0 || index >= state.length) return;
    final next = [...state];
    final s = next[index];
    next[index] = Subtask(title: s.title, done: !s.done, who: s.who, due: s.due);
    state = next;
  }

  void add(String title) {
    final t = title.trim();
    if (t.isEmpty) return;
    state = [...state, Subtask(title: t, done: false, who: 'me', due: '')];
  }
}

/// Subtasks for a task, keyed by task id. Seeded from the task entity.
final opsSubtasksProvider =
    StateNotifierProvider.family<OpsSubtasksNotifier, List<Subtask>, String>((ref, taskId) {
  // watch (not read): the tasks source is async, so on cold navigation the task
  // is null on the first frame. Watching re-seeds the notifier once the task
  // resolves instead of sticking with an empty seed.
  final task = ref.watch(opsTaskByIdProvider(taskId));
  final seed = <Subtask>[
    for (final s in task?.subtasks ?? const <Subtask>[])
      Subtask(title: s.title, done: s.done, who: s.who, due: s.due),
  ];
  return OpsSubtasksNotifier(seed);
});
