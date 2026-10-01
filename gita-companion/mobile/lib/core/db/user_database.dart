import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

part 'user_database.g.dart';

/// The user's own data, stored on the device (local-first). Phase 3 holds
/// settings; bookmarks, notes, progress and revision tables arrive in Phase 8
/// as new tables with a schema migration.
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

@DriftDatabase(tables: [UserSettingsTable])
class UserDatabase extends _$UserDatabase {
  UserDatabase(super.e);

  factory UserDatabase.inDirectory(Directory dir) =>
      UserDatabase(NativeDatabase.createInBackground(File(p.join(dir.path, 'user.sqlite'))));

  factory UserDatabase.memory() => UserDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await into(userSettingsTable).insert(const UserSettingsTableCompanion());
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
