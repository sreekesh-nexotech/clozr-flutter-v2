import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/network/network_providers.dart';
import '../../../auth/application/providers/auth_providers.dart';
import '../../domain/entities/exotel_status.dart';
import '../../domain/repositories/call_logs_repository.dart';
import '../../infrastructure/data_sources/remote/exotel_remote_ds.dart';
import 'call_logs_providers.dart';

/// How a call ended up being placed, and whether it was recorded.
enum LeadCallResult {
  /// Exotel accepted it — the user's own phone rings next, then bridges.
  ringingViaExotel,

  /// Handed to the device dialler and logged against the lead.
  dialledAndLogged,

  /// Dialled, but not logged: the API requires the caller's own number as
  /// `from_number` and this account has none on its profile.
  dialledNotLogged,

  /// Dialled, but the log was rejected.
  dialledLogFailed,

  /// The lead has no phone number to call.
  noNumber,

  /// The device would not open a dialler.
  diallerUnavailable,
}

/// The outcome plus anything the user needs told.
class LeadCallOutcome {
  const LeadCallOutcome(this.result, {this.message});

  final LeadCallResult result;

  /// A user-safe note — an API error, or a warning that Exotel was expected to
  /// take the call and did not.
  final String? message;
}

/// Hands a number to the device dialler. Injected so the routing can be tested
/// without a platform channel.
typedef Dialler = Future<bool> Function(Uri uri);

/// Decides how the Call button places a call, and records it.
///
/// Two routes, because the backend has no single "call this lead" endpoint:
///
/// * **Exotel click-to-call** when the org has telephony connected. The server
///   rings the agent, bridges to the lead, and writes the call log itself.
/// * **Device dialler** otherwise, with the app posting the call log after.
///
/// The routing deliberately tries Exotel when the status is merely *unknown*.
/// `/crm/exotel/status/` is settings-gated and a sales user may get a 403 on
/// it, while placing a call is open to any authenticated user — so trusting an
/// unreadable status would route exactly the wrong people to the dialler. A
/// refusal costs one round trip and places no call.
class LeadCallService {
  const LeadCallService({
    required ExotelRemoteDataSource? exotel,
    required CallLogsRepository callLogs,
    required Dialler dialler,
    required String myNumber,
  })  : _exotel = exotel,
        _callLogs = callLogs,
        _dial = dialler,
        _myNumber = myNumber;

  final ExotelRemoteDataSource? _exotel;
  final CallLogsRepository _callLogs;
  final Dialler _dial;

  /// The signed-in user's own number (`profile.phone`) — the `from_number` a
  /// manual call log requires. Empty on an account with no profile phone.
  final String _myNumber;

  Future<LeadCallOutcome> call({
    required String leadId,
    required String toNumber,
    required ExotelStatus status,
  }) async {
    final to = toNumber.trim();
    if (to.isEmpty) return const LeadCallOutcome(LeadCallResult.noNumber);

    String? exotelNote;
    final exotel = _exotel;
    if (exotel != null && (status.usable || !status.known)) {
      try {
        await exotel.placeCall(leadId: leadId, toNumber: to);
        return const LeadCallOutcome(LeadCallResult.ringingViaExotel);
      } on Object catch (e) {
        // Refused — nothing was dialled, so fall through. Only surface it when
        // Exotel was supposed to work; for an org that does not use it, a
        // refusal is simply the normal path and not worth a warning.
        exotelNote = status.usable
            ? (e is AppError ? e.message : 'Exotel could not place the call.')
            : null;
      }
    }

    if (!await _dial(Uri(scheme: 'tel', path: to))) {
      return LeadCallOutcome(LeadCallResult.diallerUnavailable, message: exotelNote);
    }

    if (_myNumber.trim().isEmpty) {
      return LeadCallOutcome(LeadCallResult.dialledNotLogged, message: exotelNote);
    }

    try {
      await _callLogs.logOutgoingCall(
        leadId: leadId,
        fromNumber: _myNumber.trim(),
        toNumber: to,
      );
      return LeadCallOutcome(LeadCallResult.dialledAndLogged, message: exotelNote);
    } on Object catch (e) {
      return LeadCallOutcome(
        LeadCallResult.dialledLogFailed,
        message: e is AppError ? e.message : 'Could not log the call.',
      );
    }
  }
}

/// Null in mock mode, which routes every call to the dialler.
final exotelRemoteDataSourceProvider = Provider<ExotelRemoteDataSource?>((ref) {
  if (!ApiConfig.apiEnabled) return null;
  return ExotelRemoteDataSource(ref.watch(apiServiceProvider));
});

/// The org's telephony status, fetched once and reused.
///
/// Watch this where the Call button lives so it resolves before the first tap —
/// deciding the route on a half-loaded value is the same trap the filter drawer
/// fell into.
final exotelStatusProvider = FutureProvider<ExotelStatus>((ref) async {
  final ds = ref.watch(exotelRemoteDataSourceProvider);
  return ds == null ? const ExotelStatus.off() : ds.fetchStatus();
});

/// Synchronous view — [ExotelStatus.unknown] while the fetch is in flight, so
/// an early tap tries Exotel rather than silently taking the dialler.
final exotelStatusValueProvider = Provider<ExotelStatus>(
  (ref) => ref.watch(exotelStatusProvider).valueOrNull ?? const ExotelStatus.unknown(),
);

final leadCallServiceProvider = Provider<LeadCallService>(
  (ref) => LeadCallService(
    exotel: ref.watch(exotelRemoteDataSourceProvider),
    callLogs: ref.watch(callLogsRepositoryProvider),
    dialler: launchUrl,
    myNumber: ref.watch(sessionControllerProvider).user?.phone ?? '',
  ),
);
