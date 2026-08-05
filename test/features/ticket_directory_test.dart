import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:clozrapp/features/crm/domain/entities/customer.dart';
import 'package:clozrapp/features/helpdesk/application/filters/tickets_filter_spec.dart';
import 'package:clozrapp/features/helpdesk/application/providers/tickets_providers.dart';
import 'package:clozrapp/features/helpdesk/domain/entities/ticket.dart';
import 'package:clozrapp/features/operations/domain/entities/project.dart';

Customer _customer({required String id, required String name, String? company}) => Customer(
      id: id,
      leadId: null,
      name: name,
      initials: 'XX',
      company: company,
      project: '',
      value: '',
      valueNum: 0,
      status: 'active',
      since: '',
      statusDays: 0,
      score: 0,
      source: '',
      owner: 'me',
      team: const [],
      phone: '',
      email: '',
      website: '',
      industry: '',
      location: '',
      createdOn: '',
      time: '',
      lastFu: '',
      notif: 0,
    );

Project _project({required String id, required String name, required String cost}) => Project(
      id: id,
      name: name,
      type: 'Fit-out',
      company: null,
      internal: false,
      status: 'active',
      pri: 'Medium',
      progress: 0,
      manager: 'me',
      assignees: const [],
      myTask: false,
      start: '',
      end: '',
      endISO: '2026-08-30',
      cost: cost,
      visibility: '',
      method: 'Manual',
      desc: '',
    );

Ticket _ticket({required String custId, String? projId}) => Ticket(
      id: 'TKT-1',
      subject: 'Subject',
      cat: 'Query',
      custId: custId,
      contact: '',
      channel: 'Email',
      status: 'open',
      pri: 'Medium',
      assignees: const ['me'],
      product: null,
      projId: projId,
      taskId: null,
      created: '',
      responded: null,
      resolved: null,
      respByISO: null,
      respByLabel: null,
      resolveByISO: null,
      resolveByLabel: null,
      desc: '',
    );

void main() {
  group('TicketLookups.fromData (API-mode resolution, audit L-6)', () {
    final dir = TicketLookups.fromData(
      [
        _customer(id: 'cust-1', name: 'Ramesh Pillai', company: 'Kalyan Silks'),
        _customer(id: 'cust-2', name: 'Solo Contact', company: null),
      ],
      [
        _project(id: 'proj-1', name: 'Showroom fit-out', cost: '₹18L'),
      ],
    );

    test('resolves a known customer to its real company + contact', () {
      expect(dir.customer('cust-1')?.display, 'Kalyan Silks');
      expect(dir.customer('cust-1')?.name, 'Ramesh Pillai');
    });

    test('display falls back to contact name when company is empty', () {
      expect(dir.customer('cust-2')?.display, 'Solo Contact');
    });

    test('resolves a known project to its real name + cost', () {
      expect(dir.project('proj-1')?.name, 'Showroom fit-out');
      expect(dir.project('proj-1')?.cost, '₹18L');
    });

    test('an unknown id yields null — never fabricated data', () {
      expect(dir.customer('missing'), isNull);
      expect(dir.project('missing'), isNull);
      expect(dir.customer(null), isNull);
      expect(dir.project(null), isNull);
    });

    test('ticketCustomerDisplay uses the lookups, blank when unmatched', () {
      expect(ticketCustomerDisplay(_ticket(custId: 'cust-1'), dir), 'Kalyan Silks');
      expect(ticketCustomerDisplay(_ticket(custId: 'missing'), dir), '');
    });
  });

  group('ticketDirectoryProvider (mock mode)', () {
    test('serves the ported TicketDirectory maps when the API is disabled', () {
      // No API_BASE_URL dart-define under test → ApiConfig.apiEnabled is false.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final dir = container.read(ticketDirectoryProvider);
      expect(dir.customer('C2001')?.display, 'Kalyan Silks');
      expect(dir.project('PRJ-2401')?.name, 'Kalyan Silks showroom fit-out');
      expect(dir.project('PRJ-2401')?.cost, '₹18L');
      expect(dir.customer('nope'), isNull);
    });
  });
}
