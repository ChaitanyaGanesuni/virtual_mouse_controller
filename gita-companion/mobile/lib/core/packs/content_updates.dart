import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../content/content_pack.dart';
import 'downloader.dart';
import 'pack_catalog.dart';

enum ContentUpdateState {
  upToDate,
  updateAvailable,

  /// Downloaded and verified; used from the next app start.
  readyAfterRestart,

  /// The catalog's pack needs a newer app.
  needsAppUpdate,
}

/// Newer texts and explanations without a new app release: the catalog's
/// content pack is downloaded, verified (checksum, SQLite integrity, schema,
/// content hash), and marked for ContentPackInstaller to open next start.
class ContentUpdates {
  ContentUpdates({required this.directory, required this.downloader, required this.installed});

  /// Where the installer keeps packs (app support / content).
  final Directory directory;
  final Downloader downloader;
  final InstalledContent installed;

  File get _marker => File(p.join(directory.path, ContentPackInstaller.activeDownload));

  String? pendingHash() {
    if (!_marker.existsSync()) return null;
    try {
      return (jsonDecode(_marker.readAsStringSync()) as Map<String, dynamic>)['content_hash'] as String?;
    } on Object {
      return null;
    }
  }

  ContentUpdateState check(PackInfo pack) {
    if (pack.packSchemaVersion != ContentPackInstaller.supportedSchemaVersion) {
      return ContentUpdateState.needsAppUpdate;
    }
    if (pack.contentHash == installed.contentHash) return ContentUpdateState.upToDate;
    if (!installed.downloaded && pack.version.compareTo(installed.builtAt) <= 0) {
      return ContentUpdateState.upToDate; // the app already has newer content
    }
    if (pack.contentHash == pendingHash()) return ContentUpdateState.readyAfterRestart;
    return ContentUpdateState.updateAvailable;
  }

  Future<void> download(PackInfo pack, {void Function(int, int)? onProgress, CancelToken? cancel}) async {
    final hash = pack.contentHash!;
    final dest = File(
      p.join(directory.path, '${ContentPackInstaller.downloadPrefix}${hash.substring(0, 16)}.sqlite'),
    );
    await downloader.download(
      pack.url,
      dest,
      size: pack.size,
      sha256Hex: pack.sha256,
      onProgress: onProgress,
      cancel: cancel,
    );
    try {
      final db = sqlite3.open(dest.path, mode: OpenMode.readOnly);
      try {
        final meta = {
          for (final r in db.select('SELECT key, value FROM pack_meta'))
            r['key'] as String: r['value'] as String,
        };
        final ok = db.select('PRAGMA integrity_check').first.values.first == 'ok';
        if (!ok ||
            meta['content_hash'] != hash ||
            meta['pack_schema_version'] != '${ContentPackInstaller.supportedSchemaVersion}' ||
            meta['built_at'] != pack.version) {
          throw DownloadException('corrupt', 'pack does not match the catalog');
        }
      } finally {
        db.close();
      }
    } on SqliteException catch (e) {
      dest.deleteSync();
      throw DownloadException('corrupt', e.message);
    } on DownloadException {
      dest.deleteSync();
      rethrow;
    }
    final tmp = File('${_marker.path}.tmp');
    tmp.writeAsStringSync(
      jsonEncode({
        'file': p.basename(dest.path),
        'content_hash': hash,
        'built_at': pack.version,
        'pack_schema_version': ContentPackInstaller.supportedSchemaVersion,
      }),
    );
    tmp.renameSync(_marker.path);
  }
}
