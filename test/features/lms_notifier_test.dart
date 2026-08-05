// Error-phase behaviour for the LMS load-then-notify holder: a real failure is
// surfaced (retry), an admin-only 403 degrades to a graceful empty, and a
// mock-mode (refresh:false) holder seeds synchronously and never loads.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/app_error.dart';
import 'package:clozrapp/features/training/application/providers/lms_providers.dart';

/// Drain chained microtasks so the notifier's async `_run` completes.
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('LmsListNotifier load phases', () {
    test('success clears loading and stores the items', () async {
      final n = LmsListNotifier<int>(const [], () async => [1, 2, 3], refresh: true);
      expect(n.state.loading, isTrue); // seeded loading in "API" mode
      await settle();
      expect(n.state.items, [1, 2, 3]);
      expect(n.state.loading, isFalse);
      expect(n.state.error, isNull);
      n.dispose();
    });

    test('a non-403 failure surfaces as an error phase', () async {
      final n = LmsListNotifier<int>(
        const [],
        () async => throw const AppError(type: AppErrorType.server, message: 'boom'),
        refresh: true,
      );
      await settle();
      expect(n.state.loading, isFalse);
      expect(n.state.error, isNotNull);
      expect(n.state.error!.type, AppErrorType.server);
      expect(n.state.items, isEmpty);
      n.dispose();
    });

    test('a 403 degrades to a graceful empty (no error surface)', () async {
      final n = LmsListNotifier<int>(
        const [],
        () async => throw const AppError(type: AppErrorType.forbidden, message: 'nope'),
        refresh: true,
      );
      await settle();
      expect(n.state.loading, isFalse);
      expect(n.state.error, isNull);
      expect(n.state.items, isEmpty);
      n.dispose();
    });

    test('refresh:false seeds synchronously and never calls the loader', () {
      var called = false;
      final n = LmsListNotifier<int>(
        const [7, 8],
        () async {
          called = true;
          return const [];
        },
        refresh: false,
      );
      expect(n.state.items, [7, 8]);
      expect(n.state.loading, isFalse);
      expect(n.state.error, isNull);
      expect(called, isFalse);
      n.dispose();
    });

    test('reload re-runs the loader and recovers from an earlier failure', () async {
      var attempt = 0;
      final n = LmsListNotifier<int>(
        const [],
        () async {
          attempt++;
          if (attempt == 1) throw const AppError(type: AppErrorType.network, message: 'offline');
          return [9];
        },
        refresh: true,
      );
      await settle();
      expect(n.state.error, isNotNull);
      n.reload();
      await settle();
      expect(n.state.error, isNull);
      expect(n.state.items, [9]);
      n.dispose();
    });
  });

  group('lmsCombine', () {
    test('error wins over a still-loading source', () {
      final s = lmsCombine([
        const LmsData<int>(items: [], loading: true),
        const LmsData<int>(items: [], error: AppError(type: AppErrorType.server, message: 'x')),
      ]);
      expect(s.error, isNotNull);
      expect(s.loading, isFalse); // error suppresses the shimmer
    });

    test('loading when any source is loading and none errored', () {
      final s = lmsCombine([
        const LmsData<int>(items: [1]),
        const LmsData<int>(items: [], loading: true),
      ]);
      expect(s.error, isNull);
      expect(s.loading, isTrue);
    });

    test('clean when everything has resolved', () {
      final s = lmsCombine([
        const LmsData<int>(items: [1]),
        const LmsData<int>(items: [2]),
      ]);
      expect(s.error, isNull);
      expect(s.loading, isFalse);
    });
  });
}
