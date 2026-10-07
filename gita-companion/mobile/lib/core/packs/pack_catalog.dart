import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

/// One downloadable pack, as GET /v1/packs describes it.
class PackInfo {
  const PackInfo({
    required this.id,
    required this.kind,
    required this.title,
    required this.version,
    required this.size,
    required this.sha256,
    required this.url,
    this.contentHash,
    this.packSchemaVersion,
  });

  factory PackInfo.fromJson(Map<String, dynamic> j, Uri server) => PackInfo(
    id: j['id'] as String,
    kind: j['kind'] as String,
    title: j['title'] as String,
    version: j['version'] as String,
    size: j['size'] as int,
    sha256: j['sha256'] as String,
    // Relative URLs are on the same server.
    url: server.resolve(j['url'] as String),
    contentHash: j['content_hash'] as String?,
    packSchemaVersion: j['pack_schema_version'] as int?,
  );

  final String id;
  final String kind;
  final String title;

  /// Orders versions of the same pack (for content: the build time).
  final String version;
  final int size;
  final String sha256;
  final Uri url;
  final String? contentHash;
  final int? packSchemaVersion;
}

class CatalogUnavailable implements Exception {
  CatalogUnavailable(this.reason);

  /// 'not_configured', 'offline' or 'server_error'.
  final String reason;

  @override
  String toString() => 'CatalogUnavailable($reason)';
}

/// Fetches the pack catalog. Public: no account is created to look.
class PackCatalogClient {
  PackCatalogClient(this._http, this._server, {this.timeout = const Duration(seconds: 60)});

  final http.Client _http;
  final String Function() _server;
  final Duration timeout;

  Future<List<PackInfo>> fetch() async {
    final server = _server();
    if (server.isEmpty) throw CatalogUnavailable('not_configured');
    final base = Uri.parse(server.endsWith('/') ? server : '$server/');
    http.Response r;
    try {
      r = await _http.get(base.resolve('v1/packs'), headers: {'Accept': 'application/json'}).timeout(timeout);
    } on SocketException {
      throw CatalogUnavailable('offline');
    } on http.ClientException {
      throw CatalogUnavailable('offline');
    } on TimeoutException {
      throw CatalogUnavailable('offline');
    }
    if (r.statusCode != 200) throw CatalogUnavailable('server_error');
    final json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return [for (final p in (json['packs'] as List).cast<Map<String, dynamic>>()) PackInfo.fromJson(p, base)];
  }
}
