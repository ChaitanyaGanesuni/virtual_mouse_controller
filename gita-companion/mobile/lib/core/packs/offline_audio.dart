import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../audio/audio_cache.dart';
import '../audio/manifest.dart';
import '../audio/manifest_resolver.dart';
import '../audio/synthesizer.dart';
import '../db/user_database.dart';
import 'downloader.dart';

/// A chapter's audio (each verse recited, then its simple explanation),
/// synthesized ahead on the phone and pinned in the audio cache, so it plays
/// with no network and is never evicted. Removing it unpins only files no
/// other download needs.
class OfflineAudio {
  OfflineAudio({required this.db, required this.cache, required this.synthesizer, required this.resolver});

  final UserDatabase db;
  final AudioCache cache;
  final AudioSynthesizer synthesizer;
  final ManifestResolver resolver;

  static String packId(int chapter, String language) => 'audio-chapter-$chapter-$language';

  static (int, String)? parse(String id) {
    final m = RegExp(r'^audio-chapter-(\d+)-([a-z]+)$').firstMatch(id);
    return m == null ? null : (int.parse(m[1]!), m[2]!);
  }

  AudioManifest manifest(int chapter, String language) => resolver.chapter(chapter, language);

  /// Changes when the chapter's texts change (e.g. after a content update).
  static String fingerprint(AudioManifest m) => sha256
      .convert(utf8.encode(m.chunks.map((c) => '${c.language}|${c.rate}|${c.text}').join('\n')))
      .toString();

  /// Synthesizes and pins every chunk. Already-cached chunks cost nothing,
  /// so an interrupted download continues where it stopped.
  Future<int> download(
    int chapter,
    String language, {
    void Function(int done, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final id = packId(chapter, language);
    final chunks = manifest(chapter, language).chunks;
    var bytes = 0;
    for (var i = 0; i < chunks.length; i++) {
      if (cancel?.cancelled ?? false) throw DownloadException('cancelled');
      final r = await synthesizer.fileFor(chunks[i]);
      await cache.pin(r.hash);
      await db
          .into(db.offlinePackFilesTable)
          .insert(
            OfflinePackFilesTableCompanion.insert(packId: id, hash: r.hash),
            mode: InsertMode.insertOrIgnore,
          );
      bytes += r.file.lengthSync();
      onProgress?.call(i + 1, chunks.length);
    }
    return bytes;
  }

  /// All pinned files are still there.
  Future<bool> intact(String id) async {
    final hashes = await _hashes(id);
    for (final h in hashes) {
      if (await cache.get(h) == null) return false;
    }
    return hashes.isNotEmpty;
  }

  Future<List<String>> _hashes(String id) async => [
    for (final r in await (db.select(db.offlinePackFilesTable)..where((t) => t.packId.equals(id))).get())
      r.hash,
  ];

  Future<void> remove(String id) async {
    final mine = await _hashes(id);
    await (db.delete(db.offlinePackFilesTable)..where((t) => t.packId.equals(id))).go();
    final stillNeeded = {
      for (final r in await (db.select(db.offlinePackFilesTable)..where((t) => t.hash.isIn(mine))).get())
        r.hash,
    };
    for (final h in mine.where((h) => !stillNeeded.contains(h))) {
      await cache.pin(h, pinned: false);
    }
    await cache.evict();
  }
}
