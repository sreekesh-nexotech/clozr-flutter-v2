import 'package:equatable/equatable.dart';

/// An approved WhatsApp message template that can be sent once the 24-hour
/// free-form window has closed. [body] contains a `{name}` placeholder that is
/// substituted with the contact's first name when previewed / sent.
class WhatsappTemplate extends Equatable {
  const WhatsappTemplate({required this.id, required this.name, required this.body});

  final String id;
  final String name;
  final String body;

  /// The body with `{name}` replaced by [firstName] — used for both the picker
  /// preview and the message that is actually sent.
  String resolve(String firstName) => body.replaceAll('{name}', firstName);

  @override
  List<Object?> get props => [id, name, body];
}

/// The approved template seed — a verbatim port of the prototype's `WATEMPLATES`
/// (design script ≈ line 6908). Kept as a const list so it can later be swapped
/// for a repository-backed source without touching the UI.
const List<WhatsappTemplate> kWhatsappTemplates = [
  WhatsappTemplate(
    id: 'wt1',
    name: 'Quote shared',
    body: 'Hi {name}, we have shared the latest quotation for your project. Please review and let us know if you have any questions.',
  ),
  WhatsappTemplate(
    id: 'wt2',
    name: 'Follow-up nudge',
    body: 'Hi {name}, following up on our last conversation about your fit-out. Is this week a good time to connect?',
  ),
  WhatsappTemplate(
    id: 'wt3',
    name: 'Site visit reminder',
    body: 'Hi {name}, a reminder that our team is scheduled to visit your site. Please confirm the time works for you.',
  ),
  WhatsappTemplate(
    id: 'wt4',
    name: 'Payment reminder',
    body: 'Hi {name}, a gentle reminder that a payment milestone is due this week. Thank you!',
  ),
];
