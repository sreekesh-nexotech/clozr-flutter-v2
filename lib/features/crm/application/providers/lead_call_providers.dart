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

/// A phone number as both the telephony API and the dialler want it: E.164 —
/// digits behind a single `+`, no spaces or punctuation.
///
/// Numbers reach the app however they were typed; the add-lead form's own hint
/// is "+91 98470 00000". Exotel's `to_number` must be bare E.164, so the
/// separators have to come off before the number is used for anything. A number
/// that arrives without a `+` is left without one rather than being guessed a
/// country code.
String normaliseCallNumber(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';
  return trimmed.startsWith('+') ? '+$digits' : digits;
}

/// Whether a refusal means click-to-call will not work for this caller **at
/// all** — the org has no Exotel, or this user is not a telephony agent.
///
/// Worth separating from a transient upstream failure because the answer is
/// permanent: there is nothing to retry, so re-POSTing on every Call tap only
/// buys a wasted round trip. Matched on the message because the API returns all
/// of these as a plain `400` with no code to branch on.
bool isExotelConfigRefusal(String message) {
  final m = message.toLowerCase();
  return m.contains('integration is disabled') ||
      m.contains('not fully configured') ||
      m.contains('not configured as a telephony agent') ||
      m.contains('not enabled for this telephony agent') ||
      m.contains('missing telephony agent');
}

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
    String? blockedReason,
    void Function(String reason)? onBlocked,
  })  : _exotel = exotel,
        _callLogs = callLogs,
        _dial = dialler,
        _myNumber = myNumber,
        _blockedReason = blockedReason,
        _onBlocked = onBlocked;

  final ExotelRemoteDataSource? _exotel;
  final CallLogsRepository _callLogs;
  final Dialler _dial;

  /// The signed-in user's own number (`profile.phone`) — the `from_number` a
  /// manual call log requires. Empty on an account with no profile phone.
  final String _myNumber;

  /// Why click-to-call is already known to be unavailable to this caller, from
  /// [exotelBlockedProvider]. Non-null means skip the POST — see [call].
  final String? _blockedReason;

  /// Called with the server's reason the first time a configuration refusal
  /// comes back, so it is remembered for the session.
  final void Function(String reason)? _onBlocked;

  Future<LeadCallOutcome> call({
    required String leadId,
    required String toNumber,
    required ExotelStatus status,
  }) async {
    final to = normaliseCallNumber(toNumber);
    if (to.isEmpty) return const LeadCallOutcome(LeadCallResult.noNumber);

    String? exotelNote;
    final exotel = _exotel;
    // A remembered configuration refusal short-circuits the attempt: it can
    // only be refused again, and the screen already carries the reason as a
    // standing notice.
    if (exotel != null &&
        _blockedReason == null &&
        (status.usable || !status.known)) {
      try {
        await exotel.placeCall(leadId: leadId, toNumber: to);
        return const LeadCallOutcome(LeadCallResult.ringingViaExotel);
      } on Object catch (e) {
        // Refused — nothing was dialled, so fall through to the dialler. The
        // reason is always carried now. It used to be dropped whenever the
        // status was merely unknown, which is the state every ordinary sales
        // user is in (`/exotel/status/` is settings-gated and 403s for them) —
        // so the single most common failure, "You are not configured as a
        // telephony agent", was explained nowhere.
        exotelNote =
            e is AppError ? e.message : 'Exotel could not place the call.';
        if (e is AppError && isExotelConfigRefusal(e.message)) {
          _onBlocked?.call(e.message);
        }
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

/// Why click-to-call is unavailable to this user, in the server's own words —
/// null until a call learns otherwise, and always null in mock mode.
///
/// A configuration refusal (no Exotel on the org, caller is not a telephony
/// agent) is permanent for the session, so it is remembered rather than
/// rediscovered on every tap. It is deliberately **not** a toast: by the time
/// one could be shown the device dialler is already in front of the user and a
/// timed message goes unseen. The detail screen shows this beside the Call
/// button instead, where it stays.
final exotelBlockedProvider = StateProvider<String?>((ref) => null);

final leadCallServiceProvider = Provider<LeadCallService>(
  (ref) => LeadCallService(
    exotel: ref.watch(exotelRemoteDataSourceProvider),
    callLogs: ref.watch(callLogsRepositoryProvider),
    dialler: launchUrl,
    myNumber: ref.watch(sessionControllerProvider).user?.phone ?? '',
    // Watched, not read: the service is cached, so a `read` here would hand
    // every later call the stale `null` and keep re-POSTing a refused request.
    blockedReason: ref.watch(exotelBlockedProvider),
    onBlocked: (reason) =>
        ref.read(exotelBlockedProvider.notifier).state = reason,
  ),
);
