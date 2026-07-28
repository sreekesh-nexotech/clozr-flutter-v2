import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/env.dart';
import '../../core/utils/logger.dart';

/// Destination for crash and non-fatal error reports.
///
/// Implement once per backend (Crashlytics, Sentry, …) and install it with
/// [CrashReporting.install].
abstract interface class CrashReporter {
  /// Records an error and its [stackTrace].
  ///
  /// [isFatal] marks a crash as opposed to a handled error.
  Future<void> recordErrorAsync(
    Object error,
    StackTrace? stackTrace, {
    bool isFatal,
  });

  /// Attaches a breadcrumb to subsequent reports.
  Future<void> logAsync(String message);

  /// Associates reports with a user, or clears it on logout.
  ///
  /// Pass the opaque user id only — never a name, email or phone number.
  Future<void> setUserIdAsync(String? userId);
}

/// A [CrashReporter] that logs locally and sends nothing.
class NoopCrashReporter implements CrashReporter {
  /// Creates the no-op reporter.
  const NoopCrashReporter();

  @override
  Future<void> recordErrorAsync(
    Object error,
    StackTrace? stackTrace, {
    bool isFatal = false,
  }) async {
    AppLogger.error(
      'crash report (not sent, fatal: $isFatal)',
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  Future<void> logAsync(String message) async {
    AppLogger.debug('crash breadcrumb (not sent): $message');
  }

  @override
  Future<void> setUserIdAsync(String? userId) async {
    AppLogger.debug('crash reporter user id (not sent): $userId');
  }
}

/// App-wide crash reporting facade and global error hooks.
///
/// NOT WIRED YET: `bootstrap()` does not call [installErrorHooks], so error
/// handling is unchanged. Wire it up alongside the real reporter.
///
/// Reports must never contain a token, password or OTP
/// (QA.md security audit item 13).
// TODO(clozr): call installErrorHooks() from bootstrap with a real reporter 2026-07-28
class CrashReporting {
  const CrashReporting._();

  static CrashReporter _reporter = const NoopCrashReporter();

  /// Replaces the active reporter. Call once during bootstrap.
  static void install(CrashReporter reporter) => _reporter = reporter;

  /// Routes Flutter framework and uncaught async errors to the reporter.
  ///
  /// Call after [install] and before `runApp`. Honours
  /// `Env.enableCrashReporting`, falling back to enabled when no environment
  /// has been installed yet.
  static void installErrorHooks() {
    final isEnabled =
        !Env.isInitialised || Env.current.enableCrashReporting;
    if (!isEnabled) return;

    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      previousOnError?.call(details);
      unawaited(
        recordAsync(
          details.exception,
          details.stack,
          isFatal: true,
        ),
      );
    };

    PlatformDispatcher.instance.onError = (error, stackTrace) {
      unawaited(recordAsync(error, stackTrace, isFatal: true));
      return true;
    };
  }

  /// Records a handled error. Safe to call from anywhere.
  static Future<void> recordAsync(
    Object error,
    StackTrace? stackTrace, {
    bool isFatal = false,
  }) async {
    try {
      await _reporter.recordErrorAsync(error, stackTrace, isFatal: isFatal);
    } catch (reportingError) {
      // Never let the reporter's own failure surface to the user.
      AppLogger.error('Crash reporting failed', error: reportingError);
    }
  }

  /// Adds a breadcrumb to subsequent reports.
  static Future<void> breadcrumbAsync(String message) async {
    try {
      await _reporter.logAsync(message);
    } catch (reportingError) {
      AppLogger.error('Crash breadcrumb failed', error: reportingError);
    }
  }

  /// Associates reports with [userId], or clears it on logout.
  static Future<void> setUserIdAsync(String? userId) async {
    try {
      await _reporter.setUserIdAsync(userId);
    } catch (reportingError) {
      AppLogger.error('Crash reporter user id failed', error: reportingError);
    }
  }
}
