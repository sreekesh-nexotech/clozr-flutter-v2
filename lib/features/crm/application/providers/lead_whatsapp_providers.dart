import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../messages/application/providers/messages_providers.dart';
import '../../../messages/domain/entities/conversation.dart';

/// Where the lead's WhatsApp button ended up sending the user.
enum LeadWhatsappResult {
  /// The lead already has a WhatsApp thread in the CRM — open it in Chat.
  openedThread,

  /// No thread here yet, so the number was handed to the WhatsApp app.
  handedToWhatsapp,

  /// The lead has no phone number, so there is nothing to open.
  noNumber,

  /// The device would not open WhatsApp (not installed, no browser).
  whatsappUnavailable,

  /// The conversation list could not be read, so we cannot tell whether a
  /// thread exists — see [LeadWhatsappOutcome.message].
  lookupFailed,
}

/// The outcome plus what the caller needs to act on it.
class LeadWhatsappOutcome {
  const LeadWhatsappOutcome(this.result, {this.conversationId, this.message});

  final LeadWhatsappResult result;

  /// The thread to open — set only on [LeadWhatsappResult.openedThread].
  final String? conversationId;

  /// A user-safe note (why the lookup failed).
  final String? message;
}

/// Opens WhatsApp for a URL. Injected so the routing is testable without a
/// platform channel.
typedef WhatsappLauncher = Future<bool> Function(Uri uri);

/// Decides what the lead's WhatsApp button opens.
///
/// Two routes, because a WhatsApp conversation is not something the CRM can
/// create on demand:
///
/// * **The in-app thread** when the org already has one for this lead. That is
///   the whole point of the button — replies stay in the CRM, the 24-hour
///   window and the approved-template picker are enforced by the chat screen,
///   and the thread is marked read server-side (`POST /conversations/<id>/read/`).
/// * **The WhatsApp app** otherwise, pre-addressed to the lead's number.
///
/// The fallback is deliberate rather than a stub. `/api/v1/whatsapp/` has no
/// "create conversation" endpoint: a thread appears when the customer messages
/// in, or when a template is sent to their number — and `POST /send/template/`
/// needs a `whatsapp_account_id`, which only `GET /accounts/` serves and only a
/// System Admin may read. So a first outbound message cannot be composed from
/// this screen by any sales user, and the honest thing is to hand the number to
/// WhatsApp itself — exactly as Call hands an un-bridgeable number to the
/// device dialler. Once that first message is answered the webhook creates the
/// conversation and this button starts landing on the in-app thread instead.
class LeadWhatsappService {
  const LeadWhatsappService({
    required Future<void> Function() ensureLoaded,
    required List<Conversation> Function() conversations,
    required WhatsappLauncher launcher,
  })  : _ensureLoaded = ensureLoaded,
        _conversations = conversations,
        _launch = launcher;

  final Future<void> Function() _ensureLoaded;
  final List<Conversation> Function() _conversations;
  final WhatsappLauncher _launch;

  Future<LeadWhatsappOutcome> open({
    required String leadId,
    required String phone,
  }) async {
    final digits = waDigits(phone);

    String? lookupError;
    try {
      // The CRM tab is usually opened without Messages having ever rendered, so
      // the list may not be loaded yet. Awaiting it is what keeps a cold start
      // from falling through to the WhatsApp app on a lead that has a thread.
      await _ensureLoaded();
    } on Object {
      // A failed fetch is not a dead end — the number can still be reached — but
      // it must not be reported as "no thread", so the reason is carried on.
      lookupError = 'Could not check for an existing chat.';
    }

    final existing = findConversationForLead(
      _conversations(),
      leadId: leadId,
      phone: digits,
    );
    if (existing != null) {
      return LeadWhatsappOutcome(LeadWhatsappResult.openedThread,
          conversationId: existing.id);
    }

    if (digits.isEmpty) {
      return LeadWhatsappOutcome(
        lookupError == null
            ? LeadWhatsappResult.noNumber
            : LeadWhatsappResult.lookupFailed,
        message: lookupError,
      );
    }

    // wa.me takes E.164 digits with no `+`; it opens the installed app and
    // falls back to WhatsApp Web in a browser when there is none.
    final opened = await _openWhatsapp(Uri.parse('https://wa.me/$digits'));
    if (!opened) {
      return LeadWhatsappOutcome(LeadWhatsappResult.whatsappUnavailable,
          message: lookupError);
    }
    return LeadWhatsappOutcome(LeadWhatsappResult.handedToWhatsapp,
        message: lookupError);
  }

  Future<bool> _openWhatsapp(Uri uri) async {
    try {
      return await _launch(uri);
    } on Object {
      // A device with no handler throws rather than answering false.
      return false;
    }
  }
}

final leadWhatsappServiceProvider = Provider<LeadWhatsappService>((ref) {
  return LeadWhatsappService(
    // `read` inside the callbacks, not `watch` at build time: the service is
    // cached for the screen's life and both calls must see the list as it is at
    // the moment of the tap, not as it was when the button was first drawn.
    ensureLoaded: () => ref.read(conversationsProvider.notifier).ensureLoaded(),
    conversations: () => ref.read(conversationsProvider).conversations,
    // externalApplication, or Android may hand a wa.me link to an in-app
    // webview that cannot open the app it redirects to.
    launcher: (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
  );
});
