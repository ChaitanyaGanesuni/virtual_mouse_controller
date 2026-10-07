import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';

import 'pack.dart';

const packServer = 'https://gita.test';

/// The content hash of [makeUpdatedPack]'s pack.
const updatedHash = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';

/// A content pack newer than the bundled one: the real pack with a changed
/// translation of [verseId], a new content hash and a later build time.
File makeUpdatedPack({
  String verseId = '12.13',
  String marker = 'UPDATED TRANSLATION',
  String builtAt = '2099-01-01T00:00:00+00:00',
  int schema = 3,
}) {
  final dir = Directory.systemTemp.createTempSync('updated_pack');
  final f = requirePack().copySync('${dir.path}/pack.sqlite');
  sqlite3.open(f.path)
    ..execute(
      "UPDATE verse_text SET body = ? || ' ' || body WHERE verse_id = ? AND kind = 'translation' AND language = 'en'",
      [marker, verseId],
    )
    ..execute("UPDATE pack_meta SET value = ? WHERE key = 'content_hash'", [updatedHash])
    ..execute("UPDATE pack_meta SET value = ? WHERE key = 'built_at'", [builtAt])
    ..execute("UPDATE pack_meta SET value = ? WHERE key = 'pack_schema_version'", ['$schema'])
    ..execute('VACUUM')
    ..close();
  return f;
}

/// Serves GET /v1/packs and the content pack file, with HTTP Range, the
/// way the backend does (app/api/packs.py).
class FakePackServer {
  FakePackServer(
    this.pack, {
    this.contentHash = updatedHash,
    this.builtAt = '2099-01-01T00:00:00+00:00',
    this.schema = 3,
  }) : bytes = pack.readAsBytesSync();

  final File pack;
  final Uint8List bytes;
  final String contentHash;
  final String builtAt;
  final int schema;

  final requests = <http.Request>[];

  /// Cut the connection after this many bytes of the next file response.
  int? dropAfter;

  /// Corrupt the next file response.
  bool corrupt = false;

  /// Everything fails, as in airplane mode.
  bool offline = false;

  late final client = MockClient.streaming((request, body) async {
    final r = request as http.Request;
    requests.add(r);
    if (offline) throw const SocketException('airplane mode');
    if (r.url.path == '/v1/packs') {
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'packs': [
                {
                  'id': 'content',
                  'kind': 'content',
                  'title': 'Texts and explanations',
                  'version': builtAt,
                  'content_hash': contentHash,
                  'pack_schema_version': schema,
                  'size': bytes.length,
                  'sha256': sha256.convert(bytes).toString(),
                  'url': '/v1/packs/files/gita_content_pack.sqlite',
                },
              ],
            }),
          ),
        ),
        200,
      );
    }
    if (r.url.path == '/v1/packs/files/gita_content_pack.sqlite') {
      final range = RegExp(r'bytes=(\d+)-').firstMatch(r.headers['Range'] ?? '');
      final start = range == null ? 0 : int.parse(range[1]!);
      var data = bytes.sublist(start);
      if (corrupt) {
        corrupt = false;
        data = Uint8List.fromList(data)..[data.length ~/ 2] ^= 0xff;
      }
      final drop = dropAfter;
      dropAfter = null;
      Stream<List<int>> stream() async* {
        if (drop != null) {
          yield data.sublist(0, drop);
          throw const SocketException('connection lost');
        }
        yield data;
      }

      return http.StreamedResponse(stream(), range == null ? 200 : 206);
    }
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), 404);
  });
}
