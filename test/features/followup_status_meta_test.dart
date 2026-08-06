// Follow-ups are Tasks, so their statuses are the org's own CRMTaskStatus set
// (Open / In Progress / Completed / Cancelled). The card and the detail page
// rendered only the built-in Overdue / Upcoming / Done buckets, so a follow-up
// the API reported as "In Progress" showed as "Upcoming" — the org's real
// statuses never appeared anywhere.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/application/providers/crm_catalog_providers.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_catalog.dart';
import 'package:clozrapp/features/crm/domain/entities/followup.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/followups_remote_ds.dart';

/// The org's real task statuses, as `/crm/crm-task-statuses/` returns them.
const _statuses = [
  CatalogOption(id: 's1', name: 'Open', statusType: 'open'),
  CatalogOption(id: 's2', name: 'In Progress', statusType: 'in_progress'),
  CatalogOption(id: 's3', name: 'Completed', statusType: 'completed'),
  CatalogOption(id: 's4', name: 'Cancelled', statusType: 'cancelled'),
];

Followup _fu({String statusName = '', String status = 'due'}) => Followup(
      id: 'F1',
      kind: 'Call',
      contact: 'Ishaan',
      custId: null,
      leadId: 'L1',
      company: 'DataForge',
      due: '09 Jul 2026',
      time: '10:00',
      status: status,
      statusName: statusName,
      owner: 'me',
      agenda: 'Follow-up',
    );

void main() {
  group('the pill shows the org’s own status', () {
    test('a named status renders that name, not a built-in bucket', () {
      final meta = followupStatusMeta(_fu(statusName: 'In Progress'), _statuses);

      expect(meta.label, 'In Progress');
      // "Upcoming" is what the card used to show for this row.
      expect(meta.label, isNot('Upcoming'));
    });

    test('statuses the built-in vocabulary cannot express now appear', () {
      // Neither of these has a built-in counterpart; a cancelled follow-up used
      // to read as Upcoming.
      expect(followupStatusMeta(_fu(statusName: 'Cancelled'), _statuses).label,
          'Cancelled');
      expect(followupStatusMeta(_fu(statusName: 'Open'), _statuses).label, 'Open');
    });

    test('matching is case-insensitive on the name', () {
      expect(followupStatusMeta(_fu(statusName: 'in progress'), _statuses).label,
          'In Progress');
    });
  });

  group('falling back', () {
    test('a row with no status name keeps the built-in bucket', () {
      // Mock mode, or a follow-up the org never set a status on.
      expect(followupStatusMeta(_fu(status: 'done'), const []).label, isNotEmpty);
      expect(followupStatusMeta(_fu(status: 'done'), const []).label, 'Done');
    });

    test('a name the catalog does not know is still shown, coloured by bucket',
        () {
      // Catalog still loading, or the status was removed since this row was
      // written — the org's own word beats inventing one.
      final meta = followupStatusMeta(_fu(statusName: 'Awaiting Client'), const []);

      expect(meta.label, 'Awaiting Client');
    });
  });

  group('the mapper keeps what the pill needs', () {
    test('a row’s status name survives mapping', () {
      // Live shape: the list serializer sends `status` as a display name.
      final fu = FollowupsRemoteDataSource.followupFromJson(const {
        'task_id': 'F1',
        'title': 'Call back',
        'status': 'In Progress',
      });

      expect(fu!.statusName, 'In Progress');
      expect(fu.statusKey, 'in progress');
    });

    test('a row with a null status leaves the name empty, not "null"', () {
      final fu = FollowupsRemoteDataSource.followupFromJson(const {
        'task_id': 'F1',
        'title': 'Call back',
        'status': null,
      });

      expect(fu!.statusName, isEmpty);
    });
  });
}
