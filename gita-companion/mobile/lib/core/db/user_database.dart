import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

part 'user_database.g.dart';

/// The user's own data, stored on the device (local-first).
/// v1 (Phase 3): settings. v2 (Phase 5): voice preferences, listening
/// progress, audio cache index. v3 (Phase 6): AI teacher server address. Bookmarks, notes and revision come in Phase 8.
///
/// Mirrors backend `user_settings` so the two can be synced.
class UserSettingsTable extends Table {
  @override
  String get tableName => 'user_settings';

  /// Single-row table.
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get uiLanguage => text().withDefault(const Constant('en'))();
  TextColumn get verseScript => text().withDefault(const Constant('sa'))();
  BoolColumn get showTransliteration => boolean().withDefault(const Constant(true))();
  TextColumn get translationLanguage => text().withDefault(const Constant('en'))();
  TextColumn get explanationLanguage => text().withDefault(const Constant('en'))();
  RealColumn get textScale => real().withDefault(const Constant(1.0))();
  TextColumn get theme => text().withDefault(const Constant('system'))();
  BoolColumn get onboardingDone => boolean().withDefault(const Constant(false))();

  /// JSON `{"en": "<voice id>", "te": ..., "sa": ...}` (v2).
  TextColumn get voicePrefs => text().withDefault(const Constant('{}'))();

  /// AI teacher server address chosen by the user; empty = the address built
  /// into the app (v3).
  TextColumn get tutorServer => text().withDefault(const Constant(''))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (id = 1)',
    "CHECK (verse_script IN ('sa', 'sa-Latn', 'sa-Telu'))",
    "CHECK (theme IN ('system', 'light', 'dark'))",
    'CHECK (text_scale BETWEEN 0.75 AND 2.5)',
  ];
}

/// Where playback stopped, per manifest, so listening resumes after the app
/// is closed. Mirrors backend `listening_progress`.
class ListeningProgressTable extends Table {
  @override
  String get tableName => 'listening_progress';

  TextColumn get manifestId => text()();
  IntColumn get chapter => integer().nullable()();
  TextColumn get verseId => text().nullable()();
  TextColumn get audioChunkId => text()();
  RealColumn get positionSeconds => real().withDefault(const Constant(0))();
  RealColumn get speed => real().withDefault(const Constant(1.0))();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {manifestId};

  @override
  List<String> get customConstraints => [
    'CHECK (position_seconds >= 0)',
    'CHECK (speed IN (0.75, 1.0, 1.25, 1.5, 1.75, 2.0))',
  ];
}

/// Index of synthesized audio files, keyed by content hash.
class AudioCacheTable extends Table {
  @override
  String get tableName => 'audio_cache';

  TextColumn get hash => text()();
  TextColumn get fileName => text()();
  IntColumn get bytes => integer()();
  RealColumn get durationSeconds => real().nullable()();
  TextColumn get provider => text()();
  TextColumn get voice => text()();

  /// Pinned files (downloaded for offline use) are never evicted.
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastUsedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {hash};

  @override
  List<String> get customConstraints => ['CHECK (length(hash) = 64)', 'CHECK (bytes >= 0)'];
}

@DriftDatabase(tables: [UserSettingsTable, ListeningProgressTable, AudioCacheTable])
class UserDatabase extends _$UserDatabase {
  UserDatabase(super.e);

  factory UserDatabase.inDirectory(Directory dir) =>
      UserDatabase(NativeDatabase.createInBackground(File(p.join(dir.path, 'user.sqlite'))));

  factory UserDatabase.memory() => UserDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await into(userSettingsTable).insert(const UserSettingsTableCompanion());
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(userSettingsTable, userSettingsTable.voicePrefs);
        await m.createTable(listeningProgressTable);
        await m.createTable(audioCacheTable);
      }
      if (from < 3) {
        await m.addColumn(userSettingsTable, userSettingsTable.tutorServer);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
