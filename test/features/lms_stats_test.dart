// The Training Overview's tiles used to count whatever the screen had loaded:
// courses off the fetched page, learners off an admin-only endpoint that 403s
// (so it read 0 for everyone else), completion averaged over the enrolments in
// hand. `GET /lms/dashboard/stats/` is the org's own answer.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/training/domain/entities/lms_stats.dart';

void main() {
  group('LmsStats.fromJson', () {
    /// The documented payload, verified against the dev backend.
    Map<String, dynamic> body() => {
          'total_courses': {'total': 12, 'published': 9, 'drafts': 3},
          'total_learners': 48,
          'avg_completion_percentage': 63.4,
          'total_time_invested_hours': 210.75,
        };

    test('reads every figure, including the ones no tile shows yet', () {
      final s = LmsStats.fromJson(body());
      expect(s.totalCourses, 12);
      expect(s.publishedCourses, 9);
      expect(s.draftCourses, 3);
      expect(s.totalLearners, 48);
      expect(s.timeInvestedHours, 210.75);
    });

    test('the percentage is rounded to what the tile prints', () {
      expect(LmsStats.fromJson(body()).avgCompletion, 63);
    });

    test('an empty org maps to zeros, not to nulls', () {
      final s = LmsStats.fromJson({
        'total_courses': {'total': 0, 'published': 0, 'drafts': 0},
        'total_learners': 0,
        'avg_completion_percentage': 0,
        'total_time_invested_hours': 0,
      });
      expect(s.totalCourses, 0);
      expect(s.avgCompletion, 0);
      expect(s.timeInvestedHours, 0);
    });

    test('money-style strings parse too', () {
      final s = LmsStats.fromJson({
        'total_learners': '48',
        'avg_completion_percentage': '63.4',
        'total_time_invested_hours': '210.75',
      });
      expect(s.totalLearners, 48);
      expect(s.avgCompletion, 63);
      expect(s.timeInvestedHours, 210.75);
    });

    test('a shape that loses keys degrades rather than throwing', () {
      expect(LmsStats.fromJson(const {}).totalCourses, 0);
      expect(LmsStats.fromJson(null).totalLearners, 0);
      expect(LmsStats.fromJson('nonsense').avgCompletion, 0);
      // `total_courses` present but not an object.
      expect(LmsStats.fromJson({'total_courses': 5}).totalCourses, 0);
    });
  });
}
