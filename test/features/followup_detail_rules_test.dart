// Follow-up detail: the webapp's delete wording and the list-state helpers
// the chips and counts rely on.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/application/providers/crm_tasks_providers.dart';
import 'package:clozrapp/features/crm/application/providers/followups_providers.dart';
import 'package:clozrapp/features/crm/domain/entities/crm_catalog.dart';
import 'package:clozrapp/features/crm/domain/entities/followup.dart';
import 'package:clozrapp/features/crm/presentation/screens/followup_detail_screen.dart';

Followup _fu(String statusName, {String status = 'due'}) => Followup(
      id: statusName,
      kind: 'Call',
      contact: 'X',
      custId: null,
      leadId: null,
      company: '',
      due: '24 Oct 2026',
      time: '',
      status: status,
      owner: 'me',
      title: 'T',
      statusName: statusName,
    );

const _lanes = [
  CatalogOption(id: 'o', name: 'Open', statusType: 'open'),
  CatalogOption(id: 'c', name: 'Completed', statusType: 'completed'),
];

void main() {
  test('delete message names the notes and files (webapp deleteTaskMessage)', () {
    expect(followupDeleteMessage(2, 1),
        "This permanently removes the follow-up and its 2 notes and 1 file. This can't be undone.");
    expect(followupDeleteMessage(0, 0), "This permanently removes the follow-up. This can't be undone.");
    expect(followupDeleteMessage(null, null),
        "This permanently removes the follow-up together with its notes and files. This can't be undone.");
  });

  test('chips: lanes by name, Other for no lane, counts per chip', () {
    final rows = [_fu('Open'), _fu('Completed', status: 'done'), _fu('Waiting')];
    expect(followupTabCount(rows, 'all'), 3);
    expect(followupTabCount(rows, 'Open'), 1);
    expect(rows.where((f) => followupInNoLane(f, _lanes)).map((f) => f.id), ['Waiting']);
    // Webapp chip rules are shared with Tasks.
    expect(toggleCrmTaskChip({'Open'}, 'Completed'), {'Open', 'Completed'});
    expect(toggleCrmTaskChip({'Open'}, crmTaskOtherChip), {crmTaskOtherChip});
    expect(toggleCrmTaskChip({'Open'}, 'all'), isEmpty);
  });
}
