// Fixture → entity assertions for the LMS remote mappers.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/app/theme/app_colors.dart';
import 'package:clozrapp/data/api/user_directory.dart';
import 'package:clozrapp/features/training/infrastructure/data_sources/local/lms_mock_ds.dart';
import 'package:clozrapp/features/training/infrastructure/data_sources/local/lms_people.dart';
import 'package:clozrapp/features/training/infrastructure/data_sources/remote/lms_remote_ds.dart';
import 'package:clozrapp/features/training/infrastructure/repositories/lms_repository_impl.dart';

Map<String, dynamic> courseRow({
  String id = 'c0000000-0000-0000-0000-000000000001',
  String status = 'published',
  Object? roles,
  bool universal = true,
}) =>
    {
      'course_id': id,
      'title': 'CRM Fundamentals',
      'status': status,
      'is_sequential': true,
      'is_mandatory': true,
      'is_universal': universal,
      'deadline': '2026-08-20T12:00:00Z',
      'modules_count': 4,
      if (roles != null) 'assigned_to_roles': roles,
    };

void main() {
  group('mapCourse', () {
    test('maps a list row: ids, flags, status, deadline, empty modules', () {
      final c = LmsRemoteDataSource.mapCourse(courseRow(), 0)!;
      expect(c.id, 'c0000000-0000-0000-0000-000000000001');
      expect(c.title, 'CRM Fundamentals');
      expect(c.status, 'published');
      expect(c.isPublished, isTrue);
      expect(c.sequential, isTrue);
      expect(c.mandatory, isTrue);
      expect(c.role, 'All Roles'); // is_universal → All Roles
      expect(c.deadlineISO, '2026-08-20'); // date-only, LmsLogic-parseable
      expect(c.deadline, isNotEmpty);
      expect(c.modules, isEmpty); // list payload has no embedded modules
    });

    test('maps draft status and a specific assigned role', () {
      final c = LmsRemoteDataSource.mapCourse(
        courseRow(
          status: 'draft',
          universal: false,
          roles: [
            {'role_id': 'r-1', 'name': 'Sales rep'}
          ],
        ),
        0,
      )!;
      expect(c.status, 'draft');
      expect(c.isPublished, isFalse);
      expect(c.role, 'Sales rep');
    });

    test('role name "all" and missing roles both fall back to All Roles', () {
      final all = LmsRemoteDataSource.mapCourse(
        courseRow(universal: false, roles: [
          {'role_id': null, 'name': 'all'}
        ]),
        0,
      )!;
      expect(all.role, 'All Roles');
      final none = LmsRemoteDataSource.mapCourse(
        courseRow(universal: false),
        0,
      )!;
      expect(none.role, 'All Roles');
    });

    test('defensive nulls: bare row still maps, missing id is skipped', () {
      final bare = LmsRemoteDataSource.mapCourse({'course_id': 'x'}, 0)!;
      expect(bare.title, '');
      expect(bare.status, 'draft');
      expect(bare.sequential, isFalse);
      expect(bare.deadline, '');
      expect(bare.deadlineISO, '');
      expect(LmsRemoteDataSource.mapCourse({'title': 'No id'}, 0), isNull);
    });

    test('visuals cycle deterministically by index and wrap at 6', () {
      final rows = [for (var i = 0; i < 7; i++) courseRow(id: 'c-$i')];
      final courses = LmsRemoteDataSource.mapCourseRows(rows);
      expect(courses, hasLength(7));
      expect(courses[0].tint, AppColors.blueSubtle);
      expect(courses[0].accent, AppColors.blueBright);
      expect(courses[1].accent, AppColors.success);
      expect(courses[3].accent, AppColors.pending);
      expect(courses[5].tint, AppColors.tintNavy);
      // Index 6 wraps back to the first combo.
      expect(courses[6].tint, courses[0].tint);
      expect(courses[6].icon, courses[0].icon);
    });

    test('detail-shaped row maps embedded modules', () {
      final c = LmsRemoteDataSource.mapCourse({
        ...courseRow(),
        'modules': [
          {
            'module_id': 'm-1',
            'title': 'Intro',
            'video_resources': [
              {'video_resource_id': 'v-1', 'duration_seconds': 300}
            ],
            'resources': [
              {'title': 'Guide.pdf'}
            ],
          },
          {'no_module_id': true}, // skipped
        ],
      }, 0)!;
      expect(c.modules, hasLength(1));
      expect(c.modules.first.id, 'm-1');
      expect(c.modules.first.title, 'Intro');
      expect(c.modules.first.video, isTrue);
      expect(c.modules.first.dur, '5 min');
      expect(c.modules.first.res, ['Guide.pdf']);
    });

    test('malformed rows are skipped, never fatal', () {
      final courses = LmsRemoteDataSource.mapCourseRows(
        [42, 'nope', null, courseRow()],
      );
      expect(courses, hasLength(1));
    });
  });

  group('mapEnrollmentRow', () {
    test('replicates the overall percentage across the module count', () {
      final e = LmsRemoteDataSource.mapEnrollmentRow(
        {'course_id': 'c-1', 'completion_percentage': 60.0},
        moduleCount: 4,
      )!;
      expect(e.courseId, 'c-1');
      expect(e.mods, [60, 60, 60, 60]);
    });

    test('unknown module count collapses to a single overall value', () {
      final e = LmsRemoteDataSource.mapEnrollmentRow(
        {'course_id': 'c-1', 'completion_percentage': 45.4},
      )!;
      expect(e.mods, [45]);
    });

    test('defensive: null pct → 0, out-of-range clamped, missing id → null', () {
      expect(
        LmsRemoteDataSource.mapEnrollmentRow({'course_id': 'c-1'})!.mods,
        [0],
      );
      expect(
        LmsRemoteDataSource.mapEnrollmentRow(
          {'course_id': 'c-1', 'completion_percentage': 150},
        )!.mods,
        [100],
      );
      expect(
        LmsRemoteDataSource.mapEnrollmentRow({'completion_percentage': 10}),
        isNull,
      );
    });
  });

  group('mapLearnerRow', () {
    tearDown(UserDirectory.reset);

    test('builds an aggregate record and registers the person', () {
      final rec = LmsRemoteDataSource.mapLearnerRow({
        'user_id': 'u-2',
        'name': 'Asha Peter',
        'role': {'role_id': 'r-1', 'name': 'Sales rep'},
        'assigned_courses': 3,
        'completed_courses': 1,
        'overall_progress_percentage': 33.3,
        'status': 'in_progress',
      })!;
      expect(rec.rid, 'u-2');
      expect(rec.courses, hasLength(3));
      expect(rec.courses[0].mods, [100]); // completed course
      expect(rec.courses[1].mods, [33]); // in progress at the overall pct
      expect(LmsPeople.of('u-2').name, 'Asha Peter');
      expect(LmsPeople.of('u-2').initials, 'AP');
      expect(LmsPeople.of('u-2').role, 'Sales rep');
    });

    test('not-started learners stay at zero', () {
      final rec = LmsRemoteDataSource.mapLearnerRow({
        'user_id': 'u-3',
        'name': 'New Joiner',
        'assigned_courses': 2,
        'completed_courses': 0,
        'overall_progress_percentage': 0.0,
        'status': 'not_started',
      })!;
      expect(rec.courses.map((c) => c.mods).toList(), [
        [0],
        [0]
      ]);
    });

    test("the signed-in user's row is skipped (covered by my-courses)", () {
      UserDirectory.currentUserId = 'u-me';
      expect(
        LmsRemoteDataSource.mapLearnerRow({'user_id': 'u-me', 'name': 'Me'}),
        isNull,
      );
      expect(LmsRemoteDataSource.mapLearnerRow({'name': 'No id'}), isNull);
    });
  });

  group('mapActivityRow', () {
    test('maps colours onto the mock palette and formats time', () {
      final a = LmsRemoteDataSource.mapActivityRow({
        'user_name': 'Arjun Nair',
        'description': 'completed CRM Fundamentals',
        'color': 'green',
        'created_at':
            DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
      })!;
      expect(a.dot, AppColors.success);
      expect(a.who, 'Arjun Nair');
      expect(a.what, 'completed CRM Fundamentals');
      expect(a.time, '2h ago');
    });

    test('violet maps to the purple accent; unknown falls back to blue', () {
      expect(
        LmsRemoteDataSource.mapActivityRow(
            {'user_name': 'X', 'description': 'y', 'color': 'violet'})!.dot,
        AppColors.pending,
      );
      expect(
        LmsRemoteDataSource.mapActivityRow(
            {'user_name': 'X', 'description': 'y', 'color': 'plaid'})!.dot,
        AppColors.blueBright,
      );
    });

    test('composes what from action + course title when no description', () {
      final a = LmsRemoteDataSource.mapActivityRow({
        'user_name': 'Sneha Thomas',
        'action': 'course_completed',
        'course_title': 'Sales 101',
        'color': 'red',
      })!;
      expect(a.what, 'course completed Sales 101');
    });

    test('empty rows return null', () {
      expect(LmsRemoteDataSource.mapActivityRow({}), isNull);
    });
  });

  group('mock repository (async contract)', () {
    test('still serves the full seed and no-ops progress writes', () async {
      const repo = LmsRepositoryImpl(LmsMockDataSource());
      expect(await repo.getCourses(), hasLength(6));
      expect(await repo.getRecords(), hasLength(8));
      expect(await repo.getActivity(), hasLength(5));
      await repo.setModuleProgress(
          courseId: 'LC-01', moduleId: 'm1', index: 0, value: 100);
    });
  });
}
