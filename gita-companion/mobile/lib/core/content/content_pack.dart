import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Installs the bundled content pack into app storage and opens it read-only.
///
/// The installed file is named after the pack's content hash, so a new app
/// version with new content installs side by side, switches over atomically,
/// and then removes the old pack. Nothing here needs the network.
class ContentPackInstaller {
  ContentPackInstaller({required this.directory, required this.loadAsset});

  /// Where installed packs live (app support directory / content).
  final Directory directory;

  /// Loads a bundled asset by key (rootBundle.load in the app, files in tests).
  final Future<ByteData> Function(String key) loadAsset;

  static const packAsset = 'assets/content/gita_content_pack.sqlite';
  static const manifestAsset = 'assets/content/pack_manifest.json';
  static const supportedSchemaVersion = 1;

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
    return sqlite3.open(target.path, mode: OpenMode.readOnly);
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
