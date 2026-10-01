import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../db/user_database.dart';

/// Content-addressed audio cache: identical text + voice + provider + rate
/// is synthesized once. Files live in [directory]; the index lives in the
/// user database. Unpinned entries are evicted least-recently-used first
/// when the cache grows beyond [maxBytes].
class AudioCache {
  AudioCache({
    required this.directory,
    required this.db,
    this.maxBytes = 300 * 1024 * 1024,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Directory directory;
  final UserDatabase db;
  final int maxBytes;
  final DateTime Function() _clock;

  File fileFor(String hash, {String extension = 'wav'}) => File(p.join(directory.path, '$hash.$extension'));

  /// The cached file for [hash], or null. A missing file drops its index row.
  Future<File?> get(String hash) async {
    final row = await (db.select(db.audioCacheTable)..where((t) => t.hash.equals(hash))).getSingleOrNull();
    if (row == null) return null;
    final file = File(p.join(directory.path, row.fileName));
    if (!file.existsSync()) {
      await (db.delete(db.audioCacheTable)..where((t) => t.hash.equals(hash))).go();
      return null;
    }
    await (db.update(
      db.audioCacheTable,
    )..where((t) => t.hash.equals(hash))).write(AudioCacheTableCompanion(lastUsedAt: Value(_clock())));
    return file;
  }

  /// Registers [file] (already written inside [directory]) under [hash].
  Future<void> put(
    String hash,
    File file, {
    required String provider,
    required String voice,
    double? durationSeconds,
  }) async {
    final now = _clock();
    await db
        .into(db.audioCacheTable)
        .insertOnConflictUpdate(
          AudioCacheTableCompanion.insert(
            hash: hash,
            fileName: p.basename(file.path),
            bytes: file.lengthSync(),
            durationSeconds: Value(durationSeconds),
            provider: provider,
            voice: voice,
            createdAt: now,
            lastUsedAt: now,
          ),
        );
    await evict();
  }

  Future<void> setDuration(String hash, double seconds) => (db.update(
    db.audioCacheTable,
  )..where((t) => t.hash.equals(hash))).write(AudioCacheTableCompanion(durationSeconds: Value(seconds)));

  Future<double?> duration(String hash) async => (await (db.select(
    db.audioCacheTable,
  )..where((t) => t.hash.equals(hash))).getSingleOrNull())?.durationSeconds;

  Future<void> pin(String hash, {bool pinned = true}) => (db.update(
    db.audioCacheTable,
  )..where((t) => t.hash.equals(hash))).write(AudioCacheTableCompanion(pinned: Value(pinned)));

  Future<int> totalBytes() async {
    final sum = db.audioCacheTable.bytes.sum();
    return await (db.selectOnly(
      db.audioCacheTable,
    )..addColumns([sum])).map((r) => r.read(sum) ?? 0).getSingle();
  }

  /// Deletes least-recently-used unpinned files until under [maxBytes].
  Future<void> evict() async {
    var total = await totalBytes();
    if (total <= maxBytes) return;
    final candidates =
        await (db.select(db.audioCacheTable)
              ..where((t) => t.pinned.equals(false))
              ..orderBy([(t) => OrderingTerm.asc(t.lastUsedAt)]))
            .get();
    for (final row in candidates) {
      if (total <= maxBytes) break;
      final file = File(p.join(directory.path, row.fileName));
      if (file.existsSync()) file.deleteSync();
      await (db.delete(db.audioCacheTable)..where((t) => t.hash.equals(row.hash))).go();
      total -= row.bytes;
    }
  }
}
