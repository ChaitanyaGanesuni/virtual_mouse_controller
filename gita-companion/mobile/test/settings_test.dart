import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gita_companion/core/content/models.dart';
import 'package:gita_companion/core/db/user_database.dart';
import 'package:gita_companion/core/settings/app_settings.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('defaults on first run', () async {
    final db = UserDatabase.memory();
    final s = await DriftSettingsRepository(db).load();
    expect(s, const AppSettings());
    expect(s.onboardingDone, isFalse);
    await db.close();
  });

  test('settings round-trip; UI and content languages are independent', () async {
    final db = UserDatabase.memory();
    final repo = DriftSettingsRepository(db);
    const wanted = AppSettings(
      uiLanguage: 'en',
      verseScript: VerseScript.telugu,
      showTransliteration: false,
      translationLanguage: 'en',
      explanationLanguage: 'te',
      textScale: 1.3,
      themeMode: ThemeMode.dark,
      onboardingDone: true,
    );
    await repo.save(wanted);
    expect(await repo.load(), wanted);
    await db.close();
  });

  test('text scale is clamped', () {
    expect(const AppSettings().copyWith(textScale: 5).textScale, AppSettings.maxTextScale);
    expect(const AppSettings().copyWith(textScale: 0.1).textScale, AppSettings.minTextScale);
  });

  test('database rejects invalid values', () async {
    final db = UserDatabase.memory();
    await expectLater(
      db.customStatement("UPDATE user_settings SET verse_script = 'klingon'"),
      throwsA(anything),
    );
    await expectLater(db.customStatement('INSERT INTO user_settings (id) VALUES (2)'), throwsA(anything));
    await db.close();
  });
}
