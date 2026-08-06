import '../entities/call_log.dart';

/// Abstract contract for call-log data.
///
/// Call logs are only ever read per record (the Call log tab on a lead), so
/// there is no org-wide list method — the list endpoint is always scoped with
/// `related_to` / `related_to_id`.
abstract class CallLogsRepository {
  /// Calls logged against [leadId], newest first.
  Future<List<CallLog>> getCallLogsForLead(String leadId);

  /// Records an outgoing call placed to a lead.
  ///
  /// There is no "place a call" endpoint — the device dials, this records that
  /// it happened. [fromNumber] is the caller's own number and is **required**
  /// by the API, so a caller with no number on their profile cannot log.
  ///
  /// Logging also re-scores the lead server-side, which is why it is worth
  /// doing even with no duration attached.
  Future<void> logOutgoingCall({
    required String leadId,
    required String fromNumber,
    required String toNumber,
  });
}
