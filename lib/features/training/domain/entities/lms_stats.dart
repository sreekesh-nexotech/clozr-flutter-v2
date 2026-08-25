/// The Training Overview's headline figures, straight from
/// `GET /lms/dashboard/stats/`.
///
/// The tiles used to derive these from whatever the screen had loaded: courses
/// were counted off the fetched page, learners off `/lms/learners/` (which
/// `403`s for a non-admin, so it read 0), and average completion was averaged
/// over the enrolments in hand. This is the org's own answer.
class LmsStats {
  const LmsStats({
    this.totalCourses = 0,
    this.publishedCourses = 0,
    this.draftCourses = 0,
    this.totalLearners = 0,
    this.avgCompletion = 0,
    this.timeInvestedHours = 0,
  });

  final int totalCourses;
  final int publishedCourses;
  final int draftCourses;
  final int totalLearners;

  /// Whole percent, as the tile prints it.
  final int avgCompletion;

  /// Learner hours across the org. Not on screen yet — no tile claims it.
  final double timeInvestedHours;

  /// `{"total_courses": {"total", "published", "drafts"}, "total_learners",
  /// "avg_completion_percentage", "total_time_invested_hours"}`.
  ///
  /// Every figure is optional: a shape that loses a key answers 0 for it
  /// rather than failing the whole card.
  static LmsStats fromJson(Object? body) {
    if (body is! Map) return const LmsStats();
    final courses = body['total_courses'];
    return LmsStats(
      totalCourses: _int(courses is Map ? courses['total'] : null),
      publishedCourses: _int(courses is Map ? courses['published'] : null),
      draftCourses: _int(courses is Map ? courses['drafts'] : null),
      totalLearners: _int(body['total_learners']),
      avgCompletion: _int(body['avg_completion_percentage']),
      timeInvestedHours: _double(body['total_time_invested_hours']),
    );
  }

  static int _int(Object? v) {
    if (v is num) return v.round();
    if (v is String) return (double.tryParse(v) ?? 0).round();
    return 0;
  }

  static double _double(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
