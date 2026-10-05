import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/core/content/content_pack.dart';
import 'package:path/path.dart' as p;

import 'support/pack.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('pack_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  ContentPackInstaller installer({Future<ByteData> Function(String)? load}) =>
      ContentPackInstaller(directory: dir, loadAsset: load ?? loadAssetFromDisk);

  test('installs the bundled pack and opens it read-only', () async {
    requirePack();
    final db = await installer().install();
    expect(db.select('SELECT count(*) AS n FROM verse').first['n'], 701);
    expect(() => db.execute("DELETE FROM verse WHERE id = '1.1'"), throwsA(anything));
    db.close();
    expect(
      dir.listSync().whereType<File>().where((f) => p.basename(f.path).startsWith('pack-')),
      hasLength(1),
    );
  });

  test('FTS5 is available in the bundled SQLite build', () async {
    final db = await installer().install();
    final rows = db.select("SELECT verse_id FROM verse_fts WHERE roman_loose MATCH 'phalesu'");
    expect(rows.map((r) => r['verse_id']), contains('2.47'));
    db.close();
  });

  test('reinstalling the same pack does not copy it again', () async {
    (await installer().install()).close();
    var copies = 0;
    final db = await installer(
      load: (key) {
        if (key == ContentPackInstaller.packAsset) copies++;
        return loadAssetFromDisk(key);
      },
    ).install();
    db.close();
    expect(copies, 0);
  });

  test('a corrupt installed pack is replaced; stale packs are removed', () async {
    (await installer().install()).close();
    final installed = dir.listSync().whereType<File>().single;
    installed.writeAsStringSync('garbage');
    File(p.join(dir.path, 'pack-0000000000000000.sqlite')).writeAsStringSync('old');
    final db = await installer().install();
    expect(db.select('SELECT count(*) AS n FROM verse').first['n'], 701);
    db.close();
    expect(dir.listSync().whereType<File>().map((f) => p.basename(f.path)), [p.basename(installed.path)]);
  });

  test('rejects a pack that does not match its manifest', () async {
    final other = File(p.join(dir.path, 'other.json'))
      ..writeAsStringSync('{"pack_schema_version": 3, "content_hash": "${'f' * 64}"}');
    Future<ByteData> load(String key) =>
        loadAssetFromDisk(key == ContentPackInstaller.manifestAsset ? other.path : key);
    await expectLater(installer(load: load).install(), throwsStateError);
  });

  test('rejects an unsupported pack schema', () async {
    final m = File(p.join(dir.path, 'm.json'))
      ..writeAsStringSync('{"pack_schema_version": 99, "content_hash": "x"}');
    Future<ByteData> load(String key) =>
        loadAssetFromDisk(key == ContentPackInstaller.manifestAsset ? m.path : key);
    await expectLater(installer(load: load).install(), throwsStateError);
  });
}
