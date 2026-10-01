import 'dart:io';
import 'dart:typed_data';

import 'package:gita_companion/core/content/sqlite_content_repository.dart';
import 'package:sqlite3/sqlite3.dart';

/// The real content pack, built by tool/sync_content.sh (CI runs it first).
const packPath = 'assets/content/gita_content_pack.sqlite';
const manifestPath = 'assets/content/pack_manifest.json';

File requirePack() {
  final f = File(packPath);
  if (!f.existsSync()) {
    throw StateError('Content pack missing. Run tool/sync_content.sh before flutter test.');
  }
  return f;
}

SqliteContentRepository openRealRepository() =>
    SqliteContentRepository(sqlite3.open(requirePack().path, mode: OpenMode.readOnly));

/// Asset loader for ContentPackInstaller that reads the files from disk.
Future<ByteData> loadAssetFromDisk(String key) async {
  final bytes = await File(key).readAsBytes();
  return ByteData.sublistView(bytes);
}
