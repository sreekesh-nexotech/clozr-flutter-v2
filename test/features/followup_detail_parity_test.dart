// Follow-up detail (UAT CRM-FU-024): the webapp TaskDetailScreen's follow-up
// copy and display rules.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/crm/application/followup_detail_rules.dart';
import 'package:clozrapp/features/crm/domain/entities/view_schema.dart';

void main() {
  test('Mark complete / Mark as not done', () {
    expect(followupCompleteLabel(false), 'Mark complete');
    expect(followupCompleteLabel(true), 'Mark as not done');
  });

  test('unlinked + reopen copy', () {
    expect(followupUnlinkedText, 'Internal follow-up — not linked to any record.');
    expect(followupReopenOffHint,
        'Reopening completed follow-ups is turned off (Settings → CRM Settings → Task Settings).');
  });

  test('related caption is "<Type> · <reference>", never the uuid', () {
    expect(followupRelatedCaption({'model': 'lead', 'id': 'uuid', 'reference': 'LD-0304'}), 'Lead · LD-0304');
    expect(followupRelatedCaption({'model': 'quotation', 'reference': null}), 'Quote');
    expect(followupRelatedCaption({'model': 'organization_contact', 'reference': 'C-1'}), 'Contact · C-1');
    expect(followupRelatedCaption({'model': 'site_survey'}), 'Site survey');
    expect(followupRelatedCaption(null), 'Record');
  });

  test('header subtitle "<type> · <related label>"', () {
    expect(followupSubtitle('Call', {'label': 'uat j2 web'}), 'Call · uat j2 web');
    expect(followupSubtitle('Call', null), 'Call');
    expect(followupSubtitle('', {'label': 'null'}), 'Follow-up');
  });

  test('Related To info row reads "label · model"', () {
    expect(followupRelatedRowValue({'model': 'lead', 'label': 'Acme'}), 'Acme · lead');
    expect(followupRelatedRowValue({'model': 'lead', 'label': ''}), '—');
    expect(followupRelatedRowValue(null), '—');
  });

  test('due label "18 Jun 2026" and its tone', () {
    expect(followupDueLabel('2026-06-18'), '18 Jun 2026');
    expect(followupDueLabel(null, fallback: '28 Oct 2026'), '28 Oct 2026');
    expect(followupDueLabel(''), '');
    expect(followupDueTone('In 3d'), FollowupDueTone.warn);
    expect(followupDueTone('Today'), FollowupDueTone.danger);
    expect(followupDueTone('2d overdue'), FollowupDueTone.danger);
    expect(followupDueTone(''), FollowupDueTone.none);
  });

  test('info rows only for fields the record carries (webapp present())', () {
    const due = ViewColumn(name: 'due_date', label: 'Due Date', order: 5);
    const budget = ViewColumn(name: 'custom_fields.budget', label: 'Budget', order: 9, isCustom: true);
    expect(followupRecordHasColumn({'due_date': null}, due), isTrue);
    expect(followupRecordHasColumn({}, due), isFalse);
    expect(followupRecordHasColumn({'custom_fields': {'budget': 1}}, budget), isTrue);
    expect(followupRecordHasColumn({'custom_fields': {}}, budget), isFalse);
  });

  test('related record routes (lead / customer / product / quote)', () {
    String? route(Map<String, dynamic>? r) =>
        followupRelatedRoute(r, lead: '/l', customer: '/c', product: '/p', quote: '/q');
    expect(route({'model': 'lead', 'id': 'x'}), '/l?id=x');
    expect(route({'model': 'product', 'id': 'x'}), '/p?id=x');
    expect(route({'model': 'quotation', 'id': 'x'}), '/q?id=x');
    expect(route({'model': 'issue', 'id': 'x'}), isNull);
    expect(route({'model': 'lead'}), isNull);
  });
}
