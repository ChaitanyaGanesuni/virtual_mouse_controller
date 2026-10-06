import 'package:drift/drift.dart';

/// "My Gita" study data (schema v4, Phase 8). Mirrors the server tables
/// (backend app/modules/study, practice, progress) so it can be synced.
///
/// Conventions shared by every table:
/// - times are UTC milliseconds since the epoch (sync compares them, and
///   drift's DateTime columns only keep whole seconds);
/// - `updatedAt` is when the user made the change on this device; sync
///   resolves conflicts by it (last write wins);
/// - `dirty` = changed here and not yet sent to the server;
/// - deleting sets `deleted` (a tombstone), so other devices learn of it.
///
/// Rows are identified like on the server: by natural key where there is
/// only one (a bookmark per verse), by a random UUID where there are many.

class BookmarksTable extends Table {
  @override
  String get tableName => 'bookmark';

  TextColumn get verseId => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {verseId};
}

class VerseStatesTable extends Table {
  @override
  String get tableName => 'verse_state';

  TextColumn get verseId => text()();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  BoolColumn get understood => boolean().withDefault(const Constant(false))();
  BoolColumn get needsRevision => boolean().withDefault(const Constant(false))();
  IntColumn get updatedAt => integer()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {verseId};
}

/// A character range in one rendered text of a verse: `textId` is the
/// content pack's verse_text id (the same id on the server), or null for the
/// Sanskrit.
class HighlightsTable extends Table {
  @override
  String get tableName => 'highlight';

  TextColumn get id => text()();
  TextColumn get verseId => text()();
  TextColumn get textId => text().nullable()();
  IntColumn get start => integer()();
  IntColumn get end => integer()();
  TextColumn get color => text().withDefault(const Constant('gold'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK ("start" >= 0 AND "end" > "start")',
    "CHECK (color IN ('gold', 'green', 'blue', 'pink'))",
  ];
}

/// Notes, questions (to ask the teacher or revisit) and reflections.
class NotesTable extends Table {
  @override
  String get tableName => 'note';

  TextColumn get id => text()();
  TextColumn get verseId => text().nullable()();
  IntColumn get chapter => integer().nullable()();
  TextColumn get kind => text().withDefault(const Constant('note'))();
  TextColumn get body => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (kind IN ('note', 'question', 'reflection'))",
    'CHECK (verse_id IS NULL OR chapter IS NULL)',
  ];
}

/// A spaced-repetition card (see core/study/srs.dart).
class RevisionItemsTable extends Table {
  @override
  String get tableName => 'revision_item';

  TextColumn get verseId => text()();
  TextColumn get cardType => text()();
  TextColumn get state => text().withDefault(const Constant('new'))();
  IntColumn get step => integer().withDefault(const Constant(0))();
  IntColumn get dueAt => integer()();
  IntColumn get reps => integer().withDefault(const Constant(0))();
  IntColumn get lapses => integer().withDefault(const Constant(0))();
  IntColumn get lastReviewedAt => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {verseId, cardType};

  @override
  List<String> get customConstraints => [
    "CHECK (card_type IN ('meaning', 'concept', 'application'))",
    "CHECK (state IN ('new', 'learning', 'review', 'relearning', 'suspended'))",
  ];
}

/// Append-only log of reviews (1 again, 2 hard, 3 good, 4 easy).
class RevisionReviewsTable extends Table {
  @override
  String get tableName => 'revision_review';

  TextColumn get id => text()();
  TextColumn get verseId => text()();
  TextColumn get cardType => text()();
  IntColumn get rating => integer()();
  IntColumn get reviewedAt => integer()();
  RealColumn get elapsedDays => real().nullable()();
  RealColumn get scheduledDays => real().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (rating BETWEEN 1 AND 4)'];
}

/// Daily Practice: listen → understand → reflect → apply → journal, one row
/// per local date ('2026-10-06').
class DailyPracticesTable extends Table {
  @override
  String get tableName => 'daily_practice';

  TextColumn get date => text()();
  TextColumn get verseId => text()();
  IntColumn get listenedAt => integer().nullable()();
  IntColumn get understoodAt => integer().nullable()();
  IntColumn get reflectedAt => integer().nullable()();
  IntColumn get appliedAt => integer().nullable()();

  /// Private. Leaves the device only if the user turns on journal sync.
  TextColumn get journal => text().withDefault(const Constant(''))();
  IntColumn get updatedAt => integer()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {date};
}

/// Which verses have been opened in the reader. Merged on sync (earliest
/// first read, latest last read, highest count), never overwritten.
class VersesReadTable extends Table {
  @override
  String get tableName => 'verse_read';

  TextColumn get verseId => text()();
  IntColumn get firstReadAt => integer()();
  IntColumn get lastReadAt => integer()();
  IntColumn get readCount => integer().withDefault(const Constant(1))();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {verseId};
}

/// Where the reader was last, per chapter ("Continue learning").
class ReadingProgressTable extends Table {
  @override
  String get tableName => 'reading_progress';

  IntColumn get chapter => integer()();
  TextColumn get lastVerseId => text()();
  IntColumn get updatedAt => integer()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {chapter};
}

/// Sync settings and position (single row).
class SyncStateTable extends Table {
  @override
  String get tableName => 'sync_state';

  IntColumn get id => integer().withDefault(const Constant(1))();
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();
  BoolColumn get includeJournal => boolean().withDefault(const Constant(false))();

  /// Journal sync was turned off: erase the journals from the server on the
  /// next sync.
  BoolColumn get eraseJournal => boolean().withDefault(const Constant(false))();

  /// The server's cursor after the last completed pull.
  IntColumn get cursor => integer().withDefault(const Constant(0))();

  /// The account the cursor belongs to; a different account resets it.
  TextColumn get accountId => text().nullable()();
  IntColumn get lastSyncAt => integer().nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (id = 1)'];
}
