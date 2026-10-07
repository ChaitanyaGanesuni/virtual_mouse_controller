import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Which content pack is open.
class InstalledContent {
  const InstalledContent({required this.contentHash, required this.builtAt, required this.downloaded});

  final String contentHash;

  /// pack_meta built_at (ISO 8601): orders packs.
  final String builtAt;

  /// True if a downloaded content update is in use, not the bundled pack.
  final bool downloaded;
}

/// Installs the bundled content pack into app storage and opens it read-only.
///
/// The installed file is named after the pack's content hash, so a new app
/// version with new content installs side by side, switches over atomically,
/// and then removes the old pack. Nothing here needs the network.
///
/// A downloaded content update (core/packs/content_updates.dart) is used
/// instead when it was verified, has a supported schema and is newer than
/// the bundled pack; an app update with newer content wins over an older
/// download, which is then removed.
class ContentPackInstaller {
  ContentPackInstaller({required this.directory, required this.loadAsset});

  /// Where installed packs live (app support directory / content).
  final Directory directory;

  /// Loads a bundled asset by key (rootBundle.load in the app, files in tests).
  final Future<ByteData> Function(String key) loadAsset;

  static const packAsset = 'assets/content/gita_content_pack.sqlite';
  static const manifestAsset = 'assets/content/pack_manifest.json';
  static const supportedSchemaVersion = 3;

  /// Describes the downloaded update to use (written after verification).
  static const activeDownload = 'active_download.json';
  static const downloadPrefix = 'downloaded-';

  /// The pack opened by the last [install].
  InstalledContent? active;

  Future<Database> install() async {
    final manifest = jsonDecode(utf8.decode(_bytes(await loadAsset(manifestAsset)))) as Map<String, dynamic>;
    final schema = manifest['pack_schema_version'] as int;
    if (schema != supportedSchemaVersion) {
      throw StateError('content pack schema $schema is not supported (expected $supportedSchemaVersion)');
    }
    final hash = manifest['content_hash'] as String;
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, 'pack-${hash.substring(0, 16)}.sqlite'));

    if (!target.existsSync() || _installedHash(target) != hash) {
      final tmp = File('${target.path}.tmp');
      await tmp.writeAsBytes(_bytes(await loadAsset(packAsset)), flush: true);
      if (_installedHash(tmp) != hash) {
        await tmp.delete();
        throw StateError('bundled content pack does not match its manifest');
      }
      await tmp.rename(target.path);
    }

    for (final f in directory.listSync().whereType<File>()) {
      if (f.path != target.path && p.basename(f.path).startsWith('pack-')) {
        await f.delete();
      }
    }
    final bundledBuilt = _meta(target, 'built_at') ?? '';
    final download = _usableDownload(bundledBuilt);
    if (download != null) {
      active = InstalledContent(contentHash: download.$2, builtAt: download.$3, downloaded: true);
      return sqlite3.open(download.$1.path, mode: OpenMode.readOnly);
    }
    active = InstalledContent(contentHash: hash, builtAt: bundledBuilt, downloaded: false);
    return sqlite3.open(target.path, mode: OpenMode.readOnly);
  }

  /// The verified download to use, if newer than the bundled pack; stale or
  /// broken downloads are removed.
  (File, String, String)? _usableDownload(String bundledBuilt) {
    final marker = File(p.join(directory.path, activeDownload));
    (File, String, String)? found;
    if (marker.existsSync()) {
      try {
        final m = jsonDecode(marker.readAsStringSync()) as Map<String, dynamic>;
        final file = File(p.join(directory.path, p.basename(m['file'] as String)));
        final hash = m['content_hash'] as String;
        final built = m['built_at'] as String;
        if (m['pack_schema_version'] == supportedSchemaVersion &&
            file.existsSync() &&
            _installedHash(file) == hash &&
            _meta(file, 'built_at') == built &&
            built.compareTo(bundledBuilt) > 0) {
          found = (file, hash, built);
        }
      } on Object {
        found = null;
      }
      if (found == null) marker.deleteSync();
    }
    for (final f in directory.listSync().whereType<File>()) {
      final name = p.basename(f.path);
      if (name.startsWith(downloadPrefix) && !name.endsWith('.part') && f.path != found?.$1.path) {
        f.deleteSync();
      }
    }
    return found;
  }

  static String? _meta(File file, String key) {
    try {
      final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
      try {
        final rows = db.select('SELECT value FROM pack_meta WHERE key = ?', [key]);
        return rows.isEmpty ? null : rows.first['value'] as String;
      } finally {
        db.close();
      }
    } on SqliteException {
      return null;
    }
  }

  static String? _installedHash(File file) {
    try {
      final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
      try {
        final rows = db.select("SELECT value FROM pack_meta WHERE key = 'content_hash'");
        return rows.isEmpty ? null : rows.first['value'] as String;
      } finally {
        db.close();
      }
    } on SqliteException {
      return null; // corrupt or partial file: reinstall
    }
  }

  static Uint8List _bytes(ByteData data) => data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
