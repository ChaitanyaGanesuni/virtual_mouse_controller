import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The device's credentials for one server. Tokens from another server are
/// never sent anywhere else.
class Tokens {
  const Tokens({required this.server, required this.access, required this.refresh, this.userId});

  final String server;
  final String access;
  final String refresh;

  /// The account these tokens belong to (null for tokens saved before
  /// Phase 8). Sync uses it to notice that the account changed.
  final String? userId;

  Map<String, String> toJson() => {
    'server': server,
    'access': access,
    'refresh': refresh,
    'user_id': ?userId,
  };

  static Tokens? fromJson(Object? json) {
    if (json is! Map) return null;
    final server = json['server'], access = json['access'], refresh = json['refresh'];
    if (server is! String || access is! String || refresh is! String) return null;
    final user = json['user_id'];
    return Tokens(server: server, access: access, refresh: refresh, userId: user is String ? user : null);
  }
}

abstract interface class TokenStore {
  Future<Tokens?> read();
  Future<void> write(Tokens tokens);
  Future<void> clear();
}

/// Android Keystore-backed storage. The tokens never touch the app's
/// databases or logs.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'gita.auth.tokens';
  final FlutterSecureStorage _storage;

  @override
  Future<Tokens?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      return raw == null ? null : Tokens.fromJson(jsonDecode(raw));
    } catch (_) {
      // Unreadable (e.g. keystore reset after a backup restore): sign in again.
      return null;
    }
  }

  @override
  Future<void> write(Tokens tokens) => _storage.write(key: _key, value: jsonEncode(tokens.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class MemoryTokenStore implements TokenStore {
  Tokens? tokens;

  @override
  Future<Tokens?> read() async => tokens;

  @override
  Future<void> write(Tokens t) async => tokens = t;

  @override
  Future<void> clear() async => tokens = null;
}
