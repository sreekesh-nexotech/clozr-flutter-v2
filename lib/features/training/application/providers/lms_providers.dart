import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/learner_record.dart';
import '../../domain/entities/lms_activity.dart';
import '../../domain/repositories/lms_repository.dart';
import '../../infrastructure/data_sources/local/lms_mock_ds.dart';
import '../../infrastructure/repositories/lms_repository_impl.dart';

/// DI seam: override this in `bootstrap` to inject a real API-backed repo.
final lmsRepositoryProvider = Provider<LmsRepository>(
  (ref) => const LmsRepositoryImpl(LmsMockDataSource()),
);

/// All courses (immutable seed).
final lmsCoursesProvider = Provider<List<Course>>(
  (ref) => ref.watch(lmsRepositoryProvider).getCourses(),
);

/// Single course lookup by id.
final lmsCourseByIdProvider = Provider.family<Course?, String>((ref, id) {
  for (final c in ref.watch(lmsCoursesProvider)) {
    if (c.id == id) return c;
  }
  return null;
});

/// A `Course? Function(String)` lookup, handy for the aggregate-status logic.
final lmsCourseLookupProvider = Provider<Course? Function(String)>((ref) {
  final courses = ref.watch(lmsCoursesProvider);
  return (id) {
    for (final c in courses) {
      if (c.id == id) return c;
    }
    return null;
  };
});

/// Recent-activity feed.
final lmsActivityProvider = Provider<List<LmsActivity>>(
  (ref) => ref.watch(lmsRepositoryProvider).getActivity(),
);

/// Live learner progress records. Seeded from the repository, then mutated as
/// the current user completes modules in the player (Mark-as-Completed).
class LmsRecordsNotifier extends StateNotifier<List<LearnerRecord>> {
  LmsRecordsNotifier(super.initial);

  /// Raise module [idx] of [courseId] for [rid] to at least [value] (never
  /// lowers existing progress — mirrors the prototype's `lmsSetMod`).
  void setModule(String rid, String courseId, int idx, int value) {
    state = [
      for (final r in state)
        if (r.rid != rid)
          r
        else
          r.copyWith(courses: [
            for (final c in r.courses)
              if (c.courseId != courseId)
                c
              else
                c.copyWith(mods: [
                  for (int i = 0; i < c.mods.length; i++)
                    if (i == idx) (c.mods[i] > value ? c.mods[i] : value) else c.mods[i],
                ]),
          ]),
    ];
  }
}

final lmsRecordsProvider =
    StateNotifierProvider<LmsRecordsNotifier, List<LearnerRecord>>(
  (ref) => LmsRecordsNotifier(ref.watch(lmsRepositoryProvider).getRecords()),
);

/// Single learner record by id (empty record if none).
final lmsRecordByIdProvider = Provider.family<LearnerRecord, String>((ref, rid) {
  for (final r in ref.watch(lmsRecordsProvider)) {
    if (r.rid == rid) return r;
  }
  return LearnerRecord(rid: rid, courses: const []);
});

// ── List UI state ──

/// All Courses search query.
final lmsCourseSearchProvider = StateProvider<String>((ref) => '');

/// All Courses status chip (all | published | draft).
final lmsCourseStatusProvider = StateProvider<String>((ref) => 'all');

/// Learners search query.
final lmsLearnerSearchProvider = StateProvider<String>((ref) => '');

/// Learners role filter chip (all | Manager | Sales rep | …).
final lmsRoleFilterProvider = StateProvider<String>((ref) => 'all');

/// Learners status filter chip (all | notstarted | inprogress | completed | overdue).
final lmsStatusFilterProvider = StateProvider<String>((ref) => 'all');
