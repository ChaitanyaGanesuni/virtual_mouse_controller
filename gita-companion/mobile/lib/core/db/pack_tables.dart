import 'package:drift/drift.dart';

/// Downloads for offline use (schema v5, Phase 9).

/// One row per downloadable item: the content update ('content') or a
/// chapter's audio ('audio-chapter-2-en'). States follow the design:
/// not_downloaded → queued → downloading → downloaded | failed, and
/// update_available is derived by comparing [fingerprint] with what the
/// catalog or the current content would produce.
class OfflinePacksTable extends Table {
  @override
  String get tableName => 'offline_pack';

  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get state => text()();

  /// Progress: items (audio chunks) or bytes (content) done of [total].
  IntColumn get done => integer().withDefault(const Constant(0))();
  IntColumn get total => integer().withDefault(const Constant(0))();

  /// Bytes on disk once downloaded.
  IntColumn get bytes => integer().withDefault(const Constant(0))();

  /// What was downloaded: the content pack's hash, or a hash of the audio
  /// manifest's texts. A different current value means an update exists.
  TextColumn get fingerprint => text().withDefault(const Constant(''))();
  TextColumn get error => text().nullable()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (kind IN ('content', 'audio'))",
    "CHECK (state IN ('queued', 'downloading', 'downloaded', 'failed'))",
  ];
}

/// The cached audio files an audio pack pinned (so removing the pack
/// unpins only files no other pack needs).
class OfflinePackFilesTable extends Table {
  @override
  String get tableName => 'offline_pack_file';

  TextColumn get packId => text()();
  TextColumn get hash => text()();

  @override
  Set<Column<Object>> get primaryKey => {packId, hash};
}
