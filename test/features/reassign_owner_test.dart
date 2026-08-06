// Reassigning a lead's owner: who the picker may offer, and what the write
// looks like on the wire.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clozrapp/core/network/api_service.dart';
import 'package:clozrapp/core/storage/token_storage.dart';
import 'package:clozrapp/data/api/user_directory.dart';
import 'package:clozrapp/features/crm/infrastructure/data_sources/remote/leads_remote_ds.dart';

const _leadId = 'lead-1';
const _meUuid = '11111111-1111-4111-8111-111111111111';
const _otherUuid = '22222222-2222-4222-8222-222222222222';

/// Serves a canned body and records the requests it saw.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.body);

  final Object body;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

LeadsRemoteDataSource _dsWith(_Adapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://x/api/v1'))
    ..httpClientAdapter = adapter;
  return LeadsRemoteDataSource(ApiService(tokens: TokenStorage(), dio: dio));
}

Map<String, dynamic> _user(String id, String name) => {
      'user_id': id,
      'full_name': name,
      'username': '$name@x.com',
      'email': '$name@x.com',
      'is_active': true,
    };

void main() {
  setUp(() => UserDirectory.currentUserId = _meUuid);
  tearDown(UserDirectory.reset);

  group('assignable users', () {
    test('reads the record endpoint, not the org roster', () async {
      final adapter = _Adapter({
        'count': 2,
        'next': null,
        'results': [_user(_meUuid, 'Admin Acme'), _user(_otherUuid, 'Karan Desai')],
      });

      final users = await _dsWith(adapter).fetchAssignableUsers(_leadId);

      // Eligibility is per record — `/management/users/` would be the wrong list.
      expect(adapter.requests.single.path, '/crm/leads/$_leadId/assignable-users/');
      expect(users.map((u) => u.name).toList(), ['Admin Acme', 'Karan Desai']);
      // Ids stay the raw uuids: they are what the PATCH sends.
      expect(users.map((u) => u.id).toList(), [_meUuid, _otherUuid]);
    });

    test('registers each user so avatars resolve to the same person', () async {
      final adapter = _Adapter({
        'results': [_user(_otherUuid, 'Karan Desai')],
      });
      await _dsWith(adapter).fetchAssignableUsers(_leadId);
      expect(UserDirectory.mapUserId(_otherUuid), _otherUuid);
      // The signed-in user still folds to the 'me' sentinel the UI compares on.
      expect(UserDirectory.mapUserId(_meUuid), 'me');
    });

    test('a row without an id or a name is skipped, never a blank option', () async {
      final adapter = _Adapter({
        'results': [
          _user(_otherUuid, 'Karan Desai'),
          {'user_id': '', 'full_name': 'No Id'},
          {'user_id': 'x', 'full_name': '', 'username': ''},
        ],
      });
      final users = await _dsWith(adapter).fetchAssignableUsers(_leadId);
      expect(users, hasLength(1));
    });
  });

  group('the write', () {
    test('PATCHes lead_owner with the picked user_id', () async {
      final adapter = _Adapter({'lead_id': _leadId, 'lead_name': 'X'});

      await _dsWith(adapter).updateLead(_leadId, {'lead_owner': _otherUuid});

      final req = adapter.requests.single;
      expect(req.method, 'PATCH');
      expect(req.path, '/crm/leads/$_leadId/');
      expect(req.data, {'lead_owner': _otherUuid});
    });
  });
}
