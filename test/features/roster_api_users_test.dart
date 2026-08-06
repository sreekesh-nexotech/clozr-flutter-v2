import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/data/api/user_directory.dart';
import 'package:clozrapp/data/mock/mock_users.dart';

/// The Assignees picker sent the prototype id `dr` to the API, which answered
/// `400 {"assignees": ["dr" is not a valid UUID]}`.
///
/// The cause: `MockUsers.byId` is *seeded* with the prototype reps, and real
/// users are registered into that same map — so its contents cannot tell a
/// server user from a fixture one. These pin the check that can.
void main() {
  const meUuid = '6dee7584-11b4-4851-88d4-4819c17bf0b0';
  const otherUuid = '323cac4a-eaad-4b65-8e5b-eab450dc5bef';

  setUp(() {
    UserDirectory.reset();
    UserDirectory.currentUserId = meUuid;
  });

  tearDown(UserDirectory.reset);

  test('the prototype reps really are in the shared directory', () {
    // Not a behaviour we want — just the fact the guard exists to handle.
    expect(MockUsers.byId.containsKey('dr'), isTrue);
  });

  group('isApiUser', () {
    test('rejects a prototype rep id', () {
      expect(UserDirectory.isApiUser('dr'), isFalse);
      expect(UserDirectory.isApiUser('am'), isFalse);
    });

    test('accepts a user the API registered', () {
      UserDirectory.register(userId: otherUuid, fullName: 'Karan Desai');
      expect(UserDirectory.isApiUser(otherUuid), isTrue);
    });

    test('accepts the "me" sentinel once a session exists', () {
      expect(UserDirectory.isApiUser('me'), isTrue);
      UserDirectory.currentUserId = null;
      expect(UserDirectory.isApiUser('me'), isFalse);
    });

    test('rejects null and empty', () {
      expect(UserDirectory.isApiUser(null), isFalse);
      expect(UserDirectory.isApiUser(''), isFalse);
    });
  });

  group('realUserId — what actually reaches the API', () {
    test('a prototype id resolves to null instead of being posted', () {
      // This is the 400. Returning null lets the caller omit the field.
      expect(UserDirectory.realUserId('dr'), isNull);
    });

    test('"me" becomes the signed-in uuid', () {
      expect(UserDirectory.realUserId('me'), meUuid);
    });

    test('"me" with no session resolves to null, not the literal "me"', () {
      UserDirectory.currentUserId = null;
      expect(UserDirectory.realUserId('me'), isNull);
    });

    test('a registered uuid passes through unchanged', () {
      UserDirectory.register(userId: otherUuid, fullName: 'Karan Desai');
      expect(UserDirectory.realUserId(otherUuid), otherUuid);
    });

    test('an unregistered uuid is rejected too', () {
      // Well-formed but unknown — the server may still not have it.
      expect(
        UserDirectory.realUserId('11111111-2222-4333-8444-555555555555'),
        isNull,
      );
    });

    test('registering via an embedded record object is enough', () {
      // Most users arrive this way rather than from the members endpoint,
      // which a non-admin cannot read.
      UserDirectory.registerJson(
          {'user_id': otherUuid, 'full_name': 'Karan Desai'});
      expect(UserDirectory.realUserId(otherUuid), otherUuid);
    });
  });

  test('logging out forgets the roster — it is another tenant next session', () {
    UserDirectory.register(userId: otherUuid, fullName: 'Karan Desai');
    expect(UserDirectory.isApiUser(otherUuid), isTrue);

    UserDirectory.reset();

    expect(UserDirectory.isApiUser(otherUuid), isFalse);
    expect(UserDirectory.realUserId(otherUuid), isNull);
  });
}
