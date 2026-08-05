import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/app_error.dart';
import 'error_state.dart';
import 'list_skeleton.dart';

/// Standardizes the loading / error / data branching for an [AsyncValue] so
/// every screen wires the three states identically. The [data] builder owns
/// the empty case (render an [EmptyState] inside it when the list is empty).
///
/// Loading shows a shimmer [ListSkeleton]; error shows an [ErrorState] with a
/// Retry that calls [onRetry] (typically `ref.invalidate(theProvider)`).
class AsyncStateView<T> extends StatelessWidget {
  const AsyncStateView({
    super.key,
    required this.value,
    required this.data,
    required this.onRetry,
    this.loading,
    this.error,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback onRetry;
  final Widget Function()? loading;
  final Widget Function(AppError error, VoidCallback retry)? error;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => loading?.call() ?? const ListSkeleton(),
      error: (e, _) {
        final appError = e is AppError
            ? e
            : const AppError(
                type: AppErrorType.unknown,
                message: 'Something went wrong. Please try again.',
              );
        return error?.call(appError, onRetry) ??
            ErrorState.forError(appError, onRetry: onRetry);
      },
      data: data,
    );
  }
}
