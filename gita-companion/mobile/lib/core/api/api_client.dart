import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import 'token_store.dart';

/// Errors the UI knows how to explain. `code` is either one of the server's
/// error codes (quota_exceeded, providers_busy, no_verified_answer, ...) or
/// a client-side one: not_configured, offline, timeout, server_error.
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.status, this.retryAfter});

  final String code;
  final String message;
  final int? status;
  final Duration? retryAfter;

  @override
  String toString() => 'ApiException($code, $status): $message';
}

/// Talks to the Gita Companion server over HTTPS.
///
/// The device signs in anonymously the first time it is needed. Access
/// tokens last 15 minutes; on a 401 the client refreshes once (only one
/// refresh at a time, because a refresh token is single-use) and retries.
class ApiClient {
  ApiClient({
    required http.Client client,
    required String Function() serverAddress,
    required this._tokens,
    // A free-tier server may be asleep: waking it can take a minute.
    this.timeout = const Duration(seconds: 100),
  }) : _http = client,
       _server = serverAddress;

  final http.Client _http;
  final String Function() _server;
  final TokenStore _tokens;
  final Duration timeout;
  Future<Tokens>? _refreshing;
  Future<Tokens>? _signingUp;

  bool get isConfigured => _server().isNotEmpty;

  Future<dynamic> get(String path) => _request('GET', path);
  Future<dynamic> post(String path, [Object? body]) => _request('POST', path, body: body ?? const {});
  Future<dynamic> delete(String path) => _request('DELETE', path);

  /// Deletes the account and everything the server stores for it, then
  /// forgets the credentials.
  Future<void> deleteAccount() async {
    final t = await _currentTokens();
    if (t != null) await _request('DELETE', '/v1/me');
    await _tokens.clear();
  }

  /// The account this device is signed in to, signing in (anonymously)
  /// first if needed.
  Future<String?> accountId() async {
    final server = _server();
    if (server.isEmpty) {
      throw ApiException('not_configured', 'No server is set up.');
    }
    final t =
        await _currentTokens() ??
        await (_signingUp ??= _signUp(server).whenComplete(() => _signingUp = null));
    return t.userId;
  }

  /// A new recovery code for this account (any previous one stops working).
  Future<String> createRecoveryCode() async {
    final json = await post('/v1/auth/recovery-code') as Map<String, dynamic>;
    return json['recovery_code'] as String;
  }

  /// Signs this installation in to the account [code] belongs to. The
  /// previous credentials are replaced.
  Future<String?> recover(String code) async {
    final server = _server();
    if (server.isEmpty) {
      throw ApiException('not_configured', 'No server is set up.');
    }
    final response = await _send('POST', '$server/v1/auth/recover', body: {'recovery_code': code});
    final t = _tokensFrom(server, _decode(response) as Map<String, dynamic>);
    await _tokens.write(t);
    return t.userId;
  }

  static Tokens _tokensFrom(String server, Map<String, dynamic> json) => Tokens(
    server: server,
    access: json['access_token'] as String,
    refresh: json['refresh_token'] as String,
    userId: json['user_id'] as String?,
  );

  Future<dynamic> _request(String method, String path, {Object? body}) async {
    final server = _server();
    if (server.isEmpty) {
      throw ApiException('not_configured', 'No AI teacher server is set up.');
    }
    var tokens =
        await _currentTokens() ??
        await (_signingUp ??= _signUp(server).whenComplete(() => _signingUp = null));
    var response = await _send(method, '$server$path', body: body, token: tokens.access);
    if (response.statusCode == 401) {
      tokens = await _refreshOnce(tokens);
      response = await _send(method, '$server$path', body: body, token: tokens.access);
    }
    return _decode(response);
  }

  Future<Tokens?> _currentTokens() async {
    final t = await _tokens.read();
    return (t != null && t.server == _server()) ? t : null;
  }

  Future<Tokens> _signUp(String server) async {
    final json = _decode(await _send('POST', '$server/v1/auth/anonymous')) as Map<String, dynamic>;
    final t = _tokensFrom(server, json);
    await _tokens.write(t);
    return t;
  }

  Future<Tokens> _refreshOnce(Tokens stale) =>
      _refreshing ??= _refresh(stale).whenComplete(() => _refreshing = null);

  Future<Tokens> _refresh(Tokens stale) async {
    final response = await _send(
      'POST',
      '${stale.server}/v1/auth/refresh',
      body: {'refresh_token': stale.refresh},
    );
    if (response.statusCode == 401) {
      // Revoked or expired: this device starts a fresh anonymous account.
      await _tokens.clear();
      return _signUp(stale.server);
    }
    final t = _tokensFrom(stale.server, _decode(response) as Map<String, dynamic>);
    await _tokens.write(t);
    return t;
  }

  Future<http.Response> _send(String method, String url, {Object? body, String? token}) async {
    final request = http.Request(method, Uri.parse(url))
      ..headers['Accept'] = 'application/json'
      ..followRedirects = false;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final streamed = await _http.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw ApiException('timeout', 'The server did not answer in time.');
    } on SocketException catch (e) {
      throw ApiException('offline', e.message);
    } on http.ClientException catch (e) {
      throw ApiException('offline', e.message);
    }
  }

  dynamic _decode(http.Response r) {
    if (r.statusCode == 204) return null;
    Object? json;
    try {
      json = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    } on FormatException {
      json = null;
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return json;
    final error = json is Map && json['error'] is Map ? json['error'] as Map : const {};
    final seconds = int.tryParse(r.headers['retry-after'] ?? '');
    throw ApiException(
      error['code'] as String? ?? (r.statusCode >= 500 ? 'server_error' : 'http_${r.statusCode}'),
      error['message'] as String? ?? 'HTTP ${r.statusCode}',
      status: r.statusCode,
      retryAfter: seconds == null ? null : Duration(seconds: seconds),
    );
  }
}
