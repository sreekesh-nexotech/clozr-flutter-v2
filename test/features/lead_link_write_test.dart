import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/crm_tasks_remote_ds.dart';

/// The `related_to` / `due_time` shaping shared by the Add task and Add
/// follow-up sheets when they are opened from a lead.
void main() {
  const leadId = 'lead-uuid-1';

  group('relatedTo', () {
    test('sends the pair when both halves are present', () {
      expect(
        CrmTasksRemoteDataSource.relatedTo({
          'related_to': 'lead',
          'related_to_id': leadId,
        }),
        {'related_to': 'lead', 'related_to_id': leadId},
      );
    });

    test('sends nothing when the sheet was not opened from a lead', () {
      expect(CrmTasksRemoteDataSource.relatedTo({'title': 'x'}), isEmpty);
    });

    test('drops a half-populated pair rather than letting the API reject it', () {
      // The contract is both-or-neither; sending one alone is a 400.
      expect(CrmTasksRemoteDataSource.relatedTo({'related_to': 'lead'}), isEmpty);
      expect(
        CrmTasksRemoteDataSource.relatedTo({'related_to_id': leadId}),
        isEmpty,
      );
      expect(
        CrmTasksRemoteDataSource.relatedTo({
          'related_to': 'lead',
          'related_to_id': '   ',
        }),
        isEmpty,
      );
    });

    test('tolerates non-string values without throwing', () {
      expect(
        CrmTasksRemoteDataSource.relatedTo({
          'related_to': 'lead',
          'related_to_id': 42,
        }),
        isEmpty,
      );
    });
  });

  group('apiTimeOrNull', () {
    test('normalizes to HH:MM', () {
      expect(CrmTasksRemoteDataSource.apiTimeOrNull('9:05'), '09:05');
      expect(CrmTasksRemoteDataSource.apiTimeOrNull('10:30'), '10:30');
      expect(CrmTasksRemoteDataSource.apiTimeOrNull('  14:00  '), '14:00');
    });

    test('accepts a seconds component and trims it', () {
      expect(CrmTasksRemoteDataSource.apiTimeOrNull('10:30:00'), '10:30');
    });

    test('an empty or unparseable field is omitted, not sent as junk', () {
      expect(CrmTasksRemoteDataSource.apiTimeOrNull(''), isNull);
      expect(CrmTasksRemoteDataSource.apiTimeOrNull(null), isNull);
      expect(CrmTasksRemoteDataSource.apiTimeOrNull('morning'), isNull);
    });

    test('an out-of-range time is rejected rather than sent', () {
      expect(CrmTasksRemoteDataSource.apiTimeOrNull('25:00'), isNull);
      expect(CrmTasksRemoteDataSource.apiTimeOrNull('10:75'), isNull);
    });
  });

  group('isoDateOrNull', () {
    test('accepts both the ISO and the sheet display format', () {
      expect(CrmTasksRemoteDataSource.isoDateOrNull('2026-06-24'), '2026-06-24');
      expect(CrmTasksRemoteDataSource.isoDateOrNull('24 Jun 2026'), '2026-06-24');
    });

    test('an unparseable date is omitted', () {
      expect(CrmTasksRemoteDataSource.isoDateOrNull('next tuesday'), isNull);
      expect(CrmTasksRemoteDataSource.isoDateOrNull(''), isNull);
    });
  });
}
