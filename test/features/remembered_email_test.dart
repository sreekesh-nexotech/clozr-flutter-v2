// "Remember me" on the sign-in screen. The session itself already survives a
// restart through the token store, so this remembers the work email only —
// never a password.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/storage/remembered_email.dart';

/// An in-memory stand-in for the platform keystore.
class _FakeSecureStorage extends FlutterSecureStorage {
  const _FakeSecureStorage(this._store);
  final Map<String, String> _store;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _store.remove(key);
}

void main() {
  late Map<String, String> store;
  late RememberedEmail remembered;

  setUp(() {
    store = {};
    remembered = RememberedEmail(_FakeSecureStorage(store));
  });

  test('nothing is remembered until the box is ticked', () async {
    expect(await remembered.read(), isNull);
    await remembered.save('rep@acme.com', remember: false);
    expect(await remembered.read(), isNull);
  });

  test('a ticked box survives to the next sign-in', () async {
    await remembered.save('rep@acme.com', remember: true);
    expect(await remembered.read(), 'rep@acme.com');
  });

  test('unticking it forgets what an earlier sign-in stored', () async {
    await remembered.save('rep@acme.com', remember: true);
    await remembered.save('rep@acme.com', remember: false);
    expect(await remembered.read(), isNull);
  });

  test('the address is trimmed, so a stray space does not come back', () async {
    await remembered.save('  rep@acme.com  ', remember: true);
    expect(await remembered.read(), 'rep@acme.com');
  });

  test('an empty address is nothing to remember', () async {
    await remembered.save('   ', remember: true);
    expect(await remembered.read(), isNull);
  });

  test('only the email is stored — no password key is ever written', () async {
    await remembered.save('rep@acme.com', remember: true);
    expect(store.keys, ['auth_remembered_email']);
    expect(store.values.join().toLowerCase(), isNot(contains('password')));
  });
}
