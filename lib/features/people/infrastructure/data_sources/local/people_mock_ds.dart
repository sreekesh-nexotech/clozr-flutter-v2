import '../../../domain/entities/member.dart';
import '../../../domain/entities/role.dart';
import '../../../domain/entities/team.dart';

/// Static People seed — a 1:1 port of the prototype's `members`, `teams` and
/// `roles` arrays. This is the ONLY place People sample data lives. To
/// integrate the API, replace this class with a remote data source returning
/// the same lists; nothing else changes.
///
/// Member performance snapshots are the "all-time" aggregates the prototype
/// computes from each rep's owned leads (open / closed / won / won value /
/// conversion).
class PeopleMockDataSource {
  const PeopleMockDataSource();

  List<Member> fetchMembers() => const [
        Member(id: 'mv', name: 'Manoj Varma', email: 'manoj.varma@kairali.in', phone: '+91 98470 11001', role: 'System Admin', scope: 'Organization-wide', reportsTo: '— (exempt)', team: '—', status: 'active'),
        Member(id: 'lp', name: 'Lakshmi Pillai', email: 'lakshmi.pillai@kairali.in', phone: '+91 98470 11001', role: 'Executive Leadership', scope: 'Organization-wide', reportsTo: 'Manoj Varma', team: '—', status: 'active'),
        Member(id: 'an', name: 'Arjun Nair', email: 'arjun.nair@kairali.in', phone: '+91 98470 11001', role: 'Manager', scope: 'Team-based + Reporting Hierarchy', reportsTo: 'Lakshmi Pillai', team: 'Team Central', status: 'active', perfOpen: 1),
        Member(id: 'am', name: 'Anjana Menon', email: 'anjana.menon@kairali.in', phone: '+91 98470 11001', role: 'Sales executive', scope: 'Self + Reporting Hierarchy', reportsTo: 'Arjun Nair', team: 'Team Kochi', status: 'active', perfOpen: 1, perfClosed: 2, perfWon: 2, perfWonVal: '₹1.47Cr', perfConv: '100%'),
        Member(id: 'rk', name: 'Rahul Krishnan', email: 'rahul.krishnan@kairali.in', phone: '+91 98470 11001', role: 'Sales executive', scope: 'Self + Reporting Hierarchy', reportsTo: 'Arjun Nair', team: 'Team Kochi', status: 'active', perfOpen: 3),
        Member(id: 'fa', name: 'Fariz Ahmed', email: 'fariz.ahmed@kairali.in', phone: '+91 98470 11001', role: 'Sales executive', scope: 'Self + Reporting Hierarchy', reportsTo: 'Arjun Nair', team: 'Team North Kerala', status: 'active', perfOpen: 1, perfClosed: 1, perfWon: 1, perfWonVal: '₹55L', perfConv: '100%'),
        Member(id: 'dr', name: 'Deepak Raj', email: 'deepak.raj@kairali.in', phone: '+91 98470 11001', role: 'Sales executive', scope: 'Self + Reporting Hierarchy', reportsTo: 'Arjun Nair', team: 'Team South Kerala', status: 'active', perfOpen: 2, perfClosed: 1, perfWon: 0, perfWonVal: '₹0L', perfConv: '0%'),
        Member(id: 'st', name: 'Sneha Thomas', email: 'sneha.thomas@kairali.in', phone: '+91 98470 11001', role: 'Sales executive', scope: 'Self + Reporting Hierarchy', reportsTo: 'Arjun Nair', team: 'Team Kochi', status: 'active', perfOpen: 1, perfClosed: 1, perfWon: 1, perfWonVal: '₹92L', perfConv: '100%'),
        Member(id: 'rj', name: 'Reena Jacob', email: 'reena.jacob@kairali.in', phone: '+91 98470 11001', role: 'Viewer', scope: 'Organization-wide', reportsTo: 'Lakshmi Pillai', team: '—', status: 'invited'),
      ];

  List<Team> fetchTeams() => const [
        Team(id: 'kochi', name: 'Team Kochi', zone: 'Kochi metro', lead: 'am', members: ['am', 'rk', 'st']),
        Team(id: 'central', name: 'Team Central', zone: 'Central zone', lead: 'an', members: ['an']),
        Team(id: 'north', name: 'Team North Kerala', zone: 'North zone', lead: 'fa', members: ['fa']),
        Team(id: 'south', name: 'Team South Kerala', zone: 'South zone', lead: 'dr', members: ['dr']),
      ];

  List<Role> fetchRoles() => const [
        Role(id: 'r1', name: 'System Admin', locked: true, scope: 'Organization-wide', desc: 'Full control including settings, integrations and billing. Exactly one per workspace.', caps: ['User Management', 'CRM', 'Reports & Dashboards', 'Record payments', 'Settings & Billing']),
        Role(id: 'r2', name: 'Executive Leadership', locked: true, scope: 'Self + Reporting Hierarchy', desc: 'Org-wide visibility across all reporting lines.', caps: ['CRM', 'Reports & Dashboards', 'Record payments']),
        Role(id: 'r3', name: 'Manager', locked: true, scope: 'Team-based + Reporting Hierarchy', desc: 'Manages team pipelines, tasks and approvals.', caps: ['CRM', 'Reports & Dashboards', 'Record payments']),
        Role(id: 'r4', name: 'Sales executive', locked: true, scope: 'Team-based + Reporting Hierarchy', desc: 'Works own and team leads end-to-end.', caps: ['CRM']),
        Role(id: 'r5', name: 'Viewer', locked: true, scope: 'Self + Reporting Hierarchy', desc: 'Read-only access to reports and records.', caps: ['Reports & Dashboards']),
      ];
}
