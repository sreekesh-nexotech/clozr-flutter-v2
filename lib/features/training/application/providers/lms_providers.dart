import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/learner_record.dart';
import '../../domain/entities/lms_activity.dart';
import '../../domain/repositories/lms_repository.dart';
import '../../infrastructure/data_sources/local/lms_mock_ds.dart';
import '../../infrastructure/data_sources/remote/lms_remote_ds.dart';
import '../../infrastructure/repositories/lms_api_repository.dart';
import '../../infrastructure/repositories/lms_repository_impl.dart';

/// DI seam: mock-backed by default; API-backed when a base URL is configured.
final lmsRepositoryProvider = Provider<LmsRepository>((ref) {
  if (!ApiConfig.apiEnabled) {
    return const LmsRepositoryImpl(LmsMockDataSource());
  }
  return LmsApiRepository(
    LmsRemoteDataSource(ref.watch(apiServiceProvider)),
  );
});

/// Load-then-notify list holder: starts from a synchronous seed (the mock
/// data in mock mode, empty in API mode) and swaps in the repository result
/// when the async load lands. Screens keep reading plain `List<T>` providers
/// with no loading states.
class LmsListNotifier<T> extends StateNotifier<List<T>> {
  LmsListNotifier(super.seed, Future<List<T>> Function() load, {bool refresh = true}) {
    if (refresh) _run(load);
  }

  Future<void> _run(Future<List<T>> Function() load) async {
    try {
      final value = await load();
      if (mounted) state = value;
    } on Object {
      // Keep the seed — mock data in mock mode, empty in API mode.
    }
  }
}

final _lmsCoursesNotifierProvider =
    StateNotifierProvider<LmsListNotifier<Course>, List<Course>>((ref) {
  final repo = ref.watch(lmsRepositoryProvider);
  final api = ApiConfig.apiEnabled;
  return LmsListNotifier<Course>(
    // Mock mode seeds synchronously (identical to the repo payload) so the
    // first frame matches the prototype exactly; no refresh needed.
    api ? const [] : const LmsMockDataSource().fetchCourses(),
    repo.getCourses,
    refresh: api,
  );
});

/// All courses. Same name/exposed type as before the API wiring.
final lmsCoursesProvider = Provider<List<Course>>(
  (ref) => ref.watch(_lmsCoursesNotifierProvider),
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

final _lmsActivityNotifierProvider =
    StateNotifierProvider<LmsListNotifier<LmsActivity>, List<LmsActivity>>((ref) {
  final repo = ref.watch(lmsRepositoryProvider);
  final api = ApiConfig.apiEnabled;
  return LmsListNotifier<LmsActivity>(
    api ? const [] : const LmsMockDataSource().fetchActivity(),
    repo.getActivity,
    refresh: api,
  );
});

/// Recent-activity feed.
final lmsActivityProvider = Provider<List<LmsActivity>>(
  (ref) => ref.watch(_lmsActivityNotifierProvider),
);

/// Live learner progress records. Seeded synchronously (mock data in mock
/// mode, empty in API mode — then refreshed from the repository), and mutated
/// as the current user completes modules in the player (Mark-as-Completed).
class LmsRecordsNotifier extends StateNotifier<List<LearnerRecord>> {
  LmsRecordsNotifier(
    super.initial, {
    LmsRepository? repo,
    Course? Function(String)? courseOf,
    bool refresh = false,
  })  : _repo = repo,
        _courseOf = courseOf {
    if (refresh) _load();
  }

  final LmsRepository? _repo;
  final Course? Function(String)? _courseOf;

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) return;
    try {
      final value = await repo.getRecords();
      if (mounted) state = value;
    } on Object {
      // Keep the seed; the next app launch retries.
    }
  }

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
    // Persist the signed-in user's progress, fire-and-forget (the repository
    // swallows failures; the optimistic update above is already applied).
    if (ApiConfig.apiEnabled && rid == 'me') {
      final course = _courseOf?.call(courseId);
      final moduleId = (course != null && idx >= 0 && idx < course.modules.length)
          ? course.modules[idx].id
          : '';
      _repo?.setModuleProgress(
        courseId: courseId,
        moduleId: moduleId,
        index: idx,
        value: value,
      );
    }
  }
}

final lmsRecordsProvider =
    StateNotifierProvider<LmsRecordsNotifier, List<LearnerRecord>>((ref) {
  final repo = ref.watch(lmsRepositoryProvider);
  final api = ApiConfig.apiEnabled;
  return LmsRecordsNotifier(
    api ? const [] : const LmsMockDataSource().fetchRecords(),
    repo: repo,
    courseOf: (id) => ref.read(lmsCourseLookupProvider)(id),
    refresh: api,
  );
});

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
