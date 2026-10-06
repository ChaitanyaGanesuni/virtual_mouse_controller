import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An in-memory imitation of the server's accounts and study sync, with the
/// same rules as backend app/modules/sync: a global change sequence, last
/// write wins by `updated_at` with the winner returned to the loser, merged
/// reading history, journal absent = unchanged. Several installations
/// (each with its own token store) can talk to it at once.
class FakeSyncServer {
  FakeSyncServer({this.page = 500});

  /// Changes per response (the server uses 500).
  final int page;

  final requests = <http.Request>[];
  final _users = <String>[];
  final _access = <String, String>{}; // token -> user
  final _refresh = <String, String>{};
  final _codes = <String, String>{}; // code -> user
  int _n = 0;
  int _seq = 0;

  /// user -> collection -> key -> (seq, record)
  final _data = <String, Map<String, Map<String, (int, Map<String, dynamic>)>>>{};

  /// The next sync request fails with this status (e.g. 503).
  int? failNextSync;

  late final client = MockClient(_handle);

  Map<String, Map<String, dynamic>> stored(String user, String collection) => {
    for (final e in (_data[user]?[collection] ?? const {}).entries) e.key: e.value.$2,
  };

  String get lastUser => _users.last;

  http.Response _json(Object? body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

  http.Response _error(int status, String code) => _json({
    'error': {'code': code, 'message': code},
  }, status);

  Map<String, dynamic> _tokens(String user) {
    final a = 'a${++_n}', r = 'r$_n';
    _access[a] = user;
    _refresh[r] = user;
    return {
      'access_token': a,
      'refresh_token': r,
      'token_type': 'bearer',
      'expires_in': 900,
      'user_id': user,
    };
  }

  static const _keys = {
    'bookmark': ['verse_id'],
    'verse_state': ['verse_id'],
    'highlight': ['id'],
    'note': ['id'],
    'revision_item': ['verse_id', 'card_type'],
    'revision_review': ['id'],
    'daily_practice': ['date'],
    'verse_read': ['verse_id'],
    'reading_progress': ['chapter'],
  };

  Future<http.Response> _handle(http.Request r) async {
    requests.add(r);
    final body = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;
    switch (r.url.path) {
      case '/v1/auth/anonymous':
        final user = 'user-${_users.length + 1}';
        _users.add(user);
        return _json(_tokens(user), 201);
      case '/v1/auth/refresh':
        final user = _refresh.remove(body['refresh_token']);
        return user == null ? _error(401, 'unauthorized') : _json(_tokens(user));
      case '/v1/auth/recover':
        final user = _codes[(body['recovery_code'] as String).toUpperCase()];
        return user == null ? _error(401, 'unauthorized') : _json(_tokens(user));
    }
    final user = _access[(r.headers['Authorization'] ?? '').replaceFirst('Bearer ', '')];
    if (user == null) return _error(401, 'unauthorized');
    if (r.url.path == '/v1/auth/recovery-code') {
      _codes.removeWhere((_, u) => u == user);
      final code = 'ABCD-EFGH-JKMN-PQRS-TVWX-${_codes.length.toString().padLeft(4, '0')}';
      _codes[code] = user;
      return _json({'recovery_code': code}, 201);
    }
    if (r.url.path == '/v1/sync') {
      if (failNextSync != null) {
        final s = failNextSync!;
        failNextSync = null;
        return _error(s, 'server_error');
      }
      return _json(_sync(user, body));
    }
    return _error(404, 'not_found');
  }

  Map<String, dynamic> _sync(String user, Map<String, dynamic> req) {
    final store = _data.putIfAbsent(user, () => {});
    final changes = (req['changes'] as Map).cast<String, dynamic>();
    var applied = 0, rejected = 0;
    final conflicts = <(String, String)>[];
    for (final collection in _keys.keys) {
      for (final rec in ((changes[collection] as List?) ?? const []).cast<Map<String, dynamic>>()) {
        final key = _keys[collection]!.map((k) => '${rec[k]}').join('|');
        final rows = store.putIfAbsent(collection, () => {});
        final old = rows[key]?.$2;
        if (collection == 'revision_review') {
          rows.putIfAbsent(key, () => (++_seq, rec));
          applied++;
        } else if (collection == 'verse_read') {
          if (old == null) {
            rows[key] = (++_seq, rec);
          } else {
            final merged = {
              'verse_id': rec['verse_id'],
              'first_read_at': _min(old['first_read_at'], rec['first_read_at']),
              'last_read_at': _max(old['last_read_at'], rec['last_read_at']),
              'read_count': (old['read_count'] as int) > (rec['read_count'] as int)
                  ? old['read_count']
                  : rec['read_count'],
            };
            if (jsonEncode(merged) != jsonEncode(old)) rows[key] = (++_seq, merged);
          }
          applied++;
        } else if (old == null || _t(rec['updated_at']).isAfter(_t(old['updated_at']))) {
          final next = {...rec};
          if (collection == 'daily_practice' && !rec.containsKey('journal')) {
            next['journal'] = old?['journal'];
          }
          rows[key] = (++_seq, next);
          applied++;
        } else {
          rejected++;
          conflicts.add((collection, key));
        }
      }
    }
    final cursor = req['cursor'] as int;
    final found = <(int, String, Map<String, dynamic>)>[
      for (final c in store.entries)
        for (final row in c.value.values)
          if (row.$1 > cursor) (row.$1, c.key, row.$2),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final taken = found.take(page).toList();
    final out = <String, List<Map<String, dynamic>>>{for (final c in _keys.keys) c: []};
    for (final (_, c, rec) in taken) {
      out[c]!.add(_withJournal(c, rec));
    }
    for (final (c, key) in conflicts) {
      final rec = _withJournal(c, store[c]![key]!.$2);
      if (!out[c]!.any((x) => jsonEncode(x) == jsonEncode(rec))) out[c]!.add(rec);
    }
    return {
      'cursor': taken.isEmpty ? cursor : taken.last.$1,
      'more': found.length > page,
      'changes': out,
      'applied': applied,
      'rejected': rejected,
    };
  }

  static Map<String, dynamic> _withJournal(String c, Map<String, dynamic> rec) =>
      c == 'daily_practice' ? {...rec, 'journal': rec['journal']} : rec;

  static DateTime _t(Object? s) => DateTime.parse(s! as String);
  static Object? _min(Object? a, Object? b) => _t(a).isBefore(_t(b)) ? a : b;
  static Object? _max(Object? a, Object? b) => _t(a).isAfter(_t(b)) ? a : b;
}
