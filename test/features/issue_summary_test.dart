// The Helpdesk dashboard counted the loaded tickets and computed SLA state
// against the device clock. `/crm/issues/summary/` (helpdesk.md §7) answers the
// same questions server-side, and its SLA arithmetic is pause-aware — a ticket
// on hold must not drift toward "breached", which a list row cannot express.
// Fixture is the live dev-backend response.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/helpdesk/domain/entities/issue_summary.dart';

final _body = {
  'due_soon_minutes': 60,
  'stats': {'open': 17, 'breached_now': 3, 'due_today': 5, 'closed_today': 2},
  'sla_watch': {
    'breached': {'total': 3, 'items': []},
    'due_within': {'total': 2, 'items': []},
    'due_today': {'total': 3, 'items': []},
    'on_track': {'total': 9, 'items': []},
  },
  'workload': {
    'unassigned': {'total': 4, 'items': []},
    'by_agent': [
      {
        'user': {'user_id': 'u1', 'name': 'Deepak Tiwari'},
        'total': 6,
      }
    ],
  },
  'pipeline': [
    {'name': 'Open', 'total': 4, 'is_resolved': false},
    {'name': 'In Progress', 'total': 6, 'is_resolved': false},
    {'name': 'Resolved', 'total': 5, 'is_resolved': true},
    {'name': 'Closed', 'total': 2, 'is_resolved': true},
  ],
};

void main() {
  group('the Support Overview payload', () {
    final s = IssueSummary.fromJson(_body)!;

    test('the stats strip maps onto the KPI counts', () {
      expect(s.open, 17);
      expect(s.breachedNow, 3);
      expect(s.dueToday, 5);
      expect(s.closedToday, 2);
    });

    test('the four SLA buckets come through uncapped', () {
      // `items` is capped at 8; `total` is not — the donut needs the total.
      expect(s.slaBreached, 3);
      expect(s.slaDueWithin, 2);
      expect(s.slaDueToday, 3);
      expect(s.slaOnTrack, 9);
      // Mutually exclusive and open-only, so they sum to the open total.
      expect(s.slaBreached + s.slaDueWithin + s.slaDueToday + s.slaOnTrack,
          s.open - 0);
    });

    test('resolved work is summed from the org’s own pipeline', () {
      // Keyed by real IssueStatus rows, never a fixed set of columns.
      expect(s.resolvedTotal, 7); // Resolved 5 + Closed 2
    });

    test('"Within SLA" is everything not breached and not due within the hour', () {
      expect(s.withinSla, 9 + 3 + 7);
    });
  });

  group('a missing payload falls back rather than zeroing the screen', () {
    test('junk and nulls map to null', () {
      expect(IssueSummary.fromJson(null), isNull);
      expect(IssueSummary.fromJson('forbidden'), isNull);
      // A 200 carrying neither stats nor sla_watch is not a usable summary.
      expect(IssueSummary.fromJson({'due_soon_minutes': 60}), isNull);
    });

    test('a partial payload keeps what it did send', () {
      final partial = IssueSummary.fromJson({
        'stats': {'open': 4},
      })!;

      expect(partial.open, 4);
      expect(partial.slaBreached, 0);
      expect(partial.resolvedTotal, 0);
    });
  });
}
