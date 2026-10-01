import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/core/audio/listening_progress.dart';
import 'package:gita_companion/core/db/user_database.dart';
import 'package:gita_companion/core/settings/app_settings.dart';
import 'package:sqlite3/sqlite3.dart';

Future<String> _settingsDdl() async {
  final fresh = UserDatabase.memory();
  final ddl =
      (await fresh.customSelect("SELECT sql FROM sqlite_master WHERE name = 'user_settings'").getSingle())
          .read<String>('sql');
  await fresh.close();
  return ddl;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('a v1 database (Phase 3) upgrades without losing settings', () async {
    // The v1 schema is today's user_settings table without the v2 and v3 columns.
    final v1Ddl = (await _settingsDdl()).replaceAll(RegExp(r',\s*"(voice_prefs|tutor_server)"[^,]*'), '');
    expect(v1Ddl, isNot(contains('voice_prefs')));
    expect(v1Ddl, isNot(contains('tutor_server')));

    final dir = Directory.systemTemp.createTempSync('migration');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/user.sqlite');
    final raw = sqlite3.open(file.path)
      ..execute(v1Ddl)
      ..execute(
        "INSERT INTO user_settings (id, ui_language, verse_script, onboarding_done) VALUES (1, 'te', 'sa-Telu', 1)",
      )
      ..execute('PRAGMA user_version = 1');
    raw.close();

    final db = UserDatabase(NativeDatabase(file));
    final settings = await DriftSettingsRepository(db).load();
    expect(settings.uiLanguage, 'te');
    expect(settings.onboardingDone, isTrue);
    expect(settings.voicePrefs, isEmpty);

    // New v2 tables are usable.
    final progress = ListeningProgressRepository(db);
    await progress.save(
      ListeningPosition(
        manifestId: 'chapter-2-en',
        audioChunkId: 'chapter-2-en/c0003',
        positionSeconds: 4.5,
        speed: 1.25,
        updatedAt: DateTime(2026, 10, 1),
        chapter: 2,
        verseId: '2.2',
      ),
    );
    expect((await progress.latest())!.verseId, '2.2');
    await DriftSettingsRepository(db).save(settings.copyWith(voicePrefs: {'te': 'v'}));
    expect((await DriftSettingsRepository(db).load()).voicePrefs, {'te': 'v'});
    await db.close();
  });

  test('a v2 database (Phase 5) gains the AI teacher server setting', () async {
    final v2Ddl = (await _settingsDdl()).replaceAll(RegExp(r',\s*"tutor_server"[^,]*'), '');
    final dir = Directory.systemTemp.createTempSync('migration');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/user.sqlite');
    sqlite3.open(file.path)
      ..execute(v2Ddl)
      ..execute("INSERT INTO user_settings (id, voice_prefs) VALUES (1, '{\"en\": \"v1\"}')")
      ..execute('PRAGMA user_version = 2')
      ..close();

    final db = UserDatabase(NativeDatabase(file));
    final repo = DriftSettingsRepository(db);
    final settings = await repo.load();
    expect(settings.voicePrefs, {'en': 'v1'});
    expect(settings.tutorServer, '');
    await repo.save(settings.copyWith(tutorServer: 'https://gita.example.org'));
    expect((await repo.load()).tutorServer, 'https://gita.example.org');
    await db.close();
  });

  test('listening progress rejects impossible values', () async {
    final db = UserDatabase.memory();
    addTearDown(db.close);
    expect(
      () => db.customStatement(
        'INSERT INTO listening_progress (manifest_id, audio_chunk_id, position_seconds, speed, updated_at) '
        "VALUES ('m', 'c', 1, 3.0, 0)",
      ),
      throwsA(anything),
    );
  });
}
