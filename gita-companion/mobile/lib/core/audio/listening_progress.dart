import 'package:drift/drift.dart';

import '../db/user_database.dart';

class ListeningPosition {
  const ListeningPosition({
    required this.manifestId,
    required this.audioChunkId,
    required this.positionSeconds,
    required this.speed,
    required this.updatedAt,
    this.chapter,
    this.verseId,
    this.completed = false,
  });

  final String manifestId;
  final int? chapter;
  final String? verseId;
  final String audioChunkId;
  final double positionSeconds;
  final double speed;
  final bool completed;
  final DateTime updatedAt;
}

/// Persists where listening stopped (chapterId, verseId, audioChunkId,
/// positionSeconds) so playback resumes after the app is closed.
class ListeningProgressRepository {
  ListeningProgressRepository(this._db);

  final UserDatabase _db;

  Future<void> save(ListeningPosition p) => _db
      .into(_db.listeningProgressTable)
      .insertOnConflictUpdate(
        ListeningProgressTableCompanion.insert(
          manifestId: p.manifestId,
          chapter: Value(p.chapter),
          verseId: Value(p.verseId),
          audioChunkId: p.audioChunkId,
          positionSeconds: Value(p.positionSeconds),
          speed: Value(p.speed),
          completed: Value(p.completed),
          updatedAt: p.updatedAt,
        ),
      );

  Future<ListeningPosition?> load(String manifestId) async {
    final r = await (_db.select(
      _db.listeningProgressTable,
    )..where((t) => t.manifestId.equals(manifestId))).getSingleOrNull();
    return r == null ? null : _from(r);
  }

  /// The most recently updated unfinished position ("Continue listening").
  Future<ListeningPosition?> latest() async {
    final r =
        await (_db.select(_db.listeningProgressTable)
              ..where((t) => t.completed.equals(false))
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
              ..limit(1))
            .getSingleOrNull();
    return r == null ? null : _from(r);
  }

  ListeningPosition _from(ListeningProgressTableData r) => ListeningPosition(
    manifestId: r.manifestId,
    chapter: r.chapter,
    verseId: r.verseId,
    audioChunkId: r.audioChunkId,
    positionSeconds: r.positionSeconds,
    speed: r.speed,
    completed: r.completed,
    updatedAt: r.updatedAt,
  );
}
