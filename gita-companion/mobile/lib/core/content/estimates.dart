import 'models.dart';

/// Estimated reading and listening time for a chapter.
///
/// These are estimates, shown as "about N min":
/// - Reading: ~20 seconds to read a verse and its transliteration, plus the
///   selected explanation at 200 words per minute when one exists.
/// - Listening: Sanskrit recitation at ~0.45 s per syllable (a calm pace;
///   an anuṣṭubh verse of 32 syllables takes ~15 s), plus explanations read
///   aloud at 150 words per minute.
class ChapterEstimate {
  const ChapterEstimate({required this.readingMinutes, required this.listeningMinutes});

  final int readingMinutes;
  final int listeningMinutes;
}

const _secondsPerVerseReading = 20.0;
const _readingWpm = 200.0;
const _speakingWpm = 150.0;
const _secondsPerSyllable = 0.45;

// IAST vowels (each is the nucleus of one syllable). Long/diphthong forms
// first so "ai"/"au" count once.
final _vowel = RegExp('ai|au|ā|ī|ū|ṝ|ṛ|ḹ|ḷ|a|i|u|e|o', caseSensitive: false);

int syllables(String iast) => _vowel.allMatches(iast.replaceAll(RegExp(r"[।॥|']"), '')).length;

ChapterEstimate estimateChapter(List<Verse> verses, {required String explanationLanguage}) {
  var readS = 0.0;
  var listenS = 0.0;
  for (final v in verses) {
    readS += _secondsPerVerseReading;
    final iast = v.textIn(VerseScript.iast);
    listenS += syllables(iast) * _secondsPerSyllable;
    final simple = v.texts.where((t) => t.kind == 'simple' && t.language == explanationLanguage).firstOrNull;
    if (simple != null) {
      final words = simple.body.split(RegExp(r'\s+')).length;
      readS += words / _readingWpm * 60;
      listenS += words / _speakingWpm * 60;
    }
  }
  int mins(double s) => s <= 0 ? 0 : (s / 60).ceil();
  return ChapterEstimate(readingMinutes: mins(readS), listeningMinutes: mins(listenS));
}
