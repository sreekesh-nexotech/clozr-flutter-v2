import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/app_error.dart';
import 'app_refresh.dart';
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
    this.onRefresh,
    this.refreshDisplacement,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback onRetry;
  final Widget Function()? loading;
  final Widget Function(AppError error, VoidCallback retry)? error;

  /// Supply to give the loaded list pull-to-refresh. Should invalidate whatever
  /// the screen reads and await the refetch — see [settle].
  ///
  /// Only the data branch is wrapped: the error branch already offers Retry, and
  /// the skeleton has nothing to pull. The empty state is covered, because
  /// screens render theirs inside [data].
  final Future<void> Function()? onRefresh;

  /// Passed through to [AppRefresh.displacement] for screens with a taller
  /// sticky header than the list default.
  final double? refreshDisplacement;

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
      data: (value) {
        final built = data(value);
        final refresh = onRefresh;
        if (refresh == null) return built;
        return AppRefresh(
          onRefresh: refresh,
          displacement: refreshDisplacement,
          child: built,
        );
      },
    );
  }
}
