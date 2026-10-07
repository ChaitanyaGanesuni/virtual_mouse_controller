import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class DownloadException implements Exception {
  DownloadException(this.reason, [this.detail = '']);

  /// 'offline', 'server_error', 'corrupt', 'cancelled' or 'no_space'.
  final String reason;
  final String detail;

  @override
  String toString() => 'DownloadException($reason) $detail';
}

class CancelToken {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

/// Downloads one file, resuming an interrupted download from where it
/// stopped (HTTP Range on a `.part` file), and accepts it only if its size
/// and SHA-256 match the catalog.
class Downloader {
  Downloader(this._http);

  final http.Client _http;

  Future<File> download(
    Uri url,
    File dest, {
    required int size,
    required String sha256Hex,
    void Function(int received, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final part = File('${dest.path}.part');
    await dest.parent.create(recursive: true);
    var have = part.existsSync() ? part.lengthSync() : 0;
    if (have > size) {
      part.deleteSync();
      have = 0;
    }
    if (have < size) {
      final request = http.Request('GET', url);
      if (have > 0) request.headers['Range'] = 'bytes=$have-';
      http.StreamedResponse response;
      try {
        response = await _http.send(request);
      } on SocketException catch (e) {
        throw DownloadException('offline', e.message);
      } on http.ClientException catch (e) {
        throw DownloadException('offline', e.message);
      }
      if (response.statusCode == 200) {
        have = 0; // the server ignored the range: start over
      } else if (response.statusCode != 206) {
        throw DownloadException(
          response.statusCode == 429 ? 'rate_limited' : 'server_error',
          '${response.statusCode}',
        );
      }
      final sink = part.openWrite(mode: have == 0 ? FileMode.write : FileMode.append);
      try {
        await for (final block in response.stream) {
          if (cancel?.cancelled ?? false) throw DownloadException('cancelled');
          sink.add(block);
          have += block.length;
          onProgress?.call(have, size);
        }
      } on SocketException catch (e) {
        throw DownloadException('offline', e.message);
      } on http.ClientException catch (e) {
        throw DownloadException('offline', e.message);
      } on FileSystemException catch (e) {
        throw DownloadException('no_space', e.message);
      } finally {
        await sink.close();
      }
    }
    // Keep what arrived for a resume; only a complete, matching file counts.
    if (part.lengthSync() != size) {
      throw DownloadException('offline', 'incomplete: ${part.lengthSync()} of $size bytes');
    }
    final digest = await sha256.bind(part.openRead()).first;
    if (digest.toString() != sha256Hex) {
      part.deleteSync();
      throw DownloadException('corrupt', 'checksum mismatch');
    }
    return part.rename(dest.path);
  }
}
