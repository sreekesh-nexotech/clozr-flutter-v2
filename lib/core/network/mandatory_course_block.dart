/// The LMS mandatory-course hard block (webapp `core/http/blockBridge.ts`).
///
/// While a published mandatory course is unfinished, the server answers every
/// non-LMS endpoint with `403 {code: "mandatory_course_incomplete",
/// incomplete_courses: [...]}`. The app raises one blocking screen for it
/// instead of letting each screen show its own "No access".
library;

/// The machine code the middleware returns; discriminate strictly on it.
const String mandatoryCourseCode = 'mandatory_course_incomplete';

/// One incomplete mandatory course, as listed in the 403 body.
class IncompleteCourse {
  const IncompleteCourse(
      {required this.courseId, required this.title, required this.completion});

  final String courseId;
  final String title;

  /// 0–100.
  final double completion;
}

/// Whether a 403 body is the mandatory-course block: the stable code, or the
/// `incomplete_courses` array no other 403 carries (survives DRF rewriting
/// `code` to the integer status).
bool isMandatoryCourseBlock(Object? body) {
  if (body is! Map) return false;
  return body['code'] == mandatoryCourseCode ||
      body['incomplete_courses'] is List;
}

/// The `incomplete_courses` list out of a 403 body; tolerant of missing fields
/// so a malformed body can never wedge the app.
List<IncompleteCourse> parseIncompleteCourses(Object? body) {
  final list = body is Map ? body['incomplete_courses'] : null;
  if (list is! List) return const [];
  return [
    for (final row in list)
      IncompleteCourse(
        courseId: row is Map && row['course_id'] is String
            ? row['course_id'] as String
            : '',
        title: row is Map && row['title'] is String
            ? row['title'] as String
            : 'Required course',
        completion: row is Map && row['completion'] is num
            ? (row['completion'] as num).toDouble()
            : 0,
      ),
  ];
}
