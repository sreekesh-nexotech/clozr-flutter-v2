import 'entities/course.dart';
import 'entities/learner_record.dart';

/// Pure LMS status / progress logic — a 1:1 port of the prototype's helper
/// methods (`lmsPct`, `lmsDone`, `lmsStatusOf`, `lmsAggStatus`, `lmsLockedAt`).
/// Kept framework-free so both providers and widgets can derive view state
/// without duplicating rules.
class LmsLogic {
  LmsLogic._();

  /// The prototype pins "now" to this instant so overdue/deadline states are
  /// deterministic against the seed. Mirrored here for identical results.
  static final DateTime now = DateTime.parse('2026-07-09T09:41:00');

  /// Average completion of a course entry (0–100).
  static int pct(CourseProgress e) {
    if (e.mods.isEmpty) return 0;
    final sum = e.mods.fold<int>(0, (a, b) => a + b);
    return (sum / e.mods.length).round();
  }

  /// Whether every module is fully complete.
  static bool done(CourseProgress e) =>
      e.mods.isNotEmpty && e.mods.every((m) => m >= 100);

  /// Status key for a course entry: completed / overdue / inprogress / notstarted.
  static String statusOf(CourseProgress e, Course? c) {
    if (done(e)) return 'completed';
    if (c != null && c.deadlineISO.isNotEmpty) {
      final due = DateTime.parse('${c.deadlineISO}T23:59:59');
      if (due.isBefore(now)) return 'overdue';
    }
    return pct(e) > 0 ? 'inprogress' : 'notstarted';
  }

  /// Aggregate status across all a learner's courses.
  static String aggStatus(LearnerRecord rec, Course? Function(String) courseOf) {
    final sts = rec.courses.map((e) => statusOf(e, courseOf(e.courseId))).toList();
    if (sts.contains('overdue')) return 'overdue';
    if (sts.contains('inprogress')) return 'inprogress';
    if (sts.isNotEmpty && sts.every((x) => x == 'completed')) return 'completed';
    return sts.contains('notstarted') ? 'notstarted' : 'completed';
  }

  /// Whether module [idx] is locked behind an incomplete previous module
  /// (only when the course enforces sequential progression).
  static bool lockedAt(CourseProgress e, Course c, int idx) =>
      c.sequential && idx > 0 && (idx - 1 < e.mods.length ? e.mods[idx - 1] : 0) < 100;
}
