import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_endpoints.dart';
import '../network/network_providers.dart';

/// This device's FCM token once Firebase has handed one out; null while push
/// is off (no Firebase config, permission refused, no network yet). Set by
/// `PushNotificationService`; read at sign-out to deactivate the device.
///
/// Lives apart from the service so the auth layer can import it without
/// pulling Firebase into its own import graph.
final pushTokenProvider = StateProvider<String?>((ref) => null);

/// Deactivates this device on the server (`DELETE /crm/devices/<id>/`).
/// Called **before** the session's tokens are dropped, since the call needs
/// them. Best effort: a failure leaves a stale token the backend prunes on its
/// first failed send.
Future<void> unregisterPushDevice(Ref ref) async {
  final token = ref.read(pushTokenProvider);
  if (token == null) return;
  try {
    final api = ref.read(apiServiceProvider);
    final body = await api.get(ApiEndpoints.devices,
        query: {'page_size': 50}, quiet: true);
    final rows = body is Map && body['results'] is List
        ? body['results'] as List
        : body is List
            ? body
            : const [];
    for (final r in rows) {
      if (r is Map && r['device_token'] == token) {
        await api.delete(ApiEndpoints.device('${r['user_device_id']}'));
        break;
      }
    }
  } on Object {
    // Nothing to do — see above.
  }
}
