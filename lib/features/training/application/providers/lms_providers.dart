import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../domain/entities/course.dart';
import '../../domain/entities/learner_record.dart';
import '../../domain/entities/lms_activity.dart';
import '../../domain/entities/lms_stats.dart';
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

/// A load-then-notify list plus its load phase. The screens read the derived
/// `List<T>` providers for the body and the controller state for
/// loading/error branching.
class LmsData<T> {
  const LmsData({required this.items, this.loading = false, this.error});

  final List<T> items;
  final bool loading;
  final AppError? error;

  LmsData<T> copyWith({List<T>? items, bool? loading, AppError? error, bool clearError = false}) =>
      LmsData<T>(
        items: items ?? this.items,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Aggregate load phase across several [LmsData] sources: an error wins over a
/// still-loading source, so a hard failure shows the retry rather than a
/// forever-shimmer.
class LmsStatus {
  const LmsStatus({this.loading = false, this.error});
  final bool loading;
  final AppError? error;
}

LmsStatus lmsCombine(List<LmsData> parts) {
  AppError? error;
  var loading = false;
  for (final p in parts) {
    error ??= p.error;
    if (p.loading) loading = true;
  }
  return LmsStatus(loading: error == null && loading, error: error);
}

/// Retry every core LMS load (courses + learner records + activity). Wired to
/// the ErrorState Retry CTAs; reloading a source that has already succeeded or
/// is admin-gated is harmless.
void reloadLms(WidgetRef ref) {
  ref.invalidate(lmsStatsProvider);
  ref.read(lmsCoursesControllerProvider.notifier).reload();
  ref.read(lmsRecordsControllerProvider.notifier).reload();
  ref.read(lmsActivityControllerProvider.notifier).reload();
}

/// Load-then-notify list holder: starts from a synchronous seed (the mock
/// data in mock mode, empty + loading in API mode) and swaps in the repository
/// result when the async load lands. A real failure is stored so the screen
/// can offer a retry; an admin-only 403 that reaches here degrades to a
/// graceful empty (the repository already converts the known admin-gated
/// endpoints, so this is the belt-and-braces case).
class LmsListNotifier<T> extends StateNotifier<LmsData<T>> {
  LmsListNotifier(List<T> seed, this._load, {bool refresh = true})
      : super(LmsData<T>(items: seed, loading: refresh)) {
    if (refresh) _run();
  }

  final Future<List<T>> Function() _load;

  /// Retry the load (used by the ErrorState Retry CTA).
  Future<void> reload() => _run();

  Future<void> _run() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final value = await _load();
      if (mounted) state = LmsData<T>(items: value);
    } on AppError catch (e) {
      if (!mounted) return;
      state = e.type == AppErrorType.forbidden
          ? state.copyWith(loading: false, clearError: true) // no-access → graceful empty
          : state.copyWith(loading: false, error: e);
    } on Object catch (e) {
      if (mounted) {
        state = state.copyWith(
          loading: false,
          error: AppError(type: AppErrorType.unknown, message: 'Something went wrong. Please try again.', cause: e),
        );
      }
    }
  }
}

final lmsCoursesControllerProvider =
    StateNotifierProvider<LmsListNotifier<Course>, LmsData<Course>>((ref) {
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
  (ref) => ref.watch(lmsCoursesControllerProvider).items,
);

/// The Overview's headline figures (`GET /lms/dashboard/stats/`).
///
/// Null in mock mode and for a role the dashboard `403`s, which the screen
/// reads as "count what is loaded instead" — the behaviour it had before this
/// endpoint was wired.
final lmsStatsProvider = FutureProvider<LmsStats?>(
  (ref) => ref.watch(lmsRepositoryProvider).getStats(),
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

final lmsActivityControllerProvider =
    StateNotifierProvider<LmsListNotifier<LmsActivity>, LmsData<LmsActivity>>((ref) {
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
  (ref) => ref.watch(lmsActivityControllerProvider).items,
);

/// Live learner progress records. Seeded synchronously (mock data in mock
/// mode, empty + loading in API mode — then refreshed from the repository),
/// and mutated as the current user completes modules in the player
/// (Mark-as-Completed). A real fetch failure is stored for a retry; the
/// admin-only learner list already degrades to just 'me' at the repository.
class LmsRecordsNotifier extends StateNotifier<LmsData<LearnerRecord>> {
  LmsRecordsNotifier(
    List<LearnerRecord> initial, {
    LmsRepository? repo,
    Course? Function(String)? courseOf,
    bool refresh = false,
  })  : _repo = repo,
        _courseOf = courseOf,
        super(LmsData<LearnerRecord>(items: initial, loading: refresh)) {
    if (refresh) _load();
  }

  final LmsRepository? _repo;
  final Course? Function(String)? _courseOf;

  /// Retry the records load (used by the ErrorState Retry CTA).
  Future<void> reload() => _load();

  Future<void> _load() async {
    final repo = _repo;
    if (repo == null) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final value = await repo.getRecords();
      if (mounted) state = LmsData<LearnerRecord>(items: value);
    } on AppError catch (e) {
      if (!mounted) return;
      state = e.type == AppErrorType.forbidden
          ? state.copyWith(loading: false, clearError: true) // no-access → graceful empty
          : state.copyWith(loading: false, error: e);
    } on Object catch (e) {
      if (mounted) {
        state = state.copyWith(
          loading: false,
          error: AppError(type: AppErrorType.unknown, message: 'Something went wrong. Please try again.', cause: e),
        );
      }
    }
  }

  /// Raise module [idx] of [courseId] for [rid] to at least [value] (never
  /// lowers existing progress — mirrors the prototype's `lmsSetMod`).
  void setModule(String rid, String courseId, int idx, int value) {
    state = state.copyWith(items: [
      for (final r in state.items)
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
    ]);
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

final lmsRecordsControllerProvider =
    StateNotifierProvider<LmsRecordsNotifier, LmsData<LearnerRecord>>((ref) {
  final repo = ref.watch(lmsRepositoryProvider);
  final api = ApiConfig.apiEnabled;
  return LmsRecordsNotifier(
    api ? const [] : const LmsMockDataSource().fetchRecords(),
    repo: repo,
    courseOf: (id) => ref.read(lmsCourseLookupProvider)(id),
    refresh: api,
  );
});

/// Live learner progress records. Same name/exposed type as before the API
/// wiring.
final lmsRecordsProvider = Provider<List<LearnerRecord>>(
  (ref) => ref.watch(lmsRecordsControllerProvider).items,
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
