import '../../../../core/network/app_error.dart';

/// Coerces an arbitrary async error into an [AppError] so the detail screens can
/// hand it to `ErrorState.forError`. CRM repositories already throw [AppError];
/// this only guards the rare case where some other error type propagates.
AppError crmAppError(Object error) => error is AppError
    ? error
    : const AppError(
        type: AppErrorType.unknown,
        message: 'Something went wrong. Please try again.',
      );
