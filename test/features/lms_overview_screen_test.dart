import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/app_error.dart';
import 'package:clozrapp/features/training/application/providers/lms_providers.dart';
import 'package:clozrapp/features/training/domain/entities/course.dart';
import 'package:clozrapp/features/training/domain/entities/learner_record.dart';
import 'package:clozrapp/features/training/domain/entities/lms_activity.dart';
import 'package:clozrapp/features/training/domain/entities/lms_stats.dart';
import 'package:clozrapp/features/training/presentation/screens/lms_overview_screen.dart';

Course _c(String id, String title,
        {String status = 'published', List<String> roles = const []}) =>
    Course(
      id: id,
      title: title,
      sub: '',
      status: status,
      sequential: false,
      mandatory: false,
      role: '',
      deadline: '',
      deadlineISO: '',
      desc: '',
      tint: Colors.blue,
      accent: Colors.blue,
      icon: Icons.school,
      modules: const [],
      roleNames: roles,
    );

/// Pumps the Training Overview with the given sources.
Future<void> _pump(
  WidgetTester t, {
  List<Course> courses = const [],
  List<LearnerRecord> records = const [],
  List<LmsActivity> activity = const [],
  Future<LmsStats?> Function()? stats,
  AppError? courseError,
}) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.6;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      lmsCoursesControllerProvider.overrideWith((ref) {
        final n = LmsListNotifier<Course>(courses, () async {
          if (courseError != null) throw courseError;
          return courses;
        }, refresh: false);
        if (courseError != null) {
          return _Fixed<Course>(LmsData(items: const [], error: courseError));
        }
        return n;
      }),
      lmsRecordsControllerProvider
          .overrideWith((ref) => LmsRecordsNotifier(records)),
      lmsActivityControllerProvider.overrideWith((ref) =>
          LmsListNotifier<LmsActivity>(activity, () async => activity,
              refresh: false)),
      lmsStatsProvider.overrideWith((ref) => (stats ?? () async => null)()),
    ],
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => const MaterialApp(home: Scaffold(body: LmsOverviewScreen())),
    ),
  ));
  await t.pumpAndSettle();
  t.takeException(); // Ahem-font overflow, see main()
}

class _Fixed<T> extends LmsListNotifier<T> {
  _Fixed(LmsData<T> s) : super(const [], () async => const [], refresh: false) {
    state = s;
  }
  @override
  Future<void> reload() async {}
}

void main() {
  // The test font (Ahem) is far wider than the app's, so rows overflow here
  // that do not on a device; layout overflow is not what these tests check.
  final prior = FlutterError.onError;
  setUp(() {
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) return;
      prior?.call(d);
    };
  });
  tearDown(() => FlutterError.onError = prior);
  testWidgets('TDB-005 stats endpoint failing falls back to local figures',
      (t) async {
    await _pump(t,
        courses: [_c('a', 'Alpha'), _c('b', 'Beta', status: 'draft')],
        records: [
          const LearnerRecord(rid: 'me', courses: []),
          const LearnerRecord(
              rid: 'u1', courses: [CourseProgress(courseId: 'a', mods: [100])]),
          const LearnerRecord(
              rid: 'u2', courses: [CourseProgress(courseId: 'a', mods: [50])]),
        ],
        stats: () async => throw const AppError(
            type: AppErrorType.server, message: 'boom', statusCode: 500));
    // 2 courses and 2 learners (excluding "me") — no zero-padding (UI/UX #50).
    expect(find.text('2'), findsNWidgets(2));
    expect(find.text('1 published · 1 draft'), findsOneWidget);
    expect(find.text('75%'), findsWidgets); // average of 100 and 50 (tile)
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('TDB-006 role filter lists roles, filters and drops stale ones',
      (t) async {
    await _pump(t, courses: [
      _c('a', 'Sales', roles: ['CRM User']),
      _c('b', 'Lead', roles: ['Executive Leadership']),
    ]);
    expect(find.text('All roles'), findsOneWidget);
    await t.tap(find.text('All roles'));
    await t.pumpAndSettle();
    t.takeException();
    expect(find.text('CRM User'), findsWidgets);
    await t.tap(find.text('Executive Leadership').last);
    await t.pumpAndSettle();
    t.takeException();
    expect(find.text('Lead'), findsOneWidget);
    expect(find.text('Sales'), findsNothing);
  });

  testWidgets('TDB-008 no courses: empty message and zero tiles', (t) async {
    await _pump(t, stats: () async => const LmsStats());
    expect(find.text('No courses yet'), findsOneWidget);
    expect(find.text('0'), findsWidgets); // not zero-padded (UI/UX #50)
    expect(find.text('0 published · 0 draft'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('TDB-010 empty activity feed shows an empty state', (t) async {
    await _pump(t, courses: [_c('a', 'Alpha')]);
    await t.scrollUntilVisible(find.text('Recent Activity'), 300);
    expect(find.text('No recent activity'), findsOneWidget);
  });

  testWidgets('TDB-010 activity rows read "<who> <what>" with the time',
      (t) async {
    await _pump(t, courses: [
      _c('a', 'Alpha')
    ], activity: const [
      LmsActivity(
          dot: Colors.purple, who: 'Sufail', what: 'was enrolled in X', time: '2m ago'),
    ]);
    await t.scrollUntilVisible(find.text('2m ago'), 300);
    expect(find.text('No recent activity'), findsNothing);
    expect(find.textContaining('was enrolled in X'), findsOneWidget);
  });

  testWidgets('TDB-012 a failed load shows the error state with Retry',
      (t) async {
    await _pump(t,
        courseError: const AppError(
            type: AppErrorType.network, message: 'No internet connection'));
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Overview'), findsNothing);
  });
}
