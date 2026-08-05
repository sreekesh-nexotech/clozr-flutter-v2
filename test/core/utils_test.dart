import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/utils/inr_format.dart';
import 'package:clozrapp/core/utils/relative_time.dart';
import 'package:clozrapp/data/api/status_keys.dart';

void main() {
  group('formatInr', () {
    test('formats crores, lakhs, thousands and rupees', () {
      expect(formatInr(31200000), '₹3.1Cr');
      expect(formatInr(3650000), '₹36.5L');
      expect(formatInr(1800000), '₹18L');
      expect(formatInr(45000), '₹45K');
      expect(formatInr(950), '₹950');
      expect(formatInr(0), '₹0');
      expect(formatInr(null), '');
    });

    test('parseAmount handles numbers and 2-dp strings', () {
      expect(parseAmount(450000), 450000);
      expect(parseAmount('450000.00'), 450000);
      expect(parseAmount('0.00'), 0);
      expect(parseAmount(null), 0);
      expect(parseAmount('garbage'), 0);
    });
  });

  group('relativeTime', () {
    final now = DateTime(2026, 7, 9, 9, 41);
    test('buckets match the design vocabulary', () {
      expect(relativeTime(now.subtract(const Duration(seconds: 30)), now: now),
          'Just now');
      expect(relativeTime(now.subtract(const Duration(minutes: 7)), now: now),
          '7m ago');
      expect(relativeTime(now.subtract(const Duration(hours: 5)), now: now),
          '5h ago');
      expect(relativeTime(DateTime(2026, 7, 8, 5, 0), now: now), 'Yesterday');
      expect(relativeTime(DateTime(2026, 7, 5, 9, 0), now: now), '4d ago');
      expect(relativeTime(DateTime(2026, 6, 1), now: now), '1 Jun');
      expect(relativeTime(null), '');
    });

    test('parseApiDate is defensive', () {
      expect(parseApiDate('2026-08-04T05:12:00Z'), isNotNull);
      expect(parseApiDate('not-a-date'), isNull);
      expect(parseApiDate(null), isNull);
      expect(parseApiDate(''), isNull);
    });

    test('a server clock ahead of the device clamps to "Just now"', () {
      final now = DateTime(2026, 7, 9, 9, 41);
      // Future timestamps (clock skew) must never render "-1d ago".
      expect(relativeTime(now.add(const Duration(hours: 3)), now: now), 'Just now');
      expect(relativeTime(now.add(const Duration(days: 2)), now: now), 'Just now');
    });
  });

  group('status keys', () {
    test('lead names and types map onto StatusMeta keys', () {
      expect(leadStatusKey(name: 'New'), 'new');
      expect(leadStatusKey(name: 'Qualified'), 'qualified');
      expect(leadStatusKey(name: 'Quote sent'), 'quote');
      expect(leadStatusKey(name: 'Negotiation'), 'negotiation');
      expect(leadStatusKey(name: 'Won'), 'won');
      expect(leadStatusKey(name: 'Lost'), 'lost');
      expect(leadStatusKey(name: 'Junk / Spam'), 'archived');
      // Renamed org status falls back to the fixed type.
      expect(leadStatusKey(name: 'Deal Closed!', type: 'won'), 'won');
      expect(leadStatusKey(name: 'Rubbish', type: 'junk'), 'archived');
      expect(leadStatusKey(name: null, type: null), 'new');
    });

    test('customer types win over names', () {
      expect(customerStatusKey(type: 'upsell_in_progress'), 'upsell');
      expect(customerStatusKey(type: 'completed'), 'completed');
      expect(customerStatusKey(name: 'Churned', type: 'lost'), 'lost');
      expect(customerStatusKey(name: 'VIP', type: 'active'), 'active');
    });

    test('crm task statuses', () {
      expect(crmTaskStatusKey(name: 'Open', type: 'open'), 'todo');
      expect(crmTaskStatusKey(name: 'In Progress', type: 'in_progress'),
          'inprogress');
      expect(crmTaskStatusKey(name: 'Blocked'), 'blocked');
      expect(crmTaskStatusKey(name: 'Completed', type: 'completed'), 'done');
      expect(crmTaskStatusKey(name: 'Cancelled', type: 'cancelled'), 'blocked');
    });

    test('followup derivation from due date + completion', () {
      final now = DateTime(2026, 7, 9);
      expect(followupStatusKey(isCompleted: true, now: now), 'done');
      expect(
          followupStatusKey(
              isCompleted: false, dueDate: DateTime(2026, 7, 1), now: now),
          'overdue');
      expect(
          followupStatusKey(
              isCompleted: false, dueDate: DateTime(2026, 7, 20), now: now),
          'due');
      expect(followupStatusKey(isCompleted: false, now: now), 'due');
    });

    test('quote effective status expires past validity', () {
      final now = DateTime(2026, 7, 9);
      expect(quoteStatusKey(name: 'Accepted', now: now), 'accepted');
      expect(quoteStatusKey(name: 'Draft', now: now), 'draft');
      expect(
          quoteStatusKey(
              name: 'Sent', validUntil: DateTime(2026, 6, 1), now: now),
          'expired');
      expect(
          quoteStatusKey(
              name: 'Sent', validUntil: DateTime(2026, 8, 1), now: now),
          'sent');
      expect(quoteStatusKey(name: 'anything', isConverted: true), 'accepted');
    });

    test('payment records split pending into due vs scheduled', () {
      final now = DateTime(2026, 7, 9);
      expect(paymentStatusKey(status: 'paid'), 'paid');
      expect(paymentStatusKey(status: 'overdue'), 'overdue');
      expect(
          paymentStatusKey(
              status: 'pending', dueDate: DateTime(2026, 7, 9), now: now),
          'due');
      expect(
          paymentStatusKey(
              status: 'pending', dueDate: DateTime(2026, 8, 1), now: now),
          'scheduled');
      expect(
          paymentStatusKey(
              status: 'pending', dueDate: DateTime(2026, 6, 1), now: now),
          'overdue');
    });

    test('invoice buckets from status + paid amount', () {
      expect(invoiceStatusKey(status: 'completed'), 'completed');
      expect(invoiceStatusKey(status: 'active', amountPaid: 5000), 'partial');
      expect(invoiceStatusKey(status: 'active', amountPaid: 0), 'unpaid');
    });

    test('projects, ops tasks, tickets, priorities', () {
      expect(projectStatusKey(name: 'Planning'), 'planning');
      expect(projectStatusKey(name: 'On Hold'), 'onhold');
      expect(projectStatusKey(name: 'Anything', isClosed: true), 'completed');
      expect(opsTaskStatusKey(name: 'Pending Review'), 'review');
      expect(opsTaskStatusKey(name: 'Working'), 'working');
      expect(opsTaskStatusKey(name: 'X', isCancelled: true), 'cancelled');
      expect(ticketStatusKey('Resolved'), 'resolved');
      expect(ticketStatusKey('On Hold'), 'pending');
      expect(ticketStatusKey('Anything'), 'open');
      expect(priorityKey('urgent'), 'Urgent');
      expect(priorityKey('HIGH'), 'High');
      expect(priorityKey(null), 'Medium');
    });
  });
}
