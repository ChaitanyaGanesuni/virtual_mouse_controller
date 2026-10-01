/// Domain models for scripture content. These mirror the content pack
/// schema (content/schema/content_pack.sql) and carry provenance with every
/// piece of text so the UI can always show where text came from.
library;

/// How the Sanskrit verse text is displayed. Values are BCP-47 tags and match
/// `verse_text.language` in the content pack.
enum VerseScript {
  devanagari('sa'),
  telugu('sa-Telu'),
  iast('sa-Latn');

  const VerseScript(this.tag);
  final String tag;

  static VerseScript fromTag(String tag) => values.firstWhere((s) => s.tag == tag, orElse: () => devanagari);
}

enum ReviewStatus {
  unreviewed,
  pending,
  reviewed,
  rejected;

  static ReviewStatus parse(String value) =>
      values.firstWhere((s) => s.name == value, orElse: () => unreviewed);
}

class Source {
  const Source({
    required this.id,
    required this.kind,
    required this.title,
    required this.author,
    required this.license,
    required this.isAiGenerated,
    this.year,
    this.url,
    this.modelId,
    this.promptVersion,
  });

  final String id;
  final String kind;
  final String title;
  final String author;
  final String license;
  final bool isAiGenerated;
  final int? year;
  final String? url;

  /// For AI sources: the model and prompt version that produced the text.
  final String? modelId;
  final String? promptVersion;
}

/// Text attached to a chapter (summary or theme) with its provenance.
class ChapterText {
  const ChapterText({
    required this.kind,
    required this.language,
    required this.body,
    required this.sourceId,
    required this.reviewStatus,
  });

  final String kind;
  final String language;
  final String body;
  final String sourceId;
  final ReviewStatus reviewStatus;
}

class WordMeaning {
  const WordMeaning({
    required this.word,
    required this.meaning,
    required this.language,
    required this.sourceId,
  });

  /// The word as given by the source (IAST).
  final String word;
  final String meaning;
  final String language;
  final String sourceId;
}

/// Explanation modes shown on the verse screen, in display order. The value
/// is the `verse_text.kind` in the content pack.
enum ExplanationMode {
  simple('simple'),
  deep('deep'),
  practical('practical'),
  story('story'),
  child('child'),
  sanskritTerms('sanskrit_terms');

  const ExplanationMode(this.kind);
  final String kind;
}

class Chapter {
  const Chapter({
    required this.number,
    required this.nameSa,
    required this.verseCount,
    required this.names,
    required this.titleEn,
    this.texts = const [],
  });

  final int number;

  /// Sanskrit name in Devanagari, e.g. साङ्ख्ययोग.
  final String nameSa;

  /// Canonical verse count (standard 700-verse numbering).
  final int verseCount;

  /// Sanskrit name in other scripts, keyed by script tag ('sa-Latn', 'sa-Telu').
  final Map<String, String> names;

  /// Plain-English gloss of the name (project editorial text).
  final String titleEn;

  /// Summaries and themes from every available source and language.
  final List<ChapterText> texts;

  String nameIn(VerseScript script) =>
      script == VerseScript.devanagari ? nameSa : (names[script.tag] ?? nameSa);
}

class Speaker {
  const Speaker({required this.id, required this.nameEn, required this.lines});

  final String id;
  final String nameEn;

  /// "X uvāca" heading by script tag ('sa', 'sa-Latn', 'sa-Telu').
  final Map<String, String> lines;
}

class VerseText {
  const VerseText({
    required this.id,
    required this.kind,
    required this.language,
    required this.body,
    required this.sourceId,
    required this.reviewStatus,
  });

  final String id;
  final String kind;
  final String language;
  final String body;
  final String sourceId;
  final ReviewStatus reviewStatus;
}

class Verse {
  const Verse({
    required this.id,
    required this.chapter,
    required this.verse,
    required this.isCanonical,
    required this.sanskrit,
    required this.sourceId,
    required this.reviewStatus,
    this.speaker,
    this.texts = const [],
    this.wordMeanings = const [],
  });

  /// '2.47'
  final String id;
  final int chapter;
  final int verse;

  /// False only for 13.0 (present in some editions, outside the 700).
  final bool isCanonical;

  /// Devanagari, one half-verse per line.
  final String sanskrit;
  final String sourceId;
  final ReviewStatus reviewStatus;
  final Speaker? speaker;
  final List<VerseText> texts;
  final List<WordMeaning> wordMeanings;

  /// The verse text in the requested script (Devanagari or a transliteration).
  String textIn(VerseScript script) {
    if (script == VerseScript.devanagari) return sanskrit;
    return texts
            .where((t) => t.kind == 'transliteration' && t.language == script.tag)
            .map((t) => t.body)
            .firstOrNull ??
        sanskrit;
  }

  List<VerseText> textsOfKind(String kind) => texts.where((t) => t.kind == kind).toList();
}

/// Picks the text to show from several sources: the requested language
/// first, then reviewed over unreviewed, then human-written over AI.
/// Returns null if nothing is available in any language.
T? pickText<T>(
  List<T> candidates, {
  required String language,
  required String Function(T) languageOf,
  required ReviewStatus Function(T) statusOf,
  required bool Function(T) isAi,
}) {
  if (candidates.isEmpty) return null;
  int score(T t) =>
      (languageOf(t) == language ? 100 : 0) +
      (statusOf(t) == ReviewStatus.reviewed ? 10 : 0) +
      (statusOf(t) == ReviewStatus.rejected ? -1000 : 0) +
      (isAi(t) ? 0 : 1);
  final sorted = [...candidates]..sort((a, b) => score(b).compareTo(score(a)));
  return score(sorted.first) < 0 ? null : sorted.first;
}
