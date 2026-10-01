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
  });

  final String id;
  final String kind;
  final String title;
  final String author;
  final String license;
  final bool isAiGenerated;
  final int? year;
  final String? url;
}

class Chapter {
  const Chapter({
    required this.number,
    required this.nameSa,
    required this.verseCount,
    required this.names,
    required this.titleEn,
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
