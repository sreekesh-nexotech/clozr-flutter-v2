import 'package:equatable/equatable.dart';

/// Whether the org's Exotel telephony is usable — `GET /crm/exotel/status/`.
///
/// Three states, not two. [known] is false when the status could not be read at
/// all: that endpoint needs a settings permission an ordinary sales user may
/// not have, and "I am not allowed to see the setting" is very different from
/// "the org has no Exotel". Collapsing the two would route exactly the people
/// who make calls away from click-to-call.
class ExotelStatus extends Equatable {
  const ExotelStatus({required this.enabled, required this.configured})
      : known = true;

  /// The status could not be read (403 for a non-admin, or the call failed).
  const ExotelStatus.unknown()
      : enabled = false,
        configured = false,
        known = false;

  /// Telephony is switched off for the org.
  const ExotelStatus.off()
      : enabled = false,
        configured = false,
        known = true;

  final bool enabled;

  /// All five credentials are stored. `enabled` without this still fails at
  /// dial time with "not fully configured", so both must hold.
  final bool configured;

  final bool known;

  /// Safe to route a call through Exotel.
  bool get usable => known && enabled && configured;

  @override
  List<Object?> get props => [enabled, configured, known];
}
