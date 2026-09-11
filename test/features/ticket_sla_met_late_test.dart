// The ticket SLA banner said "met", in green with a tick, for **any** answered
// ticket — including one resolved days after its deadline had already passed.
// Observed live: TKT-0026 read "Resolution due · 22 Aug 2026 — breached 20d 2h
// ago", was resolved on 11 Sep, and then read "met 11 Sep 2026". That reports a
// breach as compliance, which is the one thing an SLA readout must not do.
//
// The distinction needs timestamps, not the day-precision display strings: an
// SLA measured in hours can be missed inside the same calendar day.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/helpdesk/domain/entities/ticket.dart';

Ticket _ticket({
  String? respondedISO,
  String? respByISO,
  String? resolvedISO,
  String? resolveByISO,
}) =>
    Ticket(
      id: 't1',
      subject: 's',
      cat: 'Bug',
      custId: '',
      contact: '',
      channel: 'Phone',
      status: 'open',
      pri: 'high',
      assignees: const [],
      product: null,
      projId: null,
      taskId: null,
      created: '1 Jan 2026',
      responded: respondedISO == null ? null : '16 Aug 2026',
      resolved: resolvedISO == null ? null : '11 Sep 2026',
      respByISO: respByISO,
      respByLabel: null,
      resolveByISO: resolveByISO,
      resolveByLabel: null,
      desc: '',
      respondedISO: respondedISO,
      resolvedISO: resolvedISO,
    );

void main() {
  group('resolvedLate', () {
    test('resolved after the deadline is late', () {
      final t = _ticket(
        resolveByISO: '2026-08-22T17:00:00Z',
        resolvedISO: '2026-09-11T12:00:00Z',
      );
      expect(t.resolvedLate, isTrue);
    });

    test('resolved before the deadline is not late', () {
      final t = _ticket(
        resolveByISO: '2026-08-22T17:00:00Z',
        resolvedISO: '2026-08-20T09:00:00Z',
      );
      expect(t.resolvedLate, isFalse);
    });

    test('missed by hours inside the same day is still late', () {
      // The reason this compares timestamps rather than the "22 Aug 2026"
      // display string, which cannot tell these two apart.
      final t = _ticket(
        resolveByISO: '2026-08-22T17:00:00Z',
        resolvedISO: '2026-08-22T18:30:00Z',
      );
      expect(t.resolvedLate, isTrue);
    });

    test('unknown when either side is missing — never a silent "on time"', () {
      expect(_ticket(resolvedISO: '2026-08-22T18:30:00Z').resolvedLate, isNull);
      expect(_ticket(resolveByISO: '2026-08-22T17:00:00Z').resolvedLate, isNull);
      expect(_ticket().resolvedLate, isNull);
    });

    test('an unparseable timestamp is unknown, not late', () {
      final t = _ticket(resolveByISO: 'not-a-date', resolvedISO: 'also-not');
      expect(t.resolvedLate, isNull);
    });
  });

  group('respondedLate', () {
    test('first response after its deadline is late', () {
      final t = _ticket(
        respByISO: '2026-08-15T10:00:00Z',
        respondedISO: '2026-08-16T10:00:00Z',
      );
      expect(t.respondedLate, isTrue);
    });

    test('first response inside its deadline is not late', () {
      final t = _ticket(
        respByISO: '2026-08-15T10:00:00Z',
        respondedISO: '2026-08-15T09:59:00Z',
      );
      expect(t.respondedLate, isFalse);
    });

    test('the two axes are independent', () {
      // Responded on time, resolved late — the banner must not colour both
      // from one verdict.
      final t = _ticket(
        respByISO: '2026-08-15T10:00:00Z',
        respondedISO: '2026-08-15T09:00:00Z',
        resolveByISO: '2026-08-22T17:00:00Z',
        resolvedISO: '2026-09-11T12:00:00Z',
      );
      expect(t.respondedLate, isFalse);
      expect(t.resolvedLate, isTrue);
    });
  });
}
