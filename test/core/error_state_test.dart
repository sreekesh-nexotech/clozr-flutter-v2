import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/app_error.dart';
import 'package:clozrapp/core/widgets/error_state.dart';

void main() {
  group('ErrorState.forError', () {
    test('maps each error type to a friendly title and keeps the message', () {
      final network = ErrorState.forError(const AppError(
        type: AppErrorType.network,
        message: 'No internet connection.',
      ));
      expect(network.title, "You're offline");
      expect(network.body, 'No internet connection.');

      expect(
        ErrorState.forError(const AppError(
          type: AppErrorType.forbidden,
          message: "You don't have permission.",
        )).title,
        'No access',
      );
      expect(
        ErrorState.forError(const AppError(
          type: AppErrorType.server,
          message: 'Server error.',
        )).title,
        'Server error',
      );
      expect(
        ErrorState.forError(const AppError(
          type: AppErrorType.unknown,
          message: 'Whoops.',
        )).title,
        'Something went wrong',
      );
    });

    test('carries the retry callback through', () {
      var retried = false;
      final s = ErrorState.forError(
        const AppError(type: AppErrorType.timeout, message: 'Slow.'),
        onRetry: () => retried = true,
      );
      s.onRetry?.call();
      expect(retried, isTrue);
    });
  });
}
