import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/filters/filter_models.dart';
import 'package:clozrapp/data/api/user_directory.dart';
import 'package:clozrapp/features/people/application/filters/members_filter_spec.dart';
import 'package:clozrapp/data/mock/mock_users.dart';
import 'package:clozrapp/features/people/domain/entities/member.dart';
import 'package:clozrapp/features/people/infrastructure/data_sources/remote/people_remote_ds.dart';

/// Fixture-driven tests for the People JSON → entity mappers
/// (`PeopleRemoteDataSource` statics). Shapes mirror docs-flutter/members.md,
/// team-api.md and roles.md.
void main() {
  setUp(UserDirectory.reset);

  Map<String, dynamic> memberFixture() => {
        'id': 42,
        'user_id': 'u-1234',
        'username': 'arjun.nair@kairali.in',
        'email': 'arjun.nair@kairali.in',
        'first_name': 'Arjun',
        'last_name': 'Nair',
        'full_name': 'Arjun Nair',
        'is_active': true,
        'is_staff': false,
        'role': {'role_id': 'r-abcd', 'name': 'Manager'},
        'manager': {
          'user_id': 'u-5678',
          'full_name': 'Lakshmi Pillai',
          'email': 'lakshmi.pillai@kairali.in',
        },
        'teams': [
          {'team_id': 't-1111', 'name': 'Team Central'},
          {'team_id': 't-2222', 'name': 'Team Kochi'},
        ],
        'profile': {
          'phone': '+91 98470 11001',
          'mobile': '',
          'designation': 'Business Owner',
        },
      };

  group('member mapping', () {
    test('maps an active list row onto Member', () {
      final m = PeopleRemoteDataSource.memberFromJson(memberFixture());

      expect(m, isNotNull);
      expect(m!.id, 'u-1234'); // raw uuid, NOT mapped through mapUserId
      expect(m.name, 'Arjun Nair');
      expect(m.email, 'arjun.nair@kairali.in');
      expect(m.phone, '+91 98470 11001');
      expect(m.role, 'Manager');
      expect(m.scope, '—'); // scope is detail-only; list rows fall back
      expect(m.reportsTo, 'Lakshmi Pillai');
      expect(m.team, 'Team Central'); // first of teams[]
      expect(m.status, 'active');
      // Performance stays at entity defaults — never fetched at list time.
      expect(m.perfOpen, 0);
      expect(m.perfClosed, 0);
      expect(m.perfWon, 0);
      expect(m.perfWonVal, '₹0L');
      expect(m.perfConv, '—');
    });

    test('registers every member in the UserDirectory roster', () {
      PeopleRemoteDataSource.memberFromJson(memberFixture());
      expect(MockUsers.byId['u-1234']?.name, 'Arjun Nair');
      expect(MockUsers.byId['u-1234']?.role, 'Manager');
    });

    test('invited member: inactive, no role/manager/teams/profile', () {
      final m = PeopleRemoteDataSource.memberFromJson({
        'user_id': 'u-9999',
        'email': 'new.hire@kairali.in',
        'full_name': 'New Hire',
        'is_active': false,
        'role': null,
        'manager': null,
        'teams': <dynamic>[],
        'profile': null,
      });

      expect(m, isNotNull);
      expect(m!.status, 'invited'); // is_active=false, never logged in
      expect(m.role, 'Viewer'); // null role fallback
      expect(m.reportsTo, '— (exempt)'); // null manager sentinel
      expect(m.team, '—');
      expect(m.phone, '');
    });

    // There is no status field on the backend: `is_active=false` covers both a
    // deactivated account and an unaccepted invitation, told apart by whether
    // the user has ever logged in (members.md §Status). The mapper used to
    // answer "invited" for both, so a member an admin switched off displayed as
    // Invited — and the drawer's third chip matched nothing, because the value
    // was never produced.
    group('status splits deactivated from invited', () {
      String statusOf({required bool active, Object? lastLogin}) =>
          PeopleRemoteDataSource.memberStatusKey({
            'user_id': 'u-1',
            'is_active': active,
            if (lastLogin != null) 'last_login': lastLogin,
          });

      test('active regardless of last login', () {
        expect(statusOf(active: true), 'active');
        expect(statusOf(active: true, lastLogin: '2026-08-01T10:00:00Z'), 'active');
      });

      test('disabled after having logged in is deactivated', () {
        expect(statusOf(active: false, lastLogin: '2026-08-01T10:00:00Z'),
            'inactive');
      });

      test('never logged in is still invited', () {
        expect(statusOf(active: false), 'invited');
        expect(statusOf(active: false, lastLogin: ''), 'invited');
      });

      test('an explicit null last_login reads as invited, not deactivated', () {
        expect(
          PeopleRemoteDataSource.memberStatusKey(
              {'user_id': 'u-1', 'is_active': false, 'last_login': null}),
          'invited',
        );
      });
    });

    test('phone falls back to profile.mobile and scope.label is used', () {
      final json = memberFixture()
        ..['profile'] = {'phone': '', 'mobile': '+91 90000 00000'}
        ..['scope'] = {'code': 'hierarchy', 'label': 'Self + Reporting Hierarchy'};
      final m = PeopleRemoteDataSource.memberFromJson(json);

      expect(m!.phone, '+91 90000 00000');
      expect(m.scope, 'Self + Reporting Hierarchy'); // detail rows carry scope
    });

    test('membersFromRows skips malformed rows instead of crashing', () {
      final members = PeopleRemoteDataSource.membersFromRows([
        memberFixture(),
        {'email': 'no-id@x.com'}, // missing user_id → skipped
        'garbage',
        null,
      ]);
      expect(members.length, 1);
      expect(members.single.id, 'u-1234');
    });

    test('applyPerformance overlays the member-performance payload', () {
      final base = PeopleRemoteDataSource.memberFromJson(memberFixture())!;
      final m = PeopleRemoteDataSource.applyPerformance(base, {
        'user_id': 'u-1234',
        'period': 'all_time',
        'owned_leads': {'open': 12, 'closed': 8, 'total': 20},
        'deals_won': 5,
        'deal_value_won': '450000.00', // decimal string
        'conversion_rate': 62.5,
      });

      expect(m.perfOpen, 12);
      expect(m.perfClosed, 8);
      expect(m.perfWon, 5);
      expect(m.perfWonVal, '₹4.5L');
      expect(m.perfConv, '62.5%');
      expect(m.id, base.id); // identity untouched
    });

    test('applyPerformance tolerates nulls (nothing decided yet)', () {
      final base = PeopleRemoteDataSource.memberFromJson(memberFixture())!;
      final m = PeopleRemoteDataSource.applyPerformance(base, {
        'owned_leads': null,
        'deals_won': null,
        'deal_value_won': '0.00',
        'conversion_rate': null,
      });

      expect(m.perfOpen, 0);
      expect(m.perfWon, 0);
      expect(m.perfWonVal, '₹0L');
      expect(m.perfConv, '—');
    });
  });

  // §4.1's retrieve-only fields. The detail screen read the *list* row, so
  // Designation showed the role name, Role & scope always ended in "—", and
  // Territory and Timezone were literals ("Kerala", "Asia/Kolkata (IST)").
  group('retrieve-only fields', () {
    test('a detail row fills designation, timezone, territories, protected', () {
      final m = PeopleRemoteDataSource.memberFromJson({
        'user_id': 'u-1',
        'full_name': 'Admin Acme',
        'is_active': true,
        'is_protected': true,
        'scope': {'code': 'all', 'label': 'Organization-wide'},
        'territories': [
          {'territory_id': 't-1', 'name': 'All India'},
          {'territory_id': 't-2', 'name': 'South'},
        ],
        'profile': {
          'designation': 'Business Owner',
          'timezone': 'Asia/Kolkata',
        },
      })!;

      expect(m.designation, 'Business Owner');
      expect(m.timezone, 'Asia/Kolkata');
      expect(m.territories, ['All India', 'South']);
      expect(m.isProtected, isTrue);
      expect(m.scope, 'Organization-wide');
    });

    test('a list row leaves them at their defaults, never guessed', () {
      final m = PeopleRemoteDataSource.memberFromJson({
        'user_id': 'u-2',
        'full_name': 'Priya Pandey',
        'is_active': true,
        'role': {'name': 'Admin'},
      })!;

      expect(m.designation, '');
      expect(m.timezone, '');
      expect(m.territories, isEmpty);
      // Was inferred from the role name containing "admin".
      expect(m.isProtected, isFalse);
      expect(m.scope, '—');
    });

    test('a nameless territory is dropped rather than rendered blank', () {
      final m = PeopleRemoteDataSource.memberFromJson({
        'user_id': 'u-3',
        'is_active': true,
        'territories': [
          {'territory_id': 't-1'},
          {'territory_id': 't-2', 'name': '  '},
          {'territory_id': 't-3', 'name': 'Kerala'},
        ],
      })!;

      expect(m.territories, ['Kerala']);
    });

    test('applyPerformance keeps them — the overlay must not blank the detail', () {
      final base = PeopleRemoteDataSource.memberFromJson({
        'user_id': 'u-1',
        'full_name': 'Admin Acme',
        'is_active': true,
        'is_protected': true,
        'profile': {'designation': 'Business Owner', 'timezone': 'Asia/Kolkata'},
      })!;

      final withPerf = PeopleRemoteDataSource.applyPerformance(base, {
        'owned_leads': {'open': 3, 'closed': 1},
        'deals_won': 1,
        'conversion_rate': 100.0,
      });

      expect(withPerf.perfOpen, 3);
      expect(withPerf.designation, 'Business Owner');
      expect(withPerf.timezone, 'Asia/Kolkata');
      expect(withPerf.isProtected, isTrue);
    });
  });

  // §4.3's feed, which the card used to fake: a "Today · 09:14" sign-in, a role
  // change attributed to the seed name "Manoj Varma", and a fixed joining date.
  group('activity mapping', () {
    test('maps a row, keeping the server-humanised label', () {
      final a = PeopleRemoteDataSource.activityFromJson({
        'type': 'role_assign',
        'label': 'Role updated',
        'actor': 'Admin Acme',
        'timestamp': '2026-08-10T08:22:52Z',
      })!;

      expect(a.type, 'role_assign');
      expect(a.label, 'Role updated');
      expect(a.actor, 'Admin Acme');
      expect(a.at, isNotNull);
      expect(a.at!.year, 2026);
    });

    test('a row with no label is skipped — nothing to render', () {
      expect(
        PeopleRemoteDataSource.activityFromJson(
            {'type': 'login', 'timestamp': '2026-08-10T08:22:52Z'}),
        isNull,
      );
    });

    test('a missing actor or timestamp degrades, never throws', () {
      final a = PeopleRemoteDataSource.activityFromJson(
          {'type': 'joined', 'label': 'Joined the workspace'})!;

      expect(a.actor, '');
      expect(a.at, isNull);
    });
  });

  group('team mapping', () {
    final flatMemberRows = [
      {
        'team_member_id': 'tm-1',
        'team_id': 't-east',
        'user_id': 'u-alice',
        'user': {'user_id': 'u-alice', 'full_name': 'Alice Example'},
      },
      {
        'team_member_id': 'tm-2',
        'team_id': 't-east',
        'user_id': 'u-bob',
        'user': {'user_id': 'u-bob', 'full_name': 'Bob Example'},
      },
      {
        'team_member_id': 'tm-3',
        'team_id': 't-west',
        'user_id': 'u-alice',
        'user': {'user_id': 'u-alice', 'full_name': 'Alice Example'},
      },
      {'team_member_id': 'tm-bad'}, // no team/user → skipped
    ];

    test('groups the org-wide flat member rows per team', () {
      final grouped = PeopleRemoteDataSource.groupTeamMembers(flatMemberRows);
      expect(grouped['t-east'], ['u-alice', 'u-bob']);
      expect(grouped['t-west'], ['u-alice']); // multi-team membership
      expect(grouped.length, 2);
    });

    test('maps a team row with grouped members onto Team', () {
      final grouped = PeopleRemoteDataSource.groupTeamMembers(flatMemberRows);
      final t = PeopleRemoteDataSource.teamFromJson({
        'team_id': 't-east',
        'name': 'Sales East',
        'description': 'East region sales team',
        'manager': {'user_id': 'u-jane', 'full_name': 'Jane Doe'},
      }, grouped);

      expect(t, isNotNull);
      expect(t!.id, 't-east');
      expect(t.name, 'Sales East');
      expect(t.zone, 'East region sales team');
      expect(t.lead, 'u-jane'); // lead = manager user_id
      expect(t.members, ['u-alice', 'u-bob']);
      expect(t.size, 2);
    });

    test('tolerates null description/manager and unknown team ids', () {
      final t = PeopleRemoteDataSource.teamFromJson({
        'team_id': 't-solo',
        'name': 'Solo',
        'description': null,
        'manager': null,
      }, const {});

      expect(t!.zone, '');
      expect(t.lead, '');
      expect(t.members, isEmpty);
      expect(
        PeopleRemoteDataSource.teamFromJson(<String, dynamic>{}, const {}),
        isNull, // missing team_id → skipped
      );
    });
  });

  group('role mapping', () {
    test('maps a seeded role: locked, scope from record_permissions, caps', () {
      final r = PeopleRemoteDataSource.roleFromJson({
        'role_id': 'r-admin',
        'name': 'Admin',
        'description': 'Full control.',
        'is_custom': false,
        'is_editable': false,
        'permission_level': 100,
        'user_count': 1,
        'record_permissions': [
          {'module_name': 'lead', 'permission_type': 'all'},
        ],
        'grouped_permissions': [
          {'group': 'crm', 'modules': <dynamic>[]},
          {'group': 'pmo', 'modules': <dynamic>[]},
        ],
      });

      expect(r, isNotNull);
      expect(r!.id, 'r-admin');
      expect(r.locked, isTrue); // is_editable=false → seeded/locked
      expect(r.scope, 'Organization-wide'); // permission_type all
      expect(r.desc, 'Full control.');
      expect(r.caps, ['CRM', 'PMO']); // group keys upper-cased
    });

    test('custom role: editable, scope via grouped_permissions lead module', () {
      final r = PeopleRemoteDataSource.roleFromJson({
        'role_id': 'r-custom',
        'name': 'Regional Lead',
        'is_custom': true,
        'is_editable': true,
        'record_permissions': <dynamic>[],
        'grouped_permissions': [
          {
            'group': 'crm',
            'modules': [
              {'module_name': 'lead', 'permission_type': 'hierarchy'},
            ],
          },
        ],
      });

      expect(r!.locked, isFalse);
      expect(r.scope, 'Self + Reporting Hierarchy');
      expect(r.caps, ['CRM']);
    });

    test('team scope label and full-access fallback', () {
      final teamScoped = PeopleRemoteDataSource.roleFromJson({
        'role_id': 'r-mgr',
        'name': 'Manager',
        'record_permissions': [
          {'module_name': 'lead', 'permission_type': 'team'},
        ],
      });
      expect(teamScoped!.scope, 'Team-based + Reporting Hierarchy');

      // No lead-module scope anywhere, but full-access looking → org-wide.
      final fullAccess = PeopleRemoteDataSource.roleFromJson({
        'role_id': 'r-top',
        'name': 'Owner',
        'permission_level': 100,
      });
      expect(fullAccess!.scope, 'Organization-wide');
    });

    test('null tolerance: bare role maps with safe defaults', () {
      final r = PeopleRemoteDataSource.roleFromJson({'role_id': 'r-bare'});
      expect(r!.name, '');
      expect(r.locked, isFalse); // is_editable absent ≠ seeded
      expect(r.scope, '—');
      expect(r.desc, '');
      expect(r.caps, isEmpty);
      expect(
        PeopleRemoteDataSource.roleFromJson(<String, dynamic>{}),
        isNull, // missing role_id → skipped
      );
    });
  });

  // The drawer's "Reports to" facet (`members.md` Part 1, "Any manager").
  group('members filter — reporting manager', () {
    // [managerId] is the identity the facet is keyed by; [manager] is only the
    // label. Two managers can share a name, which is why the uuid decides.
    Member withManager(String id, String manager, {String managerId = ''}) => Member(
          id: id,
          name: 'M-$id',
          email: '$id@acme.com',
          phone: '',
          role: 'Viewer',
          scope: '—',
          reportsTo: manager,
          managerId: managerId,
          team: '—',
          status: 'active',
        );

    const uLakshmi = 'u-lakshmi';
    const uArjun = 'u-arjun';
    final roster = [
      withManager('a', 'Lakshmi Pillai', managerId: uLakshmi),
      withManager('b', 'Lakshmi Pillai', managerId: uLakshmi),
      withManager('c', 'Arjun Nair', managerId: uArjun),
      // The System Admin: `manager` is null, which maps to this sentinel.
      withManager('d', '— (exempt)'),
    ];

    FilterField managerField(FilterSpec spec) => spec.sections
        .expand((s) => s.fields)
        .firstWhere((f) => f.id == 'managers');

    test('options are the managers actually named, deduped and sorted', () {
      final spec = buildMembersFilterSpec(const [], members: roster);

      expect(managerField(spec).options.map((o) => o.label).toList(),
          ['Arjun Nair', 'Lakshmi Pillai']);
    });

    test('the exempt sentinel is not offered as a manager', () {
      final spec = buildMembersFilterSpec(const [], members: roster);

      expect(managerField(spec).options.any((o) => o.label.startsWith('—')), isFalse);
      expect(managerField(spec).options.map((o) => o.id).toList(),
          [uArjun, uLakshmi]);
    });

    test('two managers sharing a name stay separate options', () {
      // Keyed by name, both collapsed into one option that matched both.
      final spec = buildMembersFilterSpec(const [], members: [
        withManager('a', 'Priya Nair', managerId: 'u-priya-1'),
        withManager('b', 'Priya Nair', managerId: 'u-priya-2'),
      ]);

      expect(managerField(spec).options.length, 2);
    });

    test('the section is dropped when nobody reports to anyone', () {
      final spec = buildMembersFilterSpec(const [],
          members: [withManager('d', '— (exempt)')]);

      expect(spec.sections.expand((s) => s.fields).any((f) => f.id == 'managers'),
          isFalse);
    });

    test("filtering matches on the manager's uuid, not the display name", () {
      final values = FilterValues()..['managers'] = ChoiceValue(ids: {uLakshmi});

      expect(memberMatchesFilters(roster[0], values), isTrue);
      expect(memberMatchesFilters(roster[2], values), isFalse);
      // A member with no manager matches nothing, not everything.
      expect(memberMatchesFilters(roster[3], values), isFalse);
    });

    test('an unset facet leaves every member matching', () {
      expect(memberMatchesFilters(roster[3], FilterValues()), isTrue);
    });
  });

  group('invite helpers', () {
    test('generateUuid emits unique RFC-4122 v4-shaped ids', () {
      final v4 = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      final seen = <String>{};
      for (var i = 0; i < 50; i++) {
        final id = PeopleRemoteDataSource.generateUuid();
        expect(v4.hasMatch(id), isTrue, reason: 'bad uuid shape: $id');
        expect(seen.add(id), isTrue, reason: 'duplicate uuid: $id');
      }
    });
  });

  test('member entity getters used by People screens stay intact', () {
    const m = Member(
      id: 'u-1',
      name: 'Arjun Nair',
      email: 'a@x.com',
      phone: '',
      role: 'Manager',
      scope: '—',
      reportsTo: '— (exempt)',
      team: '—',
      status: 'active',
    );
    expect(m.initials, 'AN');
    expect(m.hasTeam, isFalse);
    expect(m.hasManager, isFalse); // the exempt sentinel reads as no manager
  });
}
