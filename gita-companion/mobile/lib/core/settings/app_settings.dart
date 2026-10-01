import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show mapEquals;
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
    this.voicePrefs = const {},
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

  /// Preferred TTS voice per language ('en', 'te', 'sa') → voice id.
  final Map<String, String> voicePrefs;

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
    Map<String, String>? voicePrefs,
  }) => AppSettings(
    uiLanguage: uiLanguage ?? this.uiLanguage,
    verseScript: verseScript ?? this.verseScript,
    showTransliteration: showTransliteration ?? this.showTransliteration,
    translationLanguage: translationLanguage ?? this.translationLanguage,
    explanationLanguage: explanationLanguage ?? this.explanationLanguage,
    textScale: (textScale ?? this.textScale).clamp(minTextScale, maxTextScale),
    themeMode: themeMode ?? this.themeMode,
    onboardingDone: onboardingDone ?? this.onboardingDone,
    voicePrefs: voicePrefs ?? this.voicePrefs,
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
      other.onboardingDone == onboardingDone &&
      mapEquals(other.voicePrefs, voicePrefs);

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
    Object.hashAllUnordered(voicePrefs.entries.map((e) => '${e.key}=${e.value}')),
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
      voicePrefs: _decodeVoices(row.voicePrefs),
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
        voicePrefs: Value(jsonEncode(s.voicePrefs)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}

Map<String, String> _decodeVoices(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map) return {for (final e in decoded.entries) e.key.toString(): e.value.toString()};
  } on FormatException {
    // fall through: corrupt preference means "no preference"
  }
  return const {};
}
