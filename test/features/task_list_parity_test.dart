import 'package:clozrapp/core/filters/filter_models.dart';
import 'package:clozrapp/data/api/user_directory.dart';
import 'package:clozrapp/features/crm/application/filters/tasks_filter_spec.dart';
import 'package:clozrapp/features/crm/application/providers/crm_tasks_providers.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_catalog.dart';
import 'package:clozrapp/features/crm/presentation/components/due_date_change.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const statuses = [CatalogOption(id: 's-open', name: 'Open'), CatalogOption(id: 's-done', name: 'Completed')];
  const priorities = [CatalogOption(id: 'p-high', name: 'high')];
  const codec = TaskFilterCodec(statuses: statuses, priorities: priorities);

  test('drawer → webapp list params', () {
    final v = FilterValues()
      ..['statuses'] = ChoiceValue(ids: {'s-open'})
      ..['priorities'] = ChoiceValue(ids: {'High'}, isNot: true)
      ..['teams'] = ChoiceValue(ids: {'t1'})
      ..['types'] = ChoiceValue(ids: {'Call'})
      ..['due'] = const DateValue(chip: 'overdue');
    expect(codec.encode(v), {
      'status__in': 'Open',
      'priority__not': 'p-high',
      'assigned_team__in': 't1',
      'task_type__in': 'Call',
      'is_overdue': 'true',
    });
    // "is not" status sends ids, not names.
    expect(codec.encode(FilterValues()..['statuses'] = ChoiceValue(ids: {'s-done'}, isNot: true)),
        {'status__not': 's-done'});
  });

  test('chip rules: All clears, statuses OR, Other exclusive', () {
    var s = toggleCrmTaskChip(const {}, 'Open');
    s = toggleCrmTaskChip(s, 'In Progress');
    expect(s, {'Open', 'In Progress'});
    expect(toggleCrmTaskChip(s, crmTaskOtherChip), {crmTaskOtherChip});
    expect(toggleCrmTaskChip({crmTaskOtherChip}, 'Open'), {'Open'});
    expect(toggleCrmTaskChip(s, 'all'), isEmpty);
  });

  test('due-date copy helpers', () {
    expect(slipLabel(4), '+4 days');
    expect(slipLabel(-1), '-1 day');
    expect(slipLabel(0), 'No slip');
    expect(rescheduleLabel({'reschedule_count': 2, 'slip_days': 4}), 'Moved 2×, +4 days');
    expect(rescheduleLabel({'reschedule_count': 0}), isNull);
    expect(dueDateReasonOptions(['Client requested', 'Other', ' Client requested ']), ['Client requested', 'Other']);
  });

  test('a saved filter on yourself ticks your own name in the Assignee list', () {
    // Webapp: "My Tasks" (assigned_to__in = the signed-in user) reopens with that
    // user ticked. It used to come back as `me`, which the list (keyed by real
    // user ids) never matched — "1 selected" with nothing ticked.
    const me = '8d8593b8-0a35-4942-b815-1162719b0b85';
    UserDirectory.currentUserId = me;
    addTearDown(UserDirectory.reset);
    final spec = buildTasksFilterSpec(assignableUsers: const [
      CatalogOption(id: me, name: 'Ashish Nexotech'),
      CatalogOption(id: 'cadc69f1-aed0-4584-848f-1095751b349c', name: 'Neeraja Pradeep'),
    ]);
    final v = const TaskFilterCodec().decode({'assigned_to__in': me}, spec);
    expect(v.choice('assignees')?.ids, {me});
    expect(const TaskFilterCodec().encode(v)['assigned_to__in'], me);
  });
}
