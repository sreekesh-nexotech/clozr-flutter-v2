import 'package:clozrapp/core/network/app_error.dart';
import 'package:clozrapp/features/onboarding/application/tour_event_queue.dart';
import 'package:clozrapp/features/onboarding/domain/sample_tours.dart';
import 'package:clozrapp/features/onboarding/domain/tour.dart';
import 'package:clozrapp/features/onboarding/infrastructure/onboarding_remote_ds.dart';
import 'package:clozrapp/features/onboarding/presentation/tour_anchor.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

Tour _tour({List<TourStep>? steps, String key = 't', bool auto = true}) => Tour(
      key: key,
      version: 3,
      title: 'T',
      autoStart: auto,
      steps: steps ??
          const [
            TourStep(key: 'a', route: '/home', target: 'nav.tabs', title: 'A'),
            TourStep(
                key: 'web',
                route: '/home',
                target: 'nav.sidebar',
                title: 'W',
                desktopOnly: true),
            TourStep(key: 'b', route: '/home', title: 'B'),
          ],
    );

void main() {
  group('step and tour mapping', () {
    test('omitted optional step fields get their defaults', () {
      final s =
          TourStep.fromJson({'key': 'k', 'route': '/leads', 'title': 'T'});
      expect(s.placement, TourPlacement.auto);
      expect(s.advance, TourAdvance.next);
      expect(s.target, '');
      expect(s.isCentered, isTrue);
      expect(s.desktopOnly, isFalse);
    });

    test('wire values map onto the enums', () {
      final s = TourStep.fromJson({
        'key': 'k',
        'route': '/leads',
        'title': 'T',
        'target': 'leads.list',
        'placement': 'top',
        'advance': 'click_target',
        'desktop_only': true,
      });
      expect(s.placement, TourPlacement.top);
      expect(s.advance, TourAdvance.clickTarget);
      expect(s.desktopOnly, isTrue);
      expect(s.isCentered, isFalse);
    });

    test('a tour reads its trigger, prerequisite and steps', () {
      final t = Tour.fromJson({
        'key': 'leads',
        'version': 2,
        'major_version': 1,
        'title': 'Leads',
        'trigger': 'manual',
        'prerequisite_tour': 'welcome',
        'steps': [
          {'key': 'a', 'route': '/leads', 'title': 'A'}
        ],
      });
      expect(t.autoStart, isFalse);
      expect(t.prerequisite, 'welcome');
      expect(t.steps.single.key, 'a');
    });

    test('desktop-only steps never run on the phone', () {
      expect(_tour().mobileSteps.map((s) => s.key), ['a', 'b']);
    });

    test('progress snapshot: rows, preference and suggestion', () {
      final snap = OnboardingRemoteDataSource.parseSnapshot({
        'progress': [
          {
            'tour_key': 'welcome',
            'tour_version': 1,
            'status': 'in_progress',
            'completed_steps': ['a'],
          }
        ],
        'preferences': {'auto_start_enabled': false},
        'next_tour_key': null,
      });
      expect(snap.progress['welcome']!.status, TourStatus.inProgress);
      expect(snap.autoStartEnabled, isFalse);
      expect(snap.nextTourKey, isNull);
    });
  });

  group('progress follows the events (as the server does)', () {
    final t = _tour();
    const fresh = TourProgress(tourKey: 't');

    test('start › step_completed › complete', () {
      var p = applyTourEvent(
          fresh, t, const TourEvent('t', 3, TourEventName.start));
      expect(p.status, TourStatus.inProgress);
      expect(p.currentStepKey, 'a');
      p = applyTourEvent(p, t,
          const TourEvent('t', 3, TourEventName.stepCompleted, stepKey: 'a'));
      expect(p.completedSteps, ['a']);
      expect(p.currentStepKey, 'b');
      p = applyTourEvent(p, t, const TourEvent('t', 3, TourEventName.complete));
      expect(p.status, TourStatus.completed);
      expect(p.isFinished, isTrue);
    });

    test('completed steps stay in tour order', () {
      var p = applyTourEvent(fresh, t,
          const TourEvent('t', 3, TourEventName.stepCompleted, stepKey: 'b'));
      p = applyTourEvent(p, t,
          const TourEvent('t', 3, TourEventName.stepCompleted, stepKey: 'a'));
      expect(p.completedSteps, ['a', 'b']);
    });

    test('restart clears progress and counts a replay', () {
      final done = fresh
          .copyWith(status: TourStatus.completed, completedSteps: ['a', 'b']);
      final p = applyTourEvent(
          done, t, const TourEvent('t', 3, TourEventName.restart));
      expect(p.status, TourStatus.inProgress);
      expect(p.completedSteps, isEmpty);
      expect(p.replayCount, 1);
    });

    test('resume starts at the first step not yet done', () {
      final p =
          fresh.copyWith(status: TourStatus.inProgress, completedSteps: ['a']);
      expect(resumeIndex(t, p), 1);
      expect(resumeIndex(t, null), 0);
    });
  });

  group('which tour to offer', () {
    final server = _tour(key: 'server');
    final local = Tour(
        key: 'sample',
        version: 1,
        title: 'S',
        autoStart: true,
        localOnly: true,
        steps: const [TourStep(key: 'x', route: '/home', title: 'X')]);

    test("the server's next_tour_key wins", () {
      expect(
          tourToOffer(
                  catalog: [server, local],
                  progress: const {},
                  nextTourKey: 'server',
                  autoStartEnabled: true)
              ?.key,
          'server');
    });

    test('nothing when auto-start is off', () {
      expect(
          tourToOffer(
              catalog: [server, local],
              progress: const {},
              nextTourKey: 'server',
              autoStartEnabled: false),
          isNull);
    });

    test('a server tour is not offered without the server suggesting it', () {
      expect(
          tourToOffer(
              catalog: [server],
              progress: const {},
              nextTourKey: null,
              autoStartEnabled: true),
          isNull);
    });

    test('a local sample tour is offered once, until it is seen', () {
      expect(
          tourToOffer(
                  catalog: [local],
                  progress: const {},
                  nextTourKey: null,
                  autoStartEnabled: true)
              ?.key,
          'sample');
      expect(
          tourToOffer(catalog: [
            local
          ], progress: const {
            'sample':
                TourProgress(tourKey: 'sample', status: TourStatus.dismissed)
          }, nextTourKey: null, autoStartEnabled: true),
          isNull);
    });

    test('a prerequisite blocks until it is completed', () {
      final leads = sampleTours.firstWhere((t) => t.key == 'leads');
      expect(prerequisiteMissing(leads, const {}), isTrue);
      expect(
          prerequisiteMissing(leads, const {
            'welcome':
                TourProgress(tourKey: 'welcome', status: TourStatus.completed)
          }),
          isFalse);
    });
  });

  group('routes', () {
    test('path only, query ignored', () {
      expect(routeMatches('/leads', '/leads?view=kanban'), isTrue);
      expect(routeMatches('/leads', '/leads/detail'), isFalse);
    });
    test(':id routes match by prefix', () {
      expect(routeMatches('/leads/:id', '/leads/123'), isTrue);
    });
  });

  group('anchors', () {
    test('every built-in tour step points at an id the app defines', () {
      for (final t in sampleTours) {
        for (final s in t.steps) {
          if (s.isCentered) continue;
          expect(TourAnchors.isKnown(s.target), isTrue,
              reason: '${t.key}.${s.key} → ${s.target}');
        }
      }
    });
  });

  group('event queue', () {
    const e1 = TourEvent('t', 1, TourEventName.start);
    const e2 = TourEvent('t', 1, TourEventName.stepCompleted, stepKey: 'a');
    const other = TourEvent('u', 1, TourEventName.start);

    test('waits, then sends one batch per tour in order', () {
      fakeAsync((async) {
        final sent = <String>[];
        final q = TourEventQueue(send: (k, v, ev) async {
          sent.add('$k:${ev.map((e) => e.name.wire).join(',')}');
        });
        q.add(e1);
        q.add(e2);
        q.add(other);
        async.elapse(const Duration(milliseconds: 100));
        expect(sent, isEmpty);
        async.elapse(const Duration(milliseconds: 400));
        expect(sent, ['t:start,step_completed', 'u:start']);
        expect(q.pending, isEmpty);
      });
    });

    test('a network failure keeps the batch and retries', () {
      fakeAsync((async) {
        var calls = 0;
        final q = TourEventQueue(send: (k, v, ev) async {
          calls++;
          if (calls == 1) {
            throw const AppError(type: AppErrorType.network, message: 'x');
          }
        });
        q.add(e1);
        async.elapse(const Duration(milliseconds: 500));
        expect(q.pending, hasLength(1));
        async.elapse(const Duration(seconds: 3));
        expect(calls, 2);
        expect(q.pending, isEmpty);
      });
    });

    test('a 4xx is dropped so it cannot block what follows', () {
      fakeAsync((async) {
        final sent = <String>[];
        final q = TourEventQueue(send: (k, v, ev) async {
          if (k == 't') {
            throw const AppError(
                type: AppErrorType.validation, message: 'x', statusCode: 404);
          }
          sent.add(k);
        });
        q.add(e1);
        q.add(other);
        async.elapse(const Duration(milliseconds: 500));
        expect(sent, ['u']);
        expect(q.pending, isEmpty);
      });
    });

    test('unsent events are saved and picked up on the next start', () {
      fakeAsync((async) {
        List<TourEvent> saved = [];
        final q = TourEventQueue(
            send: (k, v, ev) async => throw const AppError(
                type: AppErrorType.server, message: 'x', statusCode: 503),
            save: (l) => saved = l);
        q.add(e1);
        q.add(e2);
        expect(saved, hasLength(2));
        q.dispose();

        final sent = <int>[];
        TourEventQueue(
            send: (k, v, ev) async => sent.add(ev.length), load: () => saved);
        async.elapse(Duration.zero);
        expect(sent, [2]);
      });
    });

    test('at most 50 events per request', () {
      fakeAsync((async) {
        final sizes = <int>[];
        final q =
            TourEventQueue(send: (k, v, ev) async => sizes.add(ev.length));
        for (var i = 0; i < 120; i++) {
          q.add(TourEvent('t', 1, TourEventName.stepCompleted, stepKey: '$i'));
        }
        async.elapse(const Duration(milliseconds: 500));
        expect(sizes, [50, 50, 20]);
      });
    });
  });
}
