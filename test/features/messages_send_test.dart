// Optimistic-send honesty (audit M3): a bubble whose send the server rejects is
// marked `failed` (not left showing `sent`), and the retry affordance re-fires
// and recovers it. Plus the ChatMessage status helper.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/features/messages/application/providers/messages_providers.dart';
import 'package:clozrapp/features/messages/domain/entities/conversation.dart';
import 'package:clozrapp/features/messages/domain/entities/whatsapp_template.dart';
import 'package:clozrapp/features/messages/domain/repositories/messages_repository.dart';

Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Sends fail for the first [failTimes] calls, then succeed.
class _FakeRepo implements MessagesRepository {
  _FakeRepo({this.failTimes = 0});
  final int failTimes;
  int _textCalls = 0;

  @override
  Future<List<Conversation>> getConversations() async => [
        const Conversation(
          id: 'c1',
          leadId: null,
          name: 'Asha Rao',
          company: 'Acme',
          initials: 'AR',
          online: false,
          unread: 0,
          windowLeft: '20h left',
          lastTime: 'now',
          messages: [],
        ),
      ];

  @override
  Future<ChatThread> getThread(String id) async => const ChatThread();

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<ChatMessage?> sendText(String id, String text) async {
    _textCalls++;
    if (_textCalls <= failTimes) return null; // server rejected
    return ChatMessage(mine: true, text: text, time: 'Now', status: 'sent');
  }

  @override
  Future<ChatMessage?> sendTemplate(String id, String templateId, String body) async => null;

  @override
  Future<ChatMessage?> sendImage(String id, String path, String filename) async => null;

  @override
  Future<ChatMessage?> sendDocument(String id, String path, String filename) async => null;

  @override
  Future<(List<int>, String?)?> fetchMedia(String mediaId) async => null;

  @override
  Future<List<WhatsappTemplate>> getTemplates() async => const [];
}

void main() {
  test('ChatMessage.copyWith flips status; failed getter tracks it', () {
    const m = ChatMessage(mine: true, text: 'hi', time: 'Now', status: 'sent', localId: 'l1');
    expect(m.failed, isFalse);
    final f = m.copyWith(status: 'failed');
    expect(f.failed, isTrue);
    expect(f.localId, 'l1'); // identity preserved for retry targeting
    expect(f.text, 'hi');
  });

  test('a rejected send is marked failed, and retry recovers it', () async {
    final ctrl = ConversationsController(_FakeRepo(failTimes: 1));
    await settle(); // let the conversation list load

    ctrl.sendMessage('c1', 'hi');
    // Optimistic bubble is present immediately.
    expect(ctrl.state.conversations.single.messages.single.text, 'hi');

    await settle(); // send resolves as null
    final failed = ctrl.state.conversations.single.messages.single;
    expect(failed.status, 'failed');
    expect(failed.failed, isTrue);

    ctrl.retryMessage('c1', failed);
    await settle(); // second attempt succeeds
    final settled = ctrl.state.conversations.single.messages.single;
    expect(settled.status, 'sent');
    expect(settled.failed, isFalse);

    ctrl.dispose();
  });

  test('a successful send keeps the bubble sent (no false failure)', () async {
    final ctrl = ConversationsController(_FakeRepo());
    await settle();

    ctrl.sendMessage('c1', 'yo');
    await settle();
    final m = ctrl.state.conversations.single.messages.single;
    expect(m.status, 'sent');
    expect(m.failed, isFalse);

    ctrl.dispose();
  });
}
