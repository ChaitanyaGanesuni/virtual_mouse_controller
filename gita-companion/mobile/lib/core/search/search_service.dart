import 'dart:math' as math;

import 'package:sqlite3/sqlite3.dart';

import 'concepts.dart';
import 'romanize.dart';

/// Where a search result matched, so the UI can say why it was shown.
enum MatchField {
  reference,
  sanskrit,
  transliteration,
  teluguScript,
  translation,
  explanation,

  /// Found through the concept index ("Related to: Anger").
  concept,

  /// Found through keywords of a question, not as typed.
  keywords,
}

class SearchHit {
  const SearchHit({required this.verseId, required this.field, this.snippet, this.concepts = const []});

  final String verseId;
  final MatchField field;

  /// Matched text with the hit wrapped in «…», when available.
  final String? snippet;

  /// Concepts of the query this verse is linked to (concept ids).
  final List<String> concepts;
}

abstract interface class SearchService {
  List<SearchHit> search(String query, {int limit = 50});

  /// Verses of one concept, best first (topic browsing).
  List<SearchHit> topic(String conceptId, {int limit = 50});

  /// All concepts, for browsing by topic.
  List<ConceptEntry> topics();

  /// Concepts the query is directly about.
  List<ConceptEntry> conceptsOf(String query);
}

/// Offline search over the content pack. Mirrors the server's retriever
/// (content/gita_content/retrieval.py); constants must stay in step:
///  - explicit references ("2.47", "chapter 2 verse 47"); a query that is
///    only a reference jumps straight to the verse;
///  - concepts: the query's words matched to the concept index, scored by each
///    concept's verse weights, smoothed over neighbouring verses;
///  - keywords: BM25 over the stemmed English text (`english_stem`), the
///    loose romanisation and Telugu text, plus Sanskrit typed in Roman
///    letters found inside long compounds;
///  - literal: word/prefix search as typed, in every script, so results appear
///    while typing.
/// The rankings are fused with Reciprocal Rank Fusion.
class SqliteSearchService implements SearchService {
  SqliteSearchService(this._db, {required this.verseExists});

  final Database _db;
  final bool Function(String id) verseExists;

  static const rrfK = 60;
  static const lexicalWeightWithConcepts = 0.5;
  static const passageSmoothing = 0.5;
  static const expansionWeight = 0.5;
  static const sanskritWeight = 1.5;
  static const minSanskritToken = 5;
  static const _channelWeights = {'explicit': 2.0, 'concept': 1.0, 'lexical': 1.0, 'literal': 1.0};

  late final ConceptIndex concepts = ConceptIndex.fromDb(_db);
  late final Set<String> _stopwords = {
    for (final r in _db.select('SELECT word FROM search_stopword')) r['word'] as String,
  };
  late final int _verseCount = _db.select('SELECT count(*) AS n FROM verse_fts').first['n'] as int;

  static final _ref = RegExp(
    r'^\s*(?:bg|gita|gītā)?\s*(\d{1,2})\s*[.:\-\s]\s*(\d{1,2})\s*$',
    caseSensitive: false,
  );
  // Same as _REF in retrieval.py: references anywhere in a question.
  static final _refAnywhere = RegExp(
    r'(?:chapter\s*(\d{1,2})\s*,?\s*verse\s*(\d{1,2}))|(?<![\d.])(\d{1,2})\s*[.:]\s*(\d{1,2})(?![\d])',
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

    final literal = _literal(q);
    final (conceptScores, matched) = _conceptScores(q);
    final hasConcepts = matched.values.any((w) => w == 1.0);
    final rankings = {
      'explicit': _explicit(q),
      'concept': _ranked(conceptScores),
      'lexical': _ranked(_lexicalScores(q, matched)),
      'literal': literal.keys.toList(),
    };
    final fused = <String, double>{};
    final via = <String, Set<String>>{};
    for (final MapEntry(key: channel, value: ranked) in rankings.entries) {
      var w = _channelWeights[channel]!;
      if (channel == 'lexical' && hasConcepts) w = lexicalWeightWithConcepts;
      for (var rank = 0; rank < ranked.length && rank < 200; rank++) {
        fused[ranked[rank]] = (fused[ranked[rank]] ?? 0) + w / (rrfK + rank + 1);
        (via[ranked[rank]] ??= {}).add(channel);
      }
    }
    final order = fused.keys.toList()
      ..sort((a, b) {
        final c = fused[b]!.compareTo(fused[a]!);
        return c != 0 ? c : _compareIds(a, b);
      });
    final direct = [
      for (final e in matched.entries)
        if (e.value == 1.0) e.key,
    ];
    return [
      for (final vid in order.take(limit))
        _hit(vid, literal[vid], via[vid]!, [
          for (final c in direct)
            if (concepts.byId[c]!.verses.containsKey(vid)) c,
        ]),
    ];
  }

  SearchHit _hit(String vid, SearchHit? literal, Set<String> via, List<String> linked) {
    if (literal != null) {
      return SearchHit(verseId: vid, field: literal.field, snippet: literal.snippet, concepts: linked);
    }
    final field = via.contains('explicit')
        ? MatchField.reference
        : via.contains('concept')
        ? MatchField.concept
        : MatchField.keywords;
    return SearchHit(verseId: vid, field: field, concepts: linked);
  }

  @override
  List<SearchHit> topic(String conceptId, {int limit = 50}) {
    final entry = concepts.byId[conceptId];
    if (entry == null) return const [];
    final ranked = entry.verses.keys.toList()
      ..sort((a, b) {
        final c = entry.verses[b]!.compareTo(entry.verses[a]!);
        return c != 0 ? c : _compareIds(a, b);
      });
    return [
      for (final vid in ranked.take(limit))
        if (verseExists(vid)) SearchHit(verseId: vid, field: MatchField.concept, concepts: [conceptId]),
    ];
  }

  @override
  List<ConceptEntry> topics() => concepts.entries;

  @override
  List<ConceptEntry> conceptsOf(String query) => [
    for (final e in concepts.match(query).entries)
      if (e.value == 1.0) concepts.byId[e.key]!,
  ];

  // -- channels ---------------------------------------------------------------

  List<String> _explicit(String q) {
    final out = <String>[];
    for (final m in _refAnywhere.allMatches(q)) {
      final (ch, v) = m.group(1) != null ? (m.group(1)!, m.group(2)!) : (m.group(3)!, m.group(4)!);
      final id = '${int.parse(ch)}.${int.parse(v)}';
      if (verseExists(id) && !out.contains(id)) out.add(id);
    }
    return out;
  }

  (Map<String, double>, Map<String, double>) _conceptScores(String q) {
    final matched = concepts.match(q);
    var scores = <String, double>{};
    for (final MapEntry(key: cid, value: qw) in matched.entries) {
      for (final MapEntry(key: vid, value: w)
          in (concepts.byId[cid]?.verses ?? const <String, double>{}).entries) {
        scores[vid] = (scores[vid] ?? 0) + qw * w;
      }
    }
    if (scores.isNotEmpty) {
      // A verse inside a passage on the topic outranks a passing mention.
      final smoothed = <String, double>{};
      for (final vid in {...scores.keys, for (final v in scores.keys) ..._neighbours(v)}) {
        final around = _neighbours(vid).fold(0.0, (s, n) => s + (scores[n] ?? 0)) / 2;
        smoothed[vid] = (scores[vid] ?? 0) + passageSmoothing * around;
      }
      scores = smoothed;
    }
    return (scores, matched);
  }

  List<String> _neighbours(String vid) {
    final [ch, v] = vid.split('.');
    return [
      for (final n in [int.parse(v) - 1, int.parse(v) + 1])
        if (verseExists('$ch.$n')) '$ch.$n',
    ];
  }

  Map<String, double> _lexicalScores(String q, Map<String, double> matched) {
    final raw = tokens(q);
    final english = <String, double>{};
    for (final w in normalizeEn(q)) {
      if (!_stopwords.contains(w)) english[w] = 1.0;
    }
    for (final MapEntry(key: cid, value: qw) in matched.entries) {
      final entry = concepts.byId[cid];
      if (entry == null || qw < 1.0) continue;
      final saKey = loose(entry.termSa).split(' ').where((w) => w.isNotEmpty).join(' ');
      for (final k in entry.strong) {
        if (k.language != 'en' || k.words.join(' ') == saKey) continue;
        for (final w in k.words) {
          if (!_stopwords.contains(w)) english.putIfAbsent(w, () => expansionWeight);
        }
      }
    }
    final scores = <String, double>{};
    void bm25(String match, double qw) {
      for (final r in _db.select(
        'SELECT verse_id, bm25(verse_fts) AS s FROM verse_fts WHERE verse_fts MATCH ?',
        [match],
      )) {
        final vid = r['verse_id'] as String;
        scores[vid] = (scores[vid] ?? 0) - qw * (r['s'] as num).toDouble();
      }
    }

    final known = <String>{};
    for (final MapEntry(key: w, value: qw) in english.entries) {
      final before = scores.length;
      bm25('{english_stem roman_loose} : "${w.replaceAll('"', '')}"', qw);
      if (scores.length > before || _hasWord(w)) known.add(w);
    }
    for (final t in raw.where(isTelugu).toSet()) {
      bm25('{translation explanation} : "${t.replaceAll('"', '')}"', 1.0);
    }
    // Sanskrit in Roman letters, inside the verse's joined-up text.
    final roman = loose(raw.where((t) => !isTelugu(t)).join(' ')).split(' ');
    for (final w in roman.toSet()) {
      if (w.length < minSanskritToken || known.contains(w) || _hasWord(w)) continue;
      final hits = [
        for (final r in _db.select('SELECT verse_id FROM verse_fts_sub WHERE roman_loose MATCH ?', ['"$w"']))
          r['verse_id'] as String,
      ];
      if (hits.isEmpty || hits.length > _verseCount ~/ 10) continue;
      final idf = math.log(1 + _verseCount / hits.length);
      for (final vid in hits) {
        scores[vid] = (scores[vid] ?? 0) + sanskritWeight * idf;
      }
    }
    return scores;
  }

  /// Whether [w] is a whole word of the keyword index (the server's vocabulary).
  bool _hasWord(String w) => _db.select('SELECT 1 FROM verse_fts WHERE verse_fts MATCH ? LIMIT 1', [
    '{english_stem roman_loose} : "${w.replaceAll('"', '')}"',
  ]).isNotEmpty;

  /// Search as typed: every word must match, the last as a prefix.
  Map<String, SearchHit> _literal(String q) {
    final hits = <String, SearchHit>{};
    void add(Iterable<SearchHit> found) {
      for (final h in found) {
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
    return hits;
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

  static List<String> _ranked(Map<String, double> scores) => scores.keys.toList()
    ..sort((a, b) {
      final c = scores[b]!.compareTo(scores[a]!);
      return c != 0 ? c : _compareIds(a, b);
    });

  static int _compareIds(String a, String b) {
    final [ac, av] = a.split('.').map(int.parse).toList();
    final [bc, bv] = b.split('.').map(int.parse).toList();
    return ac != bc ? ac.compareTo(bc) : av.compareTo(bv);
  }

  static const _columns = {
    'sanskrit': 1,
    'iast': 2,
    'roman_loose': 3,
    'telugu_script': 4,
    'translation': 5,
    'explanation': 6,
    'english_stem': 7,
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
