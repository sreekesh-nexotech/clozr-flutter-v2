import 'package:clozrapp/features/helpdesk/application/board_rules.dart';
import 'package:clozrapp/features/helpdesk/domain/entities/issue_summary.dart';
import 'package:flutter_test/flutter_test.dart';

SummaryCard _card({int? left, bool paused = false}) =>
    SummaryCard(id: 'x', slaRemainingSeconds: left, slaPaused: paused);

void main() {
  test('card pill follows the webapp SLA states', () {
    expect(boardCardPill(_card()).label, 'No SLA');
    expect(boardCardPill(_card(left: 500, paused: true)).label, 'Paused');
    final late = boardCardPill(_card(left: -(4 * 3600 + 12 * 60)));
    expect(late.label, 'Overdue 4h 12m');
    expect(late.tone, BoardPillTone.breached);
    final soon = boardCardPill(_card(left: 3000));
    expect(soon.label, '50m left');
    expect(soon.tone, BoardPillTone.atRisk);
    expect(boardCardPill(_card(left: 2 * 86400 + 3600)).label, '2d 1h left');
    expect(boardCardPill(_card(left: 2 * 86400)).tone, BoardPillTone.onTrack);
  });

  test('age, initials, footer and toasts', () {
    final now = DateTime(2026, 10, 27, 12);
    expect(boardCardAge(DateTime(2026, 10, 24, 12), now: now), '3d');
    expect(boardCardAge(DateTime(2026, 10, 27, 9), now: now), '3h');
    expect(boardCardAge(null), '');
    expect(boardInitials('Sufail Salim'), 'SS');
    expect(boardInitials(''), '–');
    expect(boardMoreLabel(3, 3), isNull);
    expect(boardMoreLabel(10, 8), '+2 more →');
    expect(boardMoreLabel(2, 0), 'View in tickets →');
    expect(bucketMoreToast(7, 'Breached'), 'Tickets list — 7 breached tickets');
    expect(workloadMoreToast(const WorkloadColumn(agentId: 'u', agentName: 'Cijo George', total: 2)), 'Tickets assigned to Cijo');
    expect(workloadMoreToast(const WorkloadColumn(total: 1)), 'Unassigned tickets — use the Assignee filter');
    expect(boardDueSoonLabel, 'Due < 60m');
  });

  test('summary maps No SLA, workload columns and ordered lanes', () {
    final s = IssueSummary.fromJson({
      'stats': {'open': 4, 'breached_now': 1, 'due_today': 0, 'closed_today': 0, 'no_sla': 2},
      'sla_watch': {
        'breached': {
          'total': 1,
          'items': [
            {
              'issue_id': 'a',
              'subject': 'S',
              'priority': 'High',
              'sla_remaining_seconds': null,
              'has_linked_tasks': true,
              'created_at': '2026-10-07T09:57:32Z',
              'assignee': null,
            }
          ]
        },
        'no_sla': 2,
      },
      'workload': {
        'unassigned': {'total': 1, 'items': []},
        'by_agent': [
          {'user': {'user_id': 'u1', 'name': 'Cijo George'}, 'total': 2},
        ],
      },
      'pipeline': [
        {'issue_status_id': 's2', 'name': 'In Progress', 'position': 1, 'total': 2},
        {'issue_status_id': 's1', 'name': 'Open', 'position': 0, 'total': 1, 'color': '#3B82F6'},
      ],
    })!;
    expect(s.noSla!.total, 2);
    expect(s.noSla!.items, isEmpty);
    expect(s.breached.items.single.hasLinkedTasks, isTrue);
    expect(s.breached.items.single.createdAt, isNotNull);
    expect(s.workload.first.isUnassigned, isTrue);
    expect(s.workload[1].agentName, 'Cijo George');
    expect(s.workload[1].total, 2);
    expect(s.lanes.map((l) => l.name), ['Open', 'In Progress']);
    expect(IssueSummary.fromJson({'stats': {'open': 1}, 'sla_watch': {}})!.noSla, isNull);
  });
}
