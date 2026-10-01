import 'package:drift/drift.dart';
import 'package:flutter/material.dart';

import '../content/models.dart';
import '../db/user_database.dart';

/// Reading and display preferences. UI language and content languages are
/// independent: e.g. UI in English, verses in Telugu script, explanations
/// in Telugu.
@immutable
class AppSettings {
  const AppSettings({
    this.uiLanguage = 'en',
    this.verseScript = VerseScript.devanagari,
    this.showTransliteration = true,
    this.translationLanguage = 'en',
    this.explanationLanguage = 'en',
    this.textScale = 1.0,
    this.themeMode = ThemeMode.system,
    this.onboardingDone = false,
  });

  static const supportedLanguages = ['en', 'te'];
  static const minTextScale = 0.85;
  static const maxTextScale = 1.6;

  final String uiLanguage;
  final VerseScript verseScript;
  final bool showTransliteration;
  final String translationLanguage;
  final String explanationLanguage;
  final double textScale;
  final ThemeMode themeMode;
  final bool onboardingDone;

  Locale get locale => Locale(uiLanguage);

  AppSettings copyWith({
    String? uiLanguage,
    VerseScript? verseScript,
    bool? showTransliteration,
    String? translationLanguage,
    String? explanationLanguage,
    double? textScale,
    ThemeMode? themeMode,
    bool? onboardingDone,
  }) => AppSettings(
    uiLanguage: uiLanguage ?? this.uiLanguage,
    verseScript: verseScript ?? this.verseScript,
    showTransliteration: showTransliteration ?? this.showTransliteration,
    translationLanguage: translationLanguage ?? this.translationLanguage,
    explanationLanguage: explanationLanguage ?? this.explanationLanguage,
    textScale: (textScale ?? this.textScale).clamp(minTextScale, maxTextScale),
    themeMode: themeMode ?? this.themeMode,
    onboardingDone: onboardingDone ?? this.onboardingDone,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.uiLanguage == uiLanguage &&
      other.verseScript == verseScript &&
      other.showTransliteration == showTransliteration &&
      other.translationLanguage == translationLanguage &&
      other.explanationLanguage == explanationLanguage &&
      other.textScale == textScale &&
      other.themeMode == themeMode &&
      other.onboardingDone == onboardingDone;

  @override
  int get hashCode => Object.hash(
    uiLanguage,
    verseScript,
    showTransliteration,
    translationLanguage,
    explanationLanguage,
    textScale,
    themeMode,
    onboardingDone,
  );
}

abstract interface class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._db);

  final UserDatabase _db;

  @override
  Future<AppSettings> load() async {
    final row = await (_db.select(_db.userSettingsTable)..where((t) => t.id.equals(1))).getSingle();
    return AppSettings(
      uiLanguage: AppSettings.supportedLanguages.contains(row.uiLanguage) ? row.uiLanguage : 'en',
      verseScript: VerseScript.fromTag(row.verseScript),
      showTransliteration: row.showTransliteration,
      translationLanguage: row.translationLanguage,
      explanationLanguage: row.explanationLanguage,
      textScale: row.textScale.clamp(AppSettings.minTextScale, AppSettings.maxTextScale),
      themeMode: ThemeMode.values.firstWhere((m) => m.name == row.theme, orElse: () => ThemeMode.system),
      onboardingDone: row.onboardingDone,
    );
  }

  @override
  Future<void> save(AppSettings s) async {
    await (_db.update(_db.userSettingsTable)..where((t) => t.id.equals(1))).write(
      UserSettingsTableCompanion(
        uiLanguage: Value(s.uiLanguage),
        verseScript: Value(s.verseScript.tag),
        showTransliteration: Value(s.showTransliteration),
        translationLanguage: Value(s.translationLanguage),
        explanationLanguage: Value(s.explanationLanguage),
        textScale: Value(s.textScale),
        theme: Value(s.themeMode.name),
        onboardingDone: Value(s.onboardingDone),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
