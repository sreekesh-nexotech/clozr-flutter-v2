import 'package:clozrapp/core/filters/filter_models.dart';
import 'package:clozrapp/features/helpdesk/application/filters/tickets_filter_spec.dart';
import 'package:clozrapp/features/helpdesk/domain/entities/ticket.dart';
import 'package:clozrapp/features/helpdesk/presentation/util/ticket_sla.dart';
import 'package:flutter_test/flutter_test.dart';

Ticket _t(TicketServerFacts facts) => Ticket(
      id: 'i1',
      subject: 's',
      cat: '',
      custId: '',
      contact: '',
      channel: '',
      status: 'open',
      pri: 'Medium',
      assignees: const [],
      product: null,
      projId: null,
      taskId: null,
      created: '',
      responded: null,
      resolved: null,
      respByISO: null,
      respByLabel: null,
      resolveByISO: null,
      resolveByLabel: null,
      desc: '',
      facts: facts,
    );

void main() {
  group('list SLA chip follows the webapp issueSlaChip', () {
    test('no deadline, on hold, resolved', () {
      expect(ticketListSlaChip(_t(const TicketServerFacts())).text, 'No SLA');
      expect(ticketListSlaChip(_t(const TicketServerFacts(hasSla: true, statusOnHold: true, slaRemainingSeconds: 50))).text,
          'Paused');
      expect(ticketListSlaChip(_t(const TicketServerFacts(hasSla: true, statusResolved: true, slaRemainingSeconds: 10))).text,
          'Met');
      expect(
          ticketListSlaChip(_t(const TicketServerFacts(
                  hasSla: true, statusResolved: true, slaRemainingSeconds: -10, slaBreachedFlag: true)))
              .text,
          'Breached');
    });

    test('countdowns: on track, within 24h, overdue, first response', () {
      expect(ticketListSlaChip(_t(const TicketServerFacts(hasSla: true, slaRemainingSeconds: 2 * 86400 + 3600))).text,
          '2d 1h left');
      expect(ticketListSlaChip(_t(const TicketServerFacts(hasSla: true, slaRemainingSeconds: 3000))).text, '50m left');
      expect(ticketListSlaChip(_t(const TicketServerFacts(hasSla: true, slaRemainingSeconds: -7200))).text,
          'Overdue 2h 0m');
      expect(
          ticketListSlaChip(_t(const TicketServerFacts(
                  hasSla: true, slaRemainingSeconds: 90000, firstResponseDue: true, firstResponseRemainingSeconds: 5400)))
              .text,
          'Respond 1h 30m left');
    });
  });

  group('saved views store the webapp definition', () {
    test('is / is not per facet; unsupported exclusions are dropped and named', () {
      final v = FilterValues()
        ..['statuses'] = ChoiceValue(ids: {'s1', 's2'})
        ..['pri'] = ChoiceValue(ids: {'High'}, isNot: true)
        ..['companies'] = ChoiceValue(ids: {'c1'}, isNot: true)
        ..['products'] = ChoiceValue(ids: {'p1'});
      final built = encodeTicketView(v);
      expect(built.definition['status__in'], 's1,s2');
      expect(built.definition['priority__not'], 'High');
      expect(built.definition['product__in'], 'p1');
      expect(built.definition.containsKey('customer__not'), isFalse);
      expect(built.unsupported, ['Customer']);
    });

    test('a stored definition expands back into the drawer', () {
      final v = decodeTicketView({'status__in': 's1,s2', 'priority__not': 'Low', 'project__in': '["j1"]'});
      expect(v.choice('statuses')!.ids, {'s1', 's2'});
      expect(v.choice('pri')!.isNot, isTrue);
      expect(v.choice('projects')!.ids, {'j1'});
    });
  });
}
