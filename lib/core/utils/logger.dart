import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Severity levels for [AppLogger].
enum LogLevel {
  /// Verbose detail, useful only while debugging.
  debug,

  /// Normal lifecycle events.
  info,

  /// Recoverable problems worth noticing.
  warning,

  /// Failures that broke something for the user.
  error,
}

/// Display helpers for [LogLevel].
extension LogLevelX on LogLevel {
  /// Short uppercase tag used in log output.
  String get displayName => switch (this) {
        LogLevel.debug => 'DEBUG',
        LogLevel.info => 'INFO',
        LogLevel.warning => 'WARN',
        LogLevel.error => 'ERROR',
      };

  /// `dart:developer` severity, roughly matching `package:logging`.
  int get severity => switch (this) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warning => 900,
        LogLevel.error => 1000,
      };
}

/// Unified logging for the app.
///
/// Uses `dart:developer` rather than `print` so the `avoid_print` lint stays
/// satisfied and output is structured in DevTools.
///
/// Everything below [LogLevel.error] is suppressed in release builds, so debug
/// chatter never reaches a shipped app.
///
/// NEVER pass a token, password, OTP or full auth header to these methods —
/// QA.md security audit item 13.
class AppLogger {
  const AppLogger._();

  /// Default tag when a call site does not supply one.
  static const String defaultName = 'clozr';

  /// Logs verbose detail. Debug builds only.
  static void debug(String message, {String name = defaultName}) =>
      _log(LogLevel.debug, message, name: name);

  /// Logs a normal lifecycle event. Debug builds only.
  static void info(String message, {String name = defaultName}) =>
      _log(LogLevel.info, message, name: name);

  /// Logs a recoverable problem. Debug builds only.
  static void warning(String message, {String name = defaultName}) =>
      _log(LogLevel.warning, message, name: name);

  /// Logs a failure. Emitted in release builds too.
  ///
  /// Pass the originating [error] and [stackTrace] so crash reporting can
  /// attach them.
  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String name = defaultName,
  }) =>
      _log(
        LogLevel.error,
        message,
        name: name,
        error: error,
        stackTrace: stackTrace,
      );

  static void _log(
    LogLevel level,
    String message, {
    required String name,
    Object? error,
    StackTrace? stackTrace,
  }) {
    // Only errors survive into release builds.
    if (!kDebugMode && level != LogLevel.error) return;

    developer.log(
      '[${level.displayName}] $message',
      name: name,
      level: level.severity,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
