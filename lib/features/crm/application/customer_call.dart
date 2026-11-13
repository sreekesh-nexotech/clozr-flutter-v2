import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shell/application/providers/shell_providers.dart';
import 'providers/lead_call_providers.dart' show normaliseCallNumber;

/// Rings a customer from the list card, the detail menu or the sticky call
/// bar — the webapp's call icon opens the device dialler with the customer's
/// number (customers have no Exotel click-to-call route). Reports what
/// happened as one toast.
Future<void> dialCustomer(WidgetRef ref,
    {required String phone,
    required String name,
    String what = 'customer'}) async {
  final toast = ref.read(toastProvider.notifier);
  final number = normaliseCallNumber(phone);
  final first = name.split(' ').first;
  if (number.isEmpty) {
    toast.show('This $what has no phone number.');
    return;
  }
  final ok = await launchUrl(Uri(scheme: 'tel', path: number));
  toast.show(ok ? 'Calling $first…' : 'Could not open the dialler.');
}
