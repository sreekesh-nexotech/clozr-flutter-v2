// Inline @mentions in the notes composer — a port of the webapp's
// mentionText.ts, so the ids sent with a note match what the webapp sends.
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/utils/mention_text.dart';

const _users = [
  (id: 'u1', name: 'Neeraja'),
  (id: 'u2', name: 'Neeraja Pradeep'),
  (id: 'u3', name: 'Cijo George'),
];

void main() {
  test('the longest name wins and ids come in order of appearance', () {
    expect(mentionedIdsIn('hi @Cijo George and @Neeraja Pradeep', _users), ['u3', 'u2']);
    expect(mentionedIdsIn('@Neeraja, ping', _users), ['u1']);
  });

  test('an email address is not a mention', () {
    expect(mentionedIdsIn('mail a@Neeraja.com', _users), isEmpty);
    expect(activeMentionAt('a@Ne', 4, _users), isNull);
  });

  test('typing @ opens the query, a space after a finished name ends it', () {
    expect(activeMentionAt('hello @Ci', 9, _users), (start: 6, query: 'Ci'));
    expect(activeMentionAt('@Cijo George x', 14, _users), isNull);
    // "Neeraja " still continues "Neeraja Pradeep".
    expect(activeMentionAt('@Neeraja ', 9, _users)?.query, 'Neeraja ');
  });

  test('a picked suggestion replaces the query', () {
    final r = insertMention('hey @ci', 4, 7, 'Cijo George');
    expect(r.text, 'hey @Cijo George ');
    expect(r.caret, r.text.length);
  });

  test('the Mention picker adds at the caret and removes every token', () {
    final r = appendMention('ping', 4, 'Cijo George');
    expect(r.text, 'ping @Cijo George ');
    expect(removeMention(r.text, 'u3', _users), 'ping ');
  });

  test('suggestions put name-start matches first', () {
    expect(filterMentionCandidates(_users, 'geo').map((u) => u.id), ['u3']);
    expect(filterMentionCandidates(_users, '').length, 3);
  });
}
