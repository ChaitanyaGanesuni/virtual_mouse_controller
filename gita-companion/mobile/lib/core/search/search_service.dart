import 'package:sqlite3/sqlite3.dart';

import 'romanize.dart';

/// Where a search result matched, so the UI can say why it was shown.
enum MatchField { reference, sanskrit, transliteration, teluguScript, translation, explanation }

class SearchHit {
  const SearchHit({required this.verseId, required this.field, this.snippet});

  final String verseId;
  final MatchField field;

  /// Matched text with the hit wrapped in «…», when available.
  final String? snippet;
}

abstract interface class SearchService {
  List<SearchHit> search(String query, {int limit = 50});
}

/// Offline search over the content pack's FTS5 indexes:
///  1. verse references ("2.47", "BG 2:47", "2 47")
///  2. word/prefix search in Devanagari, Telugu script, IAST, loose romanisation,
///     and in translations and explanations
///  3. substring search inside long Sanskrit compounds (trigram index)
/// Meaning-based (semantic) search comes with the RAG service in Phase 7.
class SqliteSearchService implements SearchService {
  SqliteSearchService(this._db, {required this.verseExists});

  final Database _db;
  final bool Function(String id) verseExists;

  static final _ref = RegExp(
    r'^\s*(?:bg|gita|gītā)?\s*(\d{1,2})\s*[.:\-\s]\s*(\d{1,2})\s*$',
    caseSensitive: false,
  );
  static final _devanagari = RegExp('[ऀ-ॿ]');
  static final _telugu = RegExp('[ఀ-౿]');

  @override
  List<SearchHit> search(String query, {int limit = 50}) {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final ref = _ref.firstMatch(q);
    if (ref != null) {
      final id = '${int.parse(ref.group(1)!)}.${int.parse(ref.group(2)!)}';
      if (verseExists(id)) return [SearchHit(verseId: id, field: MatchField.reference)];
    }

    final hits = <String, SearchHit>{};
    void add(Iterable<SearchHit> found) {
      for (final h in found) {
        if (hits.length >= limit) return;
        hits.putIfAbsent(h.verseId, () => h);
      }
    }

    if (_devanagari.hasMatch(q)) {
      add(_fts('sanskrit', _phrase(q), MatchField.sanskrit));
      add(_sub('sanskrit', q.replaceAll(RegExp(r'\s+'), ''), MatchField.sanskrit));
    } else if (_telugu.hasMatch(q)) {
      add(_fts('telugu_script', _phrase(q), MatchField.teluguScript));
      add(_sub('telugu_script', q.replaceAll(RegExp(r'\s+'), ''), MatchField.teluguScript));
      add(_fts('explanation', _phrase(q), MatchField.explanation));
    } else {
      final folded = loose(q);
      if (folded.isNotEmpty) {
        // The folded column is an index artefact; the UI shows real IAST
        // instead of its snippet (see highlightIast).
        add(
          _fts(
            'roman_loose',
            _phrase(folded),
            MatchField.transliteration,
          ).map((h) => SearchHit(verseId: h.verseId, field: h.field)),
        );
        add(_sub('roman_loose', folded.replaceAll(' ', ''), MatchField.transliteration));
      }
      add(_fts('translation', _phrase(q), MatchField.translation));
      add(_fts('explanation', _phrase(q), MatchField.explanation));
    }
    return hits.values.toList();
  }

  /// An FTS5 query: every word must match; the last one as a prefix so
  /// results appear while typing. User text is quoted, never parsed as syntax.
  static String _phrase(String text) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) => w.replaceAll('"', ''));
    final quoted = words.where((w) => w.isNotEmpty).map((w) => '"$w"').toList();
    if (quoted.isEmpty) return '';
    quoted[quoted.length - 1] = '${quoted.last}*';
    return quoted.join(' ');
  }

  Iterable<SearchHit> _fts(String column, String match, MatchField field) {
    if (match.isEmpty) return const [];
    final col = _columns[column]!;
    final rows = _db.select(
      'SELECT verse_id, snippet(verse_fts, $col, \'«\', \'»\', \'…\', 12) AS snip '
      'FROM verse_fts WHERE $column MATCH ? ORDER BY bm25(verse_fts) LIMIT 100',
      [match],
    );
    return rows.map(
      (r) => SearchHit(verseId: r['verse_id'] as String, field: field, snippet: r['snip'] as String?),
    );
  }

  Iterable<SearchHit> _sub(String column, String needle, MatchField field) {
    // The trigram index needs at least three characters.
    if (needle.runes.length < 3) return const [];
    final rows = _db.select('SELECT verse_id FROM verse_fts_sub WHERE $column MATCH ? LIMIT 100', [
      '"${needle.replaceAll('"', '')}"',
    ]);
    return rows.map((r) => SearchHit(verseId: r['verse_id'] as String, field: field));
  }

  static const _columns = {
    'sanskrit': 1,
    'iast': 2,
    'roman_loose': 3,
    'telugu_script': 4,
    'translation': 5,
    'explanation': 6,
  };
}

/// Splits IAST [text] into (word, matches) pairs, marking words whose folded
/// form starts with one of the folded query words, so a search for
/// "phaleshu" highlights "phaleṣu".
List<(String, bool)> highlightIast(String text, String query) {
  final terms = loose(query).split(' ').where((t) => t.length >= 2).toList();
  final out = <(String, bool)>[];
  for (final m in RegExp(r'\S+|\s+').allMatches(text)) {
    final part = m.group(0)!;
    if (part.trim().isEmpty) {
      out.add((part, false));
      continue;
    }
    final f = loose(part).replaceAll(' ', '');
    out.add((part, f.isNotEmpty && terms.any((t) => f.startsWith(t.replaceAll(' ', '')))));
  }
  return out;
}
