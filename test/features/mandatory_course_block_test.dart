import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/mandatory_course_block.dart';
import 'package:clozrapp/features/training/application/providers/mandatory_block_provider.dart';

void main() {
  group('mandatory-course 403 body', () {
    test('matches the code or the incomplete_courses array only', () {
      expect(isMandatoryCourseBlock({'code': 'mandatory_course_incomplete'}),
          isTrue);
      expect(isMandatoryCourseBlock({'code': 403, 'incomplete_courses': []}),
          isTrue);
      expect(isMandatoryCourseBlock({'code': 'feature_not_in_plan'}), isFalse);
      expect(isMandatoryCourseBlock({'detail': 'Permission denied.'}), isFalse);
      expect(isMandatoryCourseBlock(null), isFalse);
    });

    test('parses the courses tolerantly', () {
      final c = parseIncompleteCourses({
        'incomplete_courses': [
          {'course_id': 'c1', 'title': 'Safety', 'completion': 40},
          {'bad': true},
        ],
      });
      expect(c.length, 2);
      expect(c.first.title, 'Safety');
      expect(c.first.completion, 40);
      expect(c.last.title, 'Required course');
      expect(parseIncompleteCourses({'incomplete_courses': 'x'}), isEmpty);
    });
  });

  group('block state', () {
    test('a recheck suppresses re-blocking for the cooldown only', () {
      var now = DateTime(2026, 10, 30, 10);
      final n = MandatoryBlockNotifier(now: () => now);
      const course =
          IncompleteCourse(courseId: 'c1', title: 'Safety', completion: 0);

      n.setBlock(const [course]);
      expect(n.state.blocked, isTrue);
      expect(n.state.courses.single.courseId, 'c1');

      n.clearBlock();
      expect(n.state.blocked, isFalse);
      now = now.add(const Duration(minutes: 1));
      n.setBlock(const [course]); // stale server cache — ignored
      expect(n.state.blocked, isFalse);

      now = now.add(const Duration(minutes: 2));
      n.setBlock(const [course]);
      expect(n.state.blocked, isTrue);
    });
  });
}
