import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_config.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/network_providers.dart';
import '../../../core/network/paginated.dart';
import '../../shell/application/providers/shell_providers.dart';

/// Shown wherever a WhatsApp action is tapped but the org has no WhatsApp
/// number connected.
const kWhatsappNotIntegrated =
    'Whatsapp is not integrated in this organization, please integrate to make use of this functionality';

/// Whether the org has a connected WhatsApp number — the webapp's
/// `WhatsAppConnectedGuard` rule: an account that is active and holds an
/// access token. `null` when the answer is unknown (no permission to read the
/// accounts, offline): the caller then lets the action through rather than
/// blocking a connected org on a failed lookup.
final whatsappConnectedProvider =
    FutureProvider.autoDispose<bool?>((ref) async {
  if (!ApiConfig.apiEnabled) return true;
  try {
    final body = await ref.read(apiServiceProvider).get(
        ApiEndpoints.whatsappAccounts,
        query: {'page_size': 50},
        quiet: true);
    final rows =
        Paginated.fromAny<Map<String, dynamic>>(body, (m) => m).results;
    return rows
        .any((a) => a['is_active'] == true && a['has_access_token'] == true);
  } catch (_) {
    return null;
  }
});

/// True when a WhatsApp action may go ahead; otherwise toasts
/// [kWhatsappNotIntegrated] and returns false.
Future<bool> ensureWhatsappConnected(WidgetRef ref) async {
  bool? connected;
  try {
    connected = await ref
        .read(whatsappConnectedProvider.future)
        .timeout(const Duration(seconds: 4));
  } catch (_) {
    connected = null;
  }
  if (connected == false) {
    ref.read(toastProvider.notifier).showError(kWhatsappNotIntegrated);
    ref.invalidate(whatsappConnectedProvider);
    return false;
  }
  return true;
}
