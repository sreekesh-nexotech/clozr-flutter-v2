import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/token_storage.dart';
import 'api_service.dart';

/// App-wide token store. Overridable in tests with an in-memory fake.
final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

/// The single network gateway every remote data source receives via DI.
final apiServiceProvider = Provider<ApiService>(
  (ref) => ApiService(tokens: ref.watch(tokenStorageProvider)),
);
