// CRM task types and priorities are server-defined, and rows are matched on
// them exactly. The app hard-coded both, so against a real org the drawer
// offered four types that do not exist, omitted the two most common ones, and
// could not express the org's top priority at all.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/filters/filter_models.dart';
import 'package:clozrapp/data/api/status_keys.dart';
import 'package:clozrapp/features/crm/application/filters/tasks_filter_spec.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_catalog.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_task.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/crm_catalog_remote_ds.dart';

/// The live `?view_type=form` response's `task_type` choices for this org.
const _formSchema = {
  'model': 'task',
  'view_type': 'form',
  'fields': {
    'task_type': {
      'name': 'task_type',
      'type': 'string',
      'choices': [
        {'value': 'Task', 'label': 'Task'},
        {'value': 'Call', 'label': 'Call'},
        {'value': 'Meeting', 'label': 'Meeting'},
        {'value': 'Email', 'label': 'Email'},
        {'value': 'Deadline', 'label': 'Deadline'},
      ],
    },
  },
};

/// The org's real `/crm/task-priorities/` names — lower-case, with a critical.
const _priorityCatalog = [
  CatalogOption(id: 'p1', name: 'low'),
  CatalogOption(id: 'p2', name: 'medium'),
  CatalogOption(id: 'p3', name: 'high'),
  CatalogOption(id: 'p4', name: 'critical'),
];

CrmTask _task({String type = 'Task', String priority = 'Medium'}) => CrmTask(
      id: 'T1',
      title: 'Call the lead',
      type: type,
      leadId: 'L1',
      status: 'todo',
      priority: priority,
      assignee: 'me',
      due: '09 Jul 2026',
      dueNote: '',
    );

List<String> _optionIds(String fieldId, {
  List<CatalogOption> types = const [],
  List<CatalogOption> priorities = const [],
}) {
  final field = buildTasksFilterSpec(typeCatalog: types, priorityCatalog: priorities)
      .sections
      .expand((s) => s.fields)
      .firstWhere((f) => f.id == fieldId);
  return [for (final o in field.options) o.id];
}

void main() {
  group('task types come from the form schema', () {
    test('reads fields.task_type.choices', () {
      final types = CrmCatalogRemoteDataSource.mapTaskTypeChoices(_formSchema);

      expect([for (final t in types) t.id],
          ['Task', 'Call', 'Meeting', 'Email', 'Deadline']);
    });

    test('the drawer offers exactly those, and no invented ones', () {
      final types = CrmCatalogRemoteDataSource.mapTaskTypeChoices(_formSchema);
      final options = _optionIds('types', types: types);

      expect(options, ['Task', 'Call', 'Meeting', 'Email', 'Deadline']);
      // The old hard-coded list — none of these are real task types.
      for (final invented in ['WhatsApp', 'Site visit', 'Follow-up', 'Payment']) {
        expect(options, isNot(contains(invented)));
      }
    });

    test('"Task" — the default type — is now filterable at all', () {
      final types = CrmCatalogRemoteDataSource.mapTaskTypeChoices(_formSchema);
      final values = FilterValues()..['types'] = ChoiceValue(ids: {'Task'});

      expect(_optionIds('types', types: types), contains('Task'));
      expect(crmTaskMatchesFilters(_task(type: 'Task'), values), isTrue);
      expect(crmTaskMatchesFilters(_task(type: 'Call'), values), isFalse);
    });

    test('an unusable schema response falls back to the built-in list', () {
      expect(CrmCatalogRemoteDataSource.mapTaskTypeChoices(null), isEmpty);
      expect(CrmCatalogRemoteDataSource.mapTaskTypeChoices(const {'fields': {}}), isEmpty);
      expect(_optionIds('types'), kBuiltinTaskTypes);
    });
  });

  group('priorities', () {
    test('critical folds to Urgent, not to the Medium default', () {
      // This is what made an org's most severe tasks render as ordinary ones.
      expect(priorityKey('critical'), 'Urgent');
      expect(priorityKey('Critical'), 'Urgent');
      expect(priorityKey('high'), 'High');
      expect(priorityKey('low'), 'Low');
      expect(priorityKey('medium'), 'Medium');
    });

    test('the drawer offers the org’s set, folded to display values', () {
      final options = _optionIds('priorities', priorities: _priorityCatalog);

      expect(options, ['Low', 'Medium', 'High', 'Urgent']);
      // Previously there was no way to filter for the top priority.
      expect(options, contains('Urgent'));
    });

    test('folding de-duplicates aliases of one level', () {
      final options = _optionIds('priorities', priorities: const [
        CatalogOption(id: 'a', name: 'high'),
        CatalogOption(id: 'b', name: 'Highest'),
      ]);

      expect(options, ['High']);
    });

    test('a folded option matches the folded value on a row', () {
      final values = FilterValues()..['priorities'] = ChoiceValue(ids: {'Urgent'});

      expect(crmTaskMatchesFilters(_task(priority: 'Urgent'), values), isTrue);
      expect(crmTaskMatchesFilters(_task(priority: 'High'), values), isFalse);
    });

    test('falls back to the built-in vocabulary when the catalog is empty', () {
      expect(_optionIds('priorities'), kBuiltinTaskPriorities);
    });
  });
}
