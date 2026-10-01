import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/core/api/api_client.dart';
import 'package:gita_companion/core/api/server_address.dart';
import 'package:gita_companion/core/api/token_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_server.dart';

void main() {
  late FakeGitaServer server;
  late MemoryTokenStore store;
  late String address;

  ApiClient client({http.Client? http, Duration timeout = const Duration(seconds: 5)}) =>
      ApiClient(client: http ?? server.client, serverAddress: () => address, tokens: store, timeout: timeout);

  setUp(() {
    server = FakeGitaServer();
    store = MemoryTokenStore();
    address = testServer;
  });

  test('without a server address nothing is sent', () async {
    address = '';
    await expectLater(
      client().get('/v1/tutor/conversations'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'not_configured')),
    );
    expect(server.requests, isEmpty);
  });

  test('signs in anonymously on first use and sends the bearer token', () async {
    await client().get('/v1/tutor/conversations');
    expect(server.requests.map((r) => r.url.path), ['/v1/auth/anonymous', '/v1/tutor/conversations']);
    expect(server.requests.last.headers['Authorization'], 'Bearer access-s1');
    expect(store.tokens!.server, testServer);
    expect(store.tokens!.refresh, 'refresh-s1');
  });

  test('an expired access token is refreshed once and the request retried', () async {
    final api = client();
    await api.get('/v1/tutor/conversations');
    server.expireAccessToken = true;
    await api.get('/v1/tutor/conversations');
    expect(server.refreshes, 1);
    expect(server.requests.last.headers['Authorization'], 'Bearer access-r1');
    expect(store.tokens!.refresh, 'refresh-r1');
  });

  test('concurrent 401s share one refresh (refresh tokens are single-use)', () async {
    final api = client();
    await api.get('/v1/tutor/conversations');
    server.access = 'rotated-elsewhere'; // every request now gets 401 until refreshed
    await Future.wait([api.get('/v1/tutor/conversations'), api.get('/v1/tutor/conversations')]);
    expect(server.refreshes, 1);
    expect(server.signups, 1);
  });

  test('concurrent first requests create only one account', () async {
    final api = client();
    await Future.wait([api.get('/v1/tutor/conversations'), api.get('/v1/tutor/conversations')]);
    expect(server.signups, 1);
  });

  test('a revoked refresh token leads to a fresh anonymous account', () async {
    final api = client();
    await api.get('/v1/tutor/conversations');
    server
      ..access = 'x'
      ..refresh = 'revoked';
    await api.get('/v1/tutor/conversations');
    expect(server.signups, 2);
    expect(store.tokens!.access, 'access-s2');
  });

  test('tokens are never sent to a different server', () async {
    final api = client();
    await api.get('/v1/tutor/conversations');
    address = 'https://other.test';
    final other = FakeGitaServer()..signups = 10; // issues access-s11, not access-s1
    final api2 = client(http: other.client);
    await api2.get('/v1/tutor/conversations');
    expect(other.requests.first.url.path, '/v1/auth/anonymous');
    expect(other.requests.any((r) => r.headers['Authorization'] == 'Bearer access-s1'), isFalse);
  });

  test('server errors carry their code and Retry-After', () async {
    server.answers.add((429, 'quota_exceeded'));
    final api = client();
    await api.get('/v1/tutor/conversations');
    final conv = await api.post('/v1/tutor/conversations', {'mode': 'free'}) as Map;
    await expectLater(
      api.post('/v1/tutor/conversations/${conv['id']}/messages', {'question': 'q'}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'quota_exceeded')
            .having((e) => e.retryAfter, 'retryAfter', const Duration(hours: 1)),
      ),
    );
  });

  test('network failures become offline / timeout', () async {
    final offline = MockClient((_) async => throw const SocketException('no route'));
    await expectLater(
      client(http: offline).get('/v1/health'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'offline')),
    );
    final hanging = MockClient((_) => Completer<http.Response>().future);
    await expectLater(
      client(http: hanging, timeout: const Duration(milliseconds: 50)).get('/v1/health'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'timeout')),
    );
  });

  test('deleting the account removes server data and local credentials', () async {
    final api = client();
    await api.deleteAccount(); // nothing to delete yet: no request
    expect(server.requests, isEmpty);
    await api.get('/v1/tutor/conversations');
    await api.deleteAccount();
    expect(server.requests.last.method, 'DELETE');
    expect(server.requests.last.url.path, '/v1/me');
    expect(store.tokens, isNull);
  });

  group('server address', () {
    test('only HTTPS, except a server on this machine', () {
      expect(checkServerAddress(''), isNull);
      expect(checkServerAddress('https://gita.example.org/'), isNull);
      expect(checkServerAddress('https://gita.example.org/api'), isNull);
      expect(checkServerAddress('http://gita.example.org'), ServerAddressProblem.httpsRequired);
      expect(checkServerAddress('http://10.0.2.2:8000'), isNull);
      expect(checkServerAddress('http://localhost:8000'), isNull);
      expect(checkServerAddress('gita.example.org'), ServerAddressProblem.invalid);
      expect(checkServerAddress('ftp://gita.example.org'), ServerAddressProblem.invalid);
      expect(checkServerAddress('https://gita.example.org?x=1'), ServerAddressProblem.invalid);
    });

    test('the user choice wins over the built-in address; invalid values are ignored', () {
      expect(effectiveServerAddress('', builtIn: 'https://a.test/'), 'https://a.test');
      expect(effectiveServerAddress('https://b.test', builtIn: 'https://a.test'), 'https://b.test');
      expect(effectiveServerAddress('http://evil.test', builtIn: 'https://a.test'), 'https://a.test');
      expect(effectiveServerAddress('', builtIn: ''), '');
      expect(effectiveServerAddress('', builtIn: 'http://plain.test'), '');
    });
  });
}
