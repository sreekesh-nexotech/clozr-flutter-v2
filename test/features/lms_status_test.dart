// Three LMS status defects, all from the same root: the module was ported from
// a prototype with a frozen clock and a seed where every learner's courses
// were known, and never re-checked against a live org.
//
// * `LmsLogic.now` was pinned to 2026-07-09, so a course due 26 Aug read
//   "Not started" on 11 Sep while the server said overdue. (That fix is a
//   one-line clock switch, verified on device; it is not unit-tested here
//   because a wall-clock assertion would rot as the seed dates age.)
// * `/lms/learners/` returns aggregate counts, so other learners' courses get
//   synthetic ids with no deadline — the derived status could never be
//   overdue for them, even when the row itself said `status: overdue`.
// * The overview prepended the learner's name to a server `description` that
//   already started with it: "Admin Acme Admin Acme was enrolled in test".
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/training/domain/entities/learner_record.dart';
import 'package:clozrapp/features/training/domain/lms_logic.dart';
import 'package:clozrapp/features/training/infrastructure/data_sources/remote/lms_remote_ds.dart';

void main() {
  group('aggStatus honours the server verdict', () {
    // A row from `/lms/learners/`: one assigned course, nothing done, and the
    // server has already marked it overdue. The course id is synthetic, so
    // there is no deadline for the derived path to find.
    test('overdue from the row wins over the derived in-progress', () {
      final rec = LmsRemoteDataSource.mapLearnerRow(const {
        'user_id': 'f4ac47d8-9119-402c-91ab-c3d26fd5d644',
        'name': 'Diya Reddy',
        'role': {'name': 'CRM User'},
        'assigned_courses': 1,
        'completed_courses': 0,
        'overall_progress_percentage': 0.0,
        'status': 'overdue',
      })!;
      expect(rec.serverStatus, 'overdue');
      expect(LmsLogic.aggStatus(rec, (_) => null), 'overdue');
    });

    test('the wire spellings map onto the app keys', () {
      String? key(String raw) => LmsRemoteDataSource.mapLearnerRow({
            'user_id': 'u-$raw',
            'name': 'x',
            'assigned_courses': 1,
            'status': raw,
          })!.serverStatus;
      expect(key('in_progress'), 'inprogress');
      expect(key('not_started'), 'notstarted');
      expect(key('completed'), 'completed');
      expect(key('overdue'), 'overdue');
    });

    test('an unknown or missing status falls back to the derived one', () {
      final rec = LmsRemoteDataSource.mapLearnerRow(const {
        'user_id': 'u-none',
        'name': 'x',
        'assigned_courses': 1,
        'completed_courses': 1,
      })!;
      expect(rec.serverStatus, isNull);
      // One course, fully complete → derived says completed.
      expect(LmsLogic.aggStatus(rec, (_) => null), 'completed');
    });

    test('a locally built record still derives its status', () {
      const rec = LearnerRecord(rid: 'me', courses: [
        CourseProgress(courseId: 'c1', mods: [40, 0]),
      ]);
      expect(rec.serverStatus, isNull);
      expect(LmsLogic.aggStatus(rec, (_) => null), 'inprogress');
    });
  });

  group('activity feed', () {
    test('a description that leads with the name is not doubled', () {
      final a = LmsRemoteDataSource.mapActivityRow(const {
        'user_name': 'Admin Acme',
        'description': 'Admin Acme was enrolled in test',
        'action': 'enrolled',
        'course_title': 'test',
        'color': 'violet',
      })!;
      expect(a.who, 'Admin Acme');
      expect(a.what, 'was enrolled in test');
    });

    test('a description that does not start with the name is left alone', () {
      final a = LmsRemoteDataSource.mapActivityRow(const {
        'user_name': 'Admin Acme',
        'description': 'Course test was published',
        'action': 'published',
      })!;
      expect(a.what, 'Course test was published');
    });

    test('with no description the action and title are composed', () {
      final a = LmsRemoteDataSource.mapActivityRow(const {
        'user_name': 'Admin Acme',
        'action': 'completed_module',
        'course_title': 'test',
      })!;
      expect(a.what, 'completed module test');
    });
  });
}
