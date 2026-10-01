import 'dart:convert';

import 'package:gita_companion/app/providers.dart';
import 'package:gita_companion/core/api/token_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

const testServer = 'https://gita.test';

/// An in-memory imitation of the Gita Companion API, enough to drive the
/// client and the tutor screens. `answers` scripts what the teacher says;
/// an entry may be a map (the answer JSON fields) or an (status, code) error.
class FakeGitaServer {
  final requests = <http.Request>[];
  final answers = <Object>[];
  final conversations = <String, Map<String, dynamic>>{};
  final messages = <String, List<Map<String, dynamic>>>{};
  int _ids = 0;
  int signups = 0;
  int refreshes = 0;
  String access = 'access-0';
  String refresh = 'refresh-0';

  /// Next protected request is answered with 401 (as if the token expired).
  bool expireAccessToken = false;

  late final client = MockClient(_handle);

  List<Override> overrides({String builtIn = testServer}) => [
    httpClientProvider.overrideWithValue(client),
    tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
    builtInServerAddressProvider.overrideWithValue(builtIn),
  ];

  static Map<String, dynamic> answer({
    String text = 'Act without clinging to results (BG 2.47).',
    List<String> verses = const ['2.47'],
    List<String> uncertain = const [],
    List<String> flags = const [],
    String? support,
    String confidence = 'medium',
  }) => {
    'content': text,
    'citations': [
      for (final v in verses) {'verse': v, 'source_id': 'bg-sanskrit-gita-json'},
    ],
    'uncertain_points': uncertain,
    'flags': flags,
    'support': support,
    'confidence': confidence,
  };

  String _id() => '00000000-0000-0000-0000-${(++_ids).toString().padLeft(12, '0')}';

  http.Response _json(Object? body, [int status = 200, Map<String, String> headers = const {}]) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8', ...headers},
      );

  http.Response _error(int status, String code, [Map<String, String> headers = const {}]) => _json(
    {
      'error': {'code': code, 'message': code},
    },
    status,
    headers,
  );

  Map<String, dynamic> _tokens() => {
    'access_token': access,
    'refresh_token': refresh,
    'token_type': 'bearer',
    'expires_in': 900,
    'user_id': 'u',
  };

  Future<http.Response> _handle(http.Request r) async {
    requests.add(r);
    final path = r.url.path;
    final body = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;

    if (path == '/v1/auth/anonymous') {
      signups++;
      access = 'access-s$signups';
      refresh = 'refresh-s$signups';
      return _json(_tokens(), 201);
    }
    if (path == '/v1/auth/refresh') {
      if (body['refresh_token'] != refresh) return _error(401, 'unauthorized');
      refreshes++;
      access = 'access-r$refreshes';
      refresh = 'refresh-r$refreshes';
      return _json(_tokens());
    }
    if (r.headers['Authorization'] != 'Bearer $access' || expireAccessToken) {
      expireAccessToken = false;
      return _error(401, 'unauthorized');
    }

    final now = DateTime.utc(2026, 10, 1, 9).toIso8601String();
    if (path == '/v1/me' && r.method == 'DELETE') {
      conversations.clear();
      return http.Response('', 204);
    }
    if (path == '/v1/tutor/conversations' && r.method == 'POST') {
      final id = _id();
      conversations[id] = {
        'id': id,
        'title': null,
        'pinned_verse_id': body['pinned_verse_id'],
        'mode': body['mode'] ?? 'free',
        'language': body['language'] ?? 'en',
        'created_at': now,
        'updated_at': now,
      };
      messages[id] = [];
      return _json(conversations[id], 201);
    }
    if (path == '/v1/tutor/conversations' && r.method == 'GET') {
      return _json(conversations.values.toList());
    }
    final m = RegExp(r'^/v1/tutor/conversations/([^/]+)(?:/(messages|explain))?$').firstMatch(path);
    if (m != null) {
      final conv = conversations[m.group(1)];
      if (conv == null) return _error(404, 'not_found');
      if (m.group(2) == null && r.method == 'GET') {
        return _json({...conv, 'messages': messages[conv['id']]});
      }
      if (m.group(2) == null && r.method == 'DELETE') {
        conversations.remove(conv['id']);
        return http.Response('', 204);
      }
      if (answers.isEmpty) return _error(500, 'server_error');
      final next = answers.removeAt(0);
      if (next is (int, String)) {
        return _error(next.$1, next.$2, next.$2 == 'quota_exceeded' ? {'retry-after': '3600'} : const {});
      }
      final question = m.group(2) == 'explain' ? 'Explain this verse.' : body['question'] as String;
      conv['title'] ??= question;
      final q = {'id': _id(), 'role': 'user', 'content': question, 'mode': body['mode'], 'created_at': now};
      final a = {
        'id': _id(),
        'role': 'assistant',
        'mode': body['mode'],
        'created_at': now,
        'ai_generated': true,
        'provider': 'groq',
        'model': 'llama-test',
        'language': body['language'] ?? 'en',
        'out_of_scope': false,
        ...next as Map<String, dynamic>,
      };
      messages[conv['id']]!.addAll([q, a]);
      return _json({'question': q, 'answer': a});
    }
    return _error(404, 'not_found');
  }
}
